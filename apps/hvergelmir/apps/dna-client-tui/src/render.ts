// Transcript items (from @dna/sdk, the same as the browser) as pi-tui components, cached by item id.
import {
  Container,
  Markdown,
  truncateToWidth,
  wrapTextWithAnsi,
  type Component,
} from "@earendil-works/pi-tui";
import { cleanText, ms, type ToolCallRow, type ToolCallView, type TranscriptItem } from "@dna/sdk";
import { c, markdownTheme } from "./theme.ts";

const SPIN = ["◐", "◓", "◑", "◒"];
/** Advanced by the app while a tool runs; running rows read it at render time. */
export const spinner = { frame: 0 };
/** Telemetry rows by provider call id, filled by the app: durations for finished calls. */
export const toolStats = { rows: new Map<string, ToolCallRow>() };
const TAIL = 4;
/** Cut to the width without an ellipsis: three dots never appear in the chrome. */
export const cut = (text: string, width: number) => truncateToWidth(text, width, "");

/** One styled line, cut to the width. */
export class Line implements Component {
  constructor(public text: string) {}
  render(width: number) {
    return [cut(this.text, width)];
  }
  invalidate() {}
}

/** Wrapped lines with a first-line prefix and a hanging indent. */
export class Wrapped implements Component {
  constructor(
    private text: string,
    private prefix = "",
    private style: (s: string) => string = (s) => s,
    private indent = "  ",
  ) {}
  render(width: number) {
    const inner = Math.max(1, width - Math.max(2, this.indent.length));
    const lines = this.text.split("\n").flatMap((l) => (l ? wrapTextWithAnsi(l, inner) : [""]));
    return lines.map((l, i) => cut((i ? this.indent : this.prefix) + this.style(l), width));
  }
  invalidate() {}
}

export class Stack implements Component {
  constructor(public parts: Component[] = []) {}
  render(width: number) {
    return this.parts.flatMap((p) => p.render(width));
  }
  invalidate() {
    for (const p of this.parts) p.invalidate();
  }
}

/** Lines of styled text, wrapped to the width. */
export class TextBlock implements Component {
  constructor(public lines: string[]) {}
  render(width: number) {
    return this.lines.flatMap((l) =>
      l ? wrapTextWithAnsi(l, Math.max(1, width)).map((x) => cut(x, width)) : [""],
    );
  }
  invalidate() {}
}

export function argsPreview(args: unknown): string {
  if (!args || typeof args !== "object") return "";
  return cleanText(
    Object.entries(args as Record<string, unknown>)
      .map(([k, v]) => `${k} ${typeof v === "string" ? v : JSON.stringify(v)}`)
      .join(", ")
      .replace(/\s+/g, " "),
  );
}

