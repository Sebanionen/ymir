// A tool's parameters as rows for people: name, type, required, description and enum values, from its JSON schema.
import type { ToolParam } from "@dna/sdk";

type Schema = {
  type?: string;
  description?: string;
  const?: unknown;
  anyOf?: Schema[];
  items?: Schema;
  properties?: Record<string, Schema>;
  required?: string[];
  minimum?: number;
  maximum?: number;
  minLength?: number;
  maxLength?: number;
  minItems?: number;
  maxItems?: number;
};

function typeOf(s: Schema): { type: string; values?: string[] } {
  const literals = s.anyOf?.filter((x) => x.const !== undefined);
  if (literals?.length && literals.length === s.anyOf!.length)
    return { type: "enum", values: literals.map((x) => String(x.const)) };
  if (s.type === "array") return { type: `array of ${s.items ? typeOf(s.items).type : "any"}` };
  if (s.type === "object" && !s.properties) return { type: "object" };
  return { type: s.type ?? "any" };
}

function bounds(s: Schema): string | undefined {
  const parts = [
    s.minimum !== undefined ? `min ${s.minimum}` : "",
    s.maximum !== undefined ? `max ${s.maximum}` : "",
    s.minLength !== undefined ? `at least ${s.minLength} chars` : "",
    s.maxLength !== undefined ? `at most ${s.maxLength} chars` : "",
    s.minItems !== undefined ? `at least ${s.minItems} items` : "",
    s.maxItems !== undefined ? `at most ${s.maxItems} items` : "",
  ].filter(Boolean);
  return parts.length ? parts.join(", ") : undefined;
}

export function toolParams(
  schema: unknown,
  enums: Record<string, readonly string[]> = {},
): ToolParam[] {
  const s = schema as Schema;
  const required = new Set(s.required ?? []);
  return Object.entries(s.properties ?? {}).map(([name, p]) => {
    const t = typeOf(p);
    const values = enums[name] ? [...enums[name]] : t.values;
    const description = [p.description, bounds(p)].filter(Boolean).join(". ") || undefined;
    return {
      name,
      type: values ? "enum" : t.type,
      required: required.has(name),
      ...(description ? { description } : {}),
      ...(values ? { values } : {}),
    };
  });
}
