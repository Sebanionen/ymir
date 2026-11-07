// Text hygiene: cleanText() on every agent and source string, and markdown that keeps list structure but renders
// lists with CSS marks instead of characters.
import DOMPurify from "dompurify";
import { marked } from "marked";
import { cleanText } from "@dna/sdk";

export const clean = (text: unknown): string =>
  typeof text === "string"
    ? cleanText(text)
    : text === undefined || text === null
      ? ""
      : cleanText(String(text));

/** cleanText per line, keeping list markers, headings, quotes and code fences intact. */
export function cleanMarkdown(text: string): string {
  let fenced = false;
  return text
    .split("\n")
    .map((line) => {
      if (/^\s*```/.test(line)) {
        fenced = !fenced;
        return line;
      }
      if (fenced) return line;
      const m = line.match(/^(\s*(?:[-*+]|\d+[.)])\s+|\s*#{1,6}\s+|\s*>\s*)?(.*)$/);
      return (m?.[1] ?? "") + cleanText(m?.[2] ?? line);
    })
    .join("\n");
}

export function markdown(text: string): string {
  return DOMPurify.sanitize(
    marked.parse(cleanMarkdown(text), { async: false, gfm: true, breaks: true }) as string,
    { ADD_ATTR: ["target"] },
  );
}

export function shortArgs(args: unknown, max = 70): string {
  if (!args || typeof args !== "object") return "";
  const parts = Object.entries(args as Record<string, unknown>).map(
    ([k, v]) => `${k} ${typeof v === "string" ? v : JSON.stringify(v)}`,
  );
  const joined = clean(parts.join(", "));
  return joined.length > max ? `${joined.slice(0, max)} more` : joined;
}