/** Markdown list markers become arrows, so lists never render dots or dashes. Code fences stay as written. */
export function agentText(text: string): string {
  let fenced = false;
  return text
    .split("\n")
    .map((l) => {
      if (/^\s*```/.test(l)) {
        fenced = !fenced;
        return l;
      }
      if (fenced || /^\s*(#|>)/.test(l)) return l;
      const m = l.match(/^(\s*)(?:[-*+]|\d+[.)])\s+(.*)$/);
      return m ? `${m[1]}▸ ${cleanText(m[2])}` : cleanText(l);
    })
    .join("\n");
}

export class ToolRow implements Component {
  constructor(
    private call: ToolCallView,
    private expand: boolean,
  ) {}
  render(width: number) {
    const s = this.call.status;
    const icon =
      s === "running"
        ? c.warn(SPIN[spinner.frame % SPIN.length])
        : s === "done"
          ? c.ok("✓")
          : s === "error"
            ? c.err("✗")
            : c.faint("○");
    const row = toolStats.rows.get(this.call.callId);
    const stats = row?.durationMs !== undefined ? c.faint(`  ${ms(row.durationMs)}`) : "";
    const head = cut(
      `  ${icon} ${c.bold(this.call.name)}${stats} ${c.muted(argsPreview(this.call.args))}`,
      width,
    );
    const body = cleanText(
      (this.call.result ?? this.call.output ?? "").replace(/<\/?harness>/g, ""),
    ).trim();
    if (!body || (!this.expand && s !== "error")) return [head];
    const all = body.split("\n");
    const shown = this.expand ? all : all.slice(0, TAIL);
    const lines = shown.flatMap((l) => (l ? wrapTextWithAnsi(l, Math.max(1, width - 6)) : [""]));
    const out = [
      head,
      ...lines.map((l) => cut(`      ${s === "error" ? c.err(l) : c.muted(l)}`, width)),
    ];
    if (all.length > shown.length)
      out.push(cut(c.faint(`      ${all.length - shown.length} more lines, ctrl+o`), width));
    return out;
  }
  invalidate() {}
}

class AssistantView extends Stack {
  private markdown = new Map<number, Markdown>();
  update(item: Extract<TranscriptItem, { kind: "assistant" }>, expand: boolean) {
    const parts: Component[] = [new Line("")];
    item.blocks.forEach((block, i) => {
      if (block.type === "text") {
        const text = agentText(block.text);
        let md = this.markdown.get(i);
        if (!md) {
          md = new Markdown(text, 0, 0, markdownTheme);
          this.markdown.set(i, md);
        } else md.setText(text);
        parts.push(md);
      } else if (block.type === "thinking") {
        parts.push(
          expand
            ? new Wrapped(cleanText(block.text), c.faint("∴ "), (s) => c.italic(c.faint(s)))
            : new Line(c.italic(c.faint("∴ thinking, ctrl+o to expand"))),
        );
      } else parts.push(new ToolRow(block.call, expand));
    });
    if (item.error) parts.push(new Line(c.err(`! ${cleanText(item.error)}`)));
    this.parts = parts;
  }
}

export function itemComponent(item: TranscriptItem, expand: boolean): Component {
  switch (item.kind) {
    case "user": {
      const sweep = item.text.match(/Run scheduled sweep (\d+)/);
      if (sweep)
        return new Stack([new Line(""), new Line(c.accent(`◷ Scheduled sweep ${sweep[1]}`))]);
      if (/The reader answered your taste question/.test(item.text))
        return new Stack([new Line(""), new Line(c.accent("◷ You answered a taste question"))]);
      const deep = item.text.match(/Deep research #(\d+): researcher (\d+) of (\d+) reported/);
      if (deep)
        return new Stack([
          new Line(""),
          new Line(
            c.accent(`◷ Deep research ${deep[1]}: researcher ${deep[2]} of ${deep[3]} reported`),
          ),
        ]);
      return new Stack([new Line(""), new Wrapped(cleanText(item.text), c.accent("› "), c.text)]);
    }
    case "assistant": {
      const view = new AssistantView();
      view.update(item, expand);
      return view;
    }
    case "tool-result":
      return new ToolRow(
        {
          callId: String(item.id),
          name: item.name,
          args: undefined,
          status: item.isError ? "error" : "done",
          result: item.text,
        },
        expand,
      );
    case "tool":
      return new ToolRow(item.call, expand);
    default: {
      const phase = (item.data as { phase?: string } | undefined)?.phase;
      return new Line(c.faint(`  ${phase ? `${phase} ` : ""}${cleanText(item.text)}`));
    }
  }
}

export class TranscriptView extends Container {
  private cache = new Map<string, { sig: string; component: Component }>();
  expand = false;

  update(items: readonly TranscriptItem[]) {
    const next = new Map<string, { sig: string; component: Component }>();
    this.clear();
    for (const item of items) {
      const key = `${item.kind}:${item.id}`;
      const sig = `${this.expand}|${JSON.stringify(item)}|${item.kind === "assistant" ? item.blocks.map((b) => (b.type === "tool" ? toolStats.rows.get(b.call.callId)?.durationMs : "")).join(",") : ""}`;
      let entry = this.cache.get(key);
      if (!entry || entry.sig !== sig) {
        if (entry && item.kind === "assistant" && entry.component instanceof AssistantView)
          entry.component.update(item, this.expand);
        else entry = { sig, component: itemComponent(item, this.expand) };
        entry.sig = sig;
      }
      next.set(key, entry);
      this.addChild(entry.component);
    }
    this.cache = next;
  }

  reset() {
    this.cache.clear();
    this.clear();
  }
}
