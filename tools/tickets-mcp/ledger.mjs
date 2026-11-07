#!/usr/bin/env node
// ledger.mjs — the plan ledger, read from the FILES (plan 210 P1).
//
// One module, two consumers: the Skuld MCP door (server.mjs) and the command below, so the
// shelf can be proved by a command instead of by a client.
//
//   node tools/tickets-mcp/ledger.mjs            # every plan, with its number, namespace, status and file
//   node tools/tickets-mcp/ledger.mjs --pending  # the ones that wait his word
//
// Why a module and not the table: the `plans` table holds NOTHING and never has (measured
// 2026-11-06 — `plans 0` against 275 plan files), and the door answered `(no plans)` as though
// the shelf were bare. The ledger is a SHELF OF FILES; a table is not a record (Rule 06).
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

// ── THE PLAN LEDGER: the FILES are the truth (plan 210 P1) ─────────────────────
//
// Why: the `plans` table holds NOTHING and never has (measured 2026-11-06 — `plans 0` against
// 275 plan files), while this door answered `(no plans)` as though the shelf were bare. The
// native `skuld_plan` tool reads the ledger's files; this door read a table nobody writes. Two
// surfaces, one empty — so the MCP now reads the SAME shelf, and `plans_create` refuses rather
// than growing a second store (Rule 06: a record is appended and carried; a table is not one).
const LEDGER_HOME = process.env.YMIR_HOME || path.join(os.homedir(), "Documents", "ymirhome");

function ledgerShelves() {  // every `plans` shelf in the home; nobody's list hardcoded
  const out = [];
  const skip = new Set(["node_modules", ".git", "reference", "old-plans"]);
  const walk = (dir, depth) => {
    if (depth > 5) return;
    let ents = [];
    try { ents = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const e of ents) {
      if (!e.isDirectory() || skip.has(e.name)) continue;
      const p = path.join(dir, e.name);
      if (e.name === "plans") out.push(p);
      else walk(p, depth + 1);
    }
  };
  walk(path.join(LEDGER_HOME, "svartalfaheim"), 0);
  for (const sub of ["plans", "plans/fleet", "plans/heimdall", "plans/nidavellir", "plans/termux"]) {
    const p = path.join(LEDGER_HOME, "hodd", sub);
    try { if (fs.statSync(p).isDirectory()) out.push(p); } catch {}
  }
  return out;
}

function planStatus(text) {  // a STATUS WORD, never a fragment of the sentence around it
  const head = text.split("\n").slice(0, 80).join("\n");
  const KNOWN = ["built","proposed","drafted","draft","open","live","approved","shipped","done",
                 "paused","blocked","awaiting","running","active","planned","superseded","retired"];
  const word = (str) => {
    for (const k of KNOWN) if (new RegExp("\\b" + k + "\\b", "i").test(str)) return k;
    return null;
  };
  const m = head.match(/status[^A-Za-z\n]{0,24}[*"\s\[]*([A-Za-z]+)/i);
  if (m) { const w = word(m[1]); if (w) return w; }
  const anywhere = word(head);
  return anywhere || "unknown";
}

function planRow(file, shelf) {
  let text = "";
  try { text = fs.readFileSync(file, "utf8"); } catch { return null; }
  const lines = text.split("\n");
  let num = null, title = null;
  for (const l of lines.slice(0, 12)) {
    const m = l.match(/^#\s+(?:Plan\s+)?(\d+)?\s*[-–—:]?\s*(.*)$/);
    if (m && (m[1] || m[2])) { if (m[1]) num = Number(m[1]); title = (m[2] || "").trim(); break; }
  }
  if (!num) { const b = path.basename(file).match(/^(\d+)/); if (b) num = Number(b[1]); }
  if (!title) title = path.basename(file, ".md");
  const rel = path.relative(LEDGER_HOME, file);
  // A namespace is REALM/PROJECT for the ledger, and `hodd` for the home's own shelves —
  // the shelf path carries `projects/` and `thoughts/` as scaffolding, never as a namespace.
  const segs = rel.split(path.sep);
  let ns;
  if (segs[0] === "hodd") ns = "hodd";
  else if (segs[0] === "svartalfaheim") {
    const i = segs.indexOf("plans");
    const body = segs.slice(1, i < 0 ? segs.length : i).filter(x => x !== "projects" && x !== "thoughts");
    ns = body.join("/") || "svartalfaheim";
  } else ns = segs[0] || "?";
  return { num: num || 0, ns, title, status: planStatus(text), file, rel };
}

function ledgerPlans() {  // one read of every shelf, sorted by number then namespace
  const seen = new Set(), out = [];
  for (const shelf of ledgerShelves()) {
    let names = [];
    try { names = fs.readdirSync(shelf); } catch { continue; }
    for (const n of names) {
      if (!n.endsWith(".md")) continue;
      if (["README.md", "queue.md", "questions.md", "register.md"].includes(n)) continue;
      const f = path.join(shelf, n);
      if (seen.has(f)) continue;
      seen.add(f);
      const row = planRow(f, shelf);
      if (row) out.push(row);
    }
  }
  out.sort((a, b) => a.num - b.num || a.ns.localeCompare(b.ns));
  return out;
}

function ledgerLine(r) { return `${r.num}|${r.ns}|${r.status}|${r.rel}|${r.title}`; }

function ledgerRefusal() {
  return "refused: the plan ledger is a SHELF OF FILES, not this table — this door reads it and never writes it. "
    + `Open a plan with bin/records/plan.sh (or the ymir_plan door); the shelf is `
    + `${path.join(LEDGER_HOME, "svartalfaheim", "<realm>", "projects", "<project>", "plans")}.`;
}


export { LEDGER_HOME, ledgerShelves, ledgerPlans, ledgerLine, ledgerRefusal };

// A door to read the shelf with no client and no SDK:
//   node tools/tickets-mcp/ledger.mjs [--pending]     exit 0 with rows · 3 when the shelf is unreadable
if (process.argv[1] && import.meta.url === new URL("file://" + path.resolve(process.argv[1])).href) {
  const pending = process.argv.includes("--pending");
  let plans = ledgerPlans();
  if (pending) plans = plans.filter(r => /proposed|drafted|draft|open|awaiting/i.test(r.status));
  const head = pending ? "plans_awaiting" : "plans";
  process.stdout.write(`${head}[${plans.length}]{number,namespace,status,file,title}:\n`
    + plans.map(r => "  " + ledgerLine(r)).join("\n") + "\n");
  process.exit(plans.length ? 0 : 3);
}
