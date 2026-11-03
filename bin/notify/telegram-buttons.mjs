#!/usr/bin/env node
// telegram-buttons.mjs — the one place that knows Telegram's button grammar.
//
// The bridge parses two wrappers and silently drops everything else: a footer
// `<!-- telegram_button <payload> -->` at column zero, and a column-zero
// ```telegram_button fence for in-body rows. A payload is either JSON or the
// positional CML matrix `[{label|prompt|style|disabled}…]`. Anything else is
// ignored WITHOUT an error, which is how a reply full of controls arrives as a
// wall of prose.
//
//   node telegram-buttons.mjs emit  --button "label|prompt" … [--in-body] [--allow-single]
//   node telegram-buttons.mjs check <file|-> [--json]
//
// Exit: 0 ok, 1 a finding, 2 usage.
//
// Rules encoded here (from the telegram-bridge skill, plus the house's own):
//   · enabled CML requires a prompt; label omitted is allowed ({|prompt})
//   · style is primary | success | danger, in the third position
//   · the fourth position is 1/true (disabled) or 0/false
//   · at most 8 buttons in one row (Telegram's own limit)
//   · the house asks for 2–6 buttons when a reply leaves a decision
//   · every wrapper is column zero and complete — a malformed one activates nothing

import { readFileSync } from "node:fs";

const MAX_PER_ROW = 8;
const HOUSE_MIN = 2;
const HOUSE_MAX = 6;
const LABEL_MAX = 64;
const STYLES = new Set(["primary", "success", "danger"]);

function die(code, msg) {
  process.stderr.write(`${msg}\n`);
  process.exit(code);
}

function args(argv) {
  const out = { _: [], button: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (!a.startsWith("--")) {
      out._.push(a);
      continue;
    }
    const [k, inline] = a.slice(2).split("=", 2);
    const value = inline !== undefined ? inline : argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[++i] : "true";
    if (k === "button") out.button.push(value);
    else out[k] = value;
  }
  return out;
}

/** Split on a delimiter that is not escaped, honouring the CML escapes \| \} \\ . */
function splitUnescaped(text, delimiter) {
  const parts = [];
  let cur = "";
  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];
    if (ch === "\\" && i + 1 < text.length) {
      const next = text[i + 1];
      if (next === delimiter || next === "}" || next === "\\") {
        cur += next;
        i += 1;
        continue;
      }
      cur += ch;
      continue;
    }
    if (ch === delimiter) {
      parts.push(cur);
      cur = "";
      continue;
    }
    cur += ch;
  }
  parts.push(cur);
  return parts;
}

function unescapeCell(text) {
  return text.replace(/\\([|}])/g, "$1").replace(/\\\\/g, "\\").trim();
}

function parseCell(raw, where, findings) {
  const parts = splitUnescaped(raw, "|").map((p) => unescapeCell(p));
  if (parts.length > 4) {
    findings.push({ where, fault: `a cell has ${parts.length} fields; the grammar allows label|prompt|style|disabled` });
    return null;
  }
  let label = parts.length === 0 ? "" : parts[0];
  let prompt;
  if (parts.length === 1) prompt = label;
  else prompt = parts[1] ?? "";
  const style = parts[2] || "";
  const disabledRaw = (parts[3] || "").toLowerCase();
  const disabled = disabledRaw === "1" || disabledRaw === "true";
  if (style && !STYLES.has(style)) findings.push({ where, fault: `style '${style}' is not primary|success|danger` });
  if (!disabled && !prompt.trim()) findings.push({ where, fault: "an enabled button needs a prompt — it would do nothing when tapped" });
  if (label.length > LABEL_MAX) findings.push({ where, fault: `label is ${label.length} chars; Telegram allows ${LABEL_MAX}` });
  if (!label.trim() && !prompt.trim()) findings.push({ where, fault: "a button has neither label nor prompt" });
  return { label: label || prompt, prompt, style, disabled };
}

