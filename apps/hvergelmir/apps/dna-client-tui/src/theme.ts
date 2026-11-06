// Truecolor theme matching the browser: dark, one pink accent, green facts, amber hype.
import type { EditorTheme, MarkdownTheme, SelectListTheme } from "@earendil-works/pi-tui";

const rgb = (hex: string) => {
  const n = parseInt(hex.slice(1), 16);
  return `${(n >> 16) & 255};${(n >> 8) & 255};${n & 255}`;
};
const fg = (hex: string) => (s: string) => `\x1b[38;2;${rgb(hex)}m${s}\x1b[39m`;
const wrap = (on: string, off: string) => (s: string) => `\x1b[${on}m${s}\x1b[${off}m`;

export const c = {
  accent: fg("#f386a1"),
  muted: fg("#9a9a9a"),
  faint: fg("#6a6a6a"),
  text: fg("#f4f4f2"),
  signal: fg("#f386a1"),
  facts: fg("#57c48a"),
  hype: fg("#f0a640"),
  ok: fg("#57c48a"),
  warn: fg("#f0a640"),
  err: fg("#e5675a"),
  bold: wrap("1", "22"),
  italic: wrap("3", "23"),
  underline: wrap("4", "24"),
  strike: wrap("9", "29"),
};

export const markdownTheme: MarkdownTheme = {
  heading: (s) => c.bold(c.text(s)),
  link: c.accent,
  linkUrl: c.muted,
  code: c.hype,
  codeBlock: c.text,
  codeBlockBorder: c.faint,
  quote: c.muted,
  quoteBorder: c.faint,
  hr: c.faint,
  listBullet: c.accent,
  bold: c.bold,
  italic: c.italic,
  strikethrough: c.strike,
  underline: c.underline,
};

export const selectTheme: SelectListTheme = {
  selectedPrefix: c.accent,
  selectedText: (s) => c.bold(c.accent(s)),
  description: c.muted,
  scrollInfo: c.muted,
  noMatch: c.muted,
};

export const editorTheme: EditorTheme = { borderColor: c.faint, selectList: selectTheme };
