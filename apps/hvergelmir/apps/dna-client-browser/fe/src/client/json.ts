// JSON for people: pretty printed, HTML escaped, with spans for keys, strings, numbers, booleans and null.
const escape = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

const TOKEN =
  /("(?:\\u[a-fA-F0-9]{4}|\\[^u]|[^\\"])*"(\s*:)?|\b(?:true|false|null)\b|-?\d+(?:\.\d*)?(?:[eE][+-]?\d+)?)/g;

export function prettyJson(value: unknown): string {
  if (typeof value === "string") {
    try {
      return JSON.stringify(JSON.parse(value), null, 2);
    } catch {
      return value;
    }
  }
  return JSON.stringify(value, null, 2) ?? "undefined";
}

/** Highlighted HTML for v-html: every token is escaped before it is wrapped. */
export function highlightJson(value: unknown): string {
  return escape(prettyJson(value)).replace(TOKEN, (m) => {
    const kind = m.startsWith('"')
      ? m.trimEnd().endsWith(":")
        ? "key"
        : "string"
      : m === "true" || m === "false"
        ? "boolean"
        : m === "null"
          ? "null"
          : "number";
    return `<span class="json-${kind}">${m}</span>`;
  });
}