/** Parse a CML matrix: `[ row… ]` where a row is `{cell}` or `[ {cell} … ]`. */
function parseCml(payload, findings) {
  let i = 0;
  const rows = [];
  const skip = () => {
    while (i < payload.length && /\s|,/.test(payload[i])) i += 1;
  };
  const parseCellAt = () => {
    if (payload[i] !== "{") {
      findings.push({ where: `offset ${i}`, fault: "expected '{' to open a button cell" });
      i = payload.length;
      return null;
    }
    let depth = 0;
    let start = i + 1;
    let j = i;
    for (; j < payload.length; j += 1) {
      const ch = payload[j];
      if (ch === "\\") {
        j += 1;
        continue;
      }
      if (ch === "{") depth += 1;
      else if (ch === "}") {
        depth -= 1;
        if (depth === 0) break;
      }
    }
    if (depth !== 0) {
      findings.push({ where: `offset ${i}`, fault: "a button cell is never closed with '}'" });
      i = payload.length;
      return null;
    }
    const raw = payload.slice(start, j);
    i = j + 1;
    return parseCell(raw, `cell at offset ${start}`, findings);
  };
  skip();
  if (payload[i] !== "[") {
    findings.push({ where: "payload", fault: "a CML payload must open a matrix with '['" });
    return [];
  }
  i += 1;
  for (;;) {
    skip();
    if (i >= payload.length) {
      findings.push({ where: "payload", fault: "the matrix is never closed with ']'" });
      break;
    }
    if (payload[i] === "]") {
      i += 1;
      break;
    }
    if (payload[i] === "{") {
      const cell = parseCellAt();
      if (cell) rows.push([cell]);
      continue;
    }
    if (payload[i] === "[") {
      i += 1;
      const row = [];
      for (;;) {
        skip();
        if (i >= payload.length) {
          findings.push({ where: "payload", fault: "a row is never closed with ']'" });
          break;
        }
        if (payload[i] === "]") {
          i += 1;
          break;
        }
        if (payload[i] !== "{") {
          findings.push({ where: `offset ${i}`, fault: "a row holds button cells only" });
          i = payload.length;
          break;
        }
        const cell = parseCellAt();
        if (cell) row.push(cell);
      }
      if (row.length) rows.push(row);
      continue;
    }
    findings.push({ where: `offset ${i}`, fault: "unexpected character in a CML matrix" });
    break;
  }
  skip();
  if (i < payload.length) findings.push({ where: `offset ${i}`, fault: "trailing text after the matrix — the wrapper must hold one complete payload" });
  return rows;
}

function fromJson(payload, findings) {
  let value;
  try {
    value = JSON.parse(payload);
  } catch (err) {
    findings.push({ where: "payload", fault: `neither CML nor JSON (${err.message})` });
    return [];
  }
  const rows = [];
  const cell = (obj, where) => {
    if (!obj || typeof obj !== "object") {
      findings.push({ where, fault: "a button must be an object" });
      return null;
    }
    const label = String(obj.label ?? "");
    const prompt = String(obj.prompt ?? "");
    const style = obj.style ? String(obj.style) : "";
    const disabled = Boolean(obj.disabled);
    if (style && !STYLES.has(style)) findings.push({ where, fault: `style '${style}' is not primary|success|danger` });
    if (!disabled && !prompt.trim()) findings.push({ where, fault: "an enabled button needs a prompt" });
    return { label: label || prompt, prompt, style, disabled };
  };
  if (Array.isArray(value)) {
    if (value.length && Array.isArray(value[0])) {
      value.forEach((row, r) => rows.push(row.map((c, i2) => cell(c, `row ${r} cell ${i2}`)).filter(Boolean)));
    } else {
      value.forEach((c, i2) => {
        const parsed = cell(c, `cell ${i2}`);
        if (parsed) rows.push([parsed]);
      });
    }
  } else if (value && typeof value === "object") {
    const parsed = cell(value, "cell 0");
    if (parsed) rows.push([parsed]);
  } else {
    findings.push({ where: "payload", fault: "a JSON payload is a button object or an array of them" });
  }
  return rows;
}

