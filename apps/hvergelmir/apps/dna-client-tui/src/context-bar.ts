// ▕██████░░░░│░░░░░░┃░░▏ 64k  bg 100k  force 200k: used tokens, the background point (│) and the force point (┃).
import { k } from "@dna/sdk";
import { c } from "./theme.ts";

export function contextBar(
  cells: number,
  used: number,
  window: number,
  background: number,
  force: number,
): string {
  const n = Math.max(8, cells);
  const at = (tokens: number) =>
    Math.min(n - 1, Math.max(0, Math.round((tokens / Math.max(1, window)) * n)));
  const filled = Math.min(n, Math.round((used / Math.max(1, window)) * n));
  const bg = at(background);
  const fp = at(force);
  let bar = "";
  for (let i = 0; i < n; i++) {
    if (i === fp) bar += c.text("┃");
    else if (i === bg) bar += c.accent("│");
    else bar += i < filled ? (used >= background ? c.accent("█") : c.muted("█")) : c.faint("░");
  }
  return `${c.faint("▕")}${bar}${c.faint("▏")} ${k(used)}  ${c.muted("bg")} ${k(background)}  ${c.muted("force")} ${k(force)}`;
}
