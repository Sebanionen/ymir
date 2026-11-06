// Read a card's props safely: strings are cleaned, lists are lists, anything else is skipped.
import { clean } from "../../client/text";

export function text(props: Record<string, unknown>, key: string): string {
  const v = props[key];
  if (typeof v === "string" || typeof v === "number") return clean(String(v));
  if (v && typeof v === "object" && !Array.isArray(v)) {
    const o = v as Record<string, unknown>;
    return clean(String(o.text ?? o.summary ?? o.name ?? o.title ?? ""));
  }
  return "";
}

export function list(props: Record<string, unknown>, key: string): string[] {
  const v = props[key];
  if (Array.isArray(v))
    return v
      .map((x) =>
        typeof x === "string"
          ? clean(x)
          : x && typeof x === "object"
            ? clean(
                String(
                  (x as Record<string, unknown>).text ??
                    (x as Record<string, unknown>).title ??
                    JSON.stringify(x),
                ),
              )
            : clean(String(x)),
      )
      .filter(Boolean);
  if (typeof v === "string" && v.trim()) return [clean(v)];
  return [];
}

export function events(props: Record<string, unknown>): { date: string; text: string }[] {
  const v = props.events;
  if (!Array.isArray(v)) return [];
  return v.map((e) =>
    e && typeof e === "object"
      ? {
          date: clean(String((e as Record<string, unknown>).date ?? "")),
          text: clean(String((e as Record<string, unknown>).text ?? "")),
        }
      : { date: "", text: clean(String(e)) },
  );
}

export function side(props: Record<string, unknown>, key: string): { name: string; text: string } {
  const v = props[key];
  if (v && typeof v === "object" && !Array.isArray(v)) {
    const o = v as Record<string, unknown>;
    return {
      name: clean(String(o.name ?? o.title ?? "")),
      text: clean(String(o.text ?? o.summary ?? o.body ?? "")),
    };
  }
  return { name: "", text: clean(String(v ?? "")) };
}