function parsePayload(payload, findings) {
  const trimmed = payload.trim();
  if (!trimmed) {
    findings.push({ where: "payload", fault: "the wrapper is empty" });
    return [];
  }
  const rows = /^[[{]/.test(trimmed) && !/^\{\s*"/.test(trimmed) ? parseCml(trimmed, findings) : fromJson(trimmed, findings);
  rows.forEach((row, index) => {
    if (row.length > MAX_PER_ROW) findings.push({ where: `row ${index}`, fault: `${row.length} buttons in one row; Telegram allows ${MAX_PER_ROW}` });
  });
  const total = rows.reduce((n, row) => n + row.length, 0);
  if (total === 0) findings.push({ where: "payload", fault: "no buttons parsed" });
  return rows;
}

function scan(text, optsSingle = false, optsMany = false) {
  const findings = [];
  const found = [];
  const lines = text.split("\n");
  const offsets = [];
  let at = 0;
  for (const line of lines) {
    offsets.push(at);
    at += line.length + 1;
  }

  // The colon form is the one that looks right and is silently dropped.
  text.split("\n").forEach((line, index) => {
    if (/^\s*<!--\s*telegram_button\s*:/.test(line)) {
      findings.push({
        line: index + 1,
        fault: "legacy colon form — the bridge ignores it. Use `<!-- telegram_button [{label|prompt}] -->`",
      });
    }
    if (/^\s+<!--\s*telegram_button\s/.test(line)) {
      findings.push({ line: index + 1, fault: "the comment is indented; a wrapper must start at column zero" });
    }
  });

  const footer = /^<!--\s*telegram_button\s+([\s\S]*?)\s*-->/gm;
  let m;
  while ((m = footer.exec(text)) !== null) {
    const line = text.slice(0, m.index).split("\n").length;
    const local = [];
    const rows = parsePayload(m[1], local);
    local.forEach((f) => findings.push({ line, ...f }));
    found.push({ kind: "footer", line, rows, ok: local.length === 0 });
  }

  const fence = /^```telegram_button\s*\n([\s\S]*?)\n```/gm;
  while ((m = fence.exec(text)) !== null) {
    const line = text.slice(0, m.index).split("\n").length;
    const local = [];
    const rows = parsePayload(m[1], local);
    local.forEach((f) => findings.push({ line, ...f }));
    found.push({ kind: "in-body", line, rows, ok: local.length === 0 });
  }

  const total = found.reduce((n, f) => n + f.rows.reduce((k, row) => k + row.length, 0), 0);
  if (total === 1 && optsSingle !== true) {
    findings.push({ line: 0, fault: "one button only — the house asks for 2–6 when a reply leaves a decision" });
  }
  if (total > HOUSE_MAX && optsMany !== true) {
    findings.push({ line: 0, fault: `${total} buttons; the house asks for at most ${HOUSE_MAX} (Telegram allows rows of ${MAX_PER_ROW})` });
  }
  return { found, findings, total };
}

function emit(opts) {
  if (!opts.button.length) die(2, "emit: at least one --button \"label|prompt\" is required");
  const findings = [];
  const cells = opts.button.map((spec, index) => {
    const parsed = parseCell(spec, `button ${index}`, findings);
    return parsed;
  });
  if (findings.length) {
    findings.forEach((f) => process.stderr.write(`refused: ${f.where} — ${f.fault}\n`));
    process.exit(1);
  }
  if (cells.length > HOUSE_MAX && opts["allow-many"] !== "true") {
    process.stderr.write(
      `refused: ${cells.length} buttons — the house asks for at most ${HOUSE_MAX} (pass --allow-many for a deliberate long row)\n`,
    );
    process.exit(1);
  }
  const chunk = (list, size) => {
    const out = [];
    for (let i = 0; i < list.length; i += size) out.push(list.slice(i, i + size));
    return out;
  };
  const cellText = (c) => {
    const style = c.style ? `|${c.style}` : "";
    const disabled = c.disabled ? "|1" : "";
    return `{${c.label}|${c.prompt}${style}${disabled}}`;
  };
  const rows = chunk(cells, MAX_PER_ROW);
  const payload =
    rows.length === 1 ? `[${rows[0].map(cellText).join("")}]` : `[${rows.map((r) => `[${r.map(cellText).join("")}]`).join("")}]`;
  if (opts["in-body"] === "true") process.stdout.write("```telegram_button\n" + payload + "\n```\n");
  else process.stdout.write(`<!-- telegram_button ${payload} -->\n`);
}

const [command, ...rest] = process.argv.slice(2);
const opts = args(rest);

if (command === "emit") {
  emit(opts);
} else if (command === "check") {
  const target = opts._[0] || "-";
  let text;
  try {
    text = target === "-" ? readFileSync(0, "utf8") : readFileSync(target, "utf8");
  } catch (err) {
    die(2, `check: cannot read ${target} (${err.message})`);
  }
  const result = scan(text, opts["allow-single"] === "true", opts["allow-many"] === "true");
  if (opts.json === "true") {
    process.stdout.write(JSON.stringify(result, null, 2) + "\n");
  } else {
    const lines = [`telegram_buttons[${result.found.length}]{kind,line,buttons,ok}:`];
    result.found.forEach((f) => {
      const n = f.rows.reduce((k, row) => k + row.length, 0);
      lines.push(`  "${f.kind}","${f.line}","${n}","${f.ok}"`);
    });
    if (result.findings.length) {
      lines.push(`findings[${result.findings.length}]{line,fault}:`);
      result.findings.forEach((f) => lines.push(`  "${f.line}","${String(f.fault).replace(/"/g, "'")}"`));
    }
    process.stdout.write(lines.join("\n") + "\n");
  }
  process.exit(result.findings.length ? 1 : 0);
} else {
  die(2, "usage: telegram-buttons.mjs emit|check …");
}
