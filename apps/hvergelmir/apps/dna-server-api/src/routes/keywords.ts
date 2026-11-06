// Keywords per section (topic, hype, facts, signal) with weights.
import type { Keyword } from "@dna/sdk";
import { int, invalid, notFound } from "../errors.ts";
import { clamp } from "../db/repos/taste.ts";
import { bodyOf, bool, num, oneOf, str, type Handlers, type RouteDeps } from "./types.ts";

const KINDS = ["topic", "hype", "facts", "signal"] as const;

export function keywordRoutes({
  app,
}: RouteDeps): Handlers<"keywords.list" | "keywords.add" | "keywords.update" | "keywords.remove"> {
  const { store } = app;
  return {
    "keywords.list": (req, res) =>
      res.json(
        store.taste.keywords(
          oneOf(req.query.kind, "kind", KINDS, true) as Keyword["kind"] | undefined,
        ),
      ),
    "keywords.add": (req, res) => {
      const body = bodyOf(req);
      const kind = oneOf(body.kind, "kind", KINDS)!;
      const term = str(body, "term", { max: 80 });
      if (store.taste.findKeyword(kind, term)) throw invalid(`${kind} already has "${term}"`);
      const keyword = store.taste.addKeyword(
        kind,
        term,
        clamp(num(body, "weight", { min: 0.1, max: 2 }) ?? 1),
      );
      app.log.info("taste.keyword_added", { id: keyword.id, kind, term });
      res.status(201).json(keyword);
    },
    "keywords.update": (req, res) => {
      const body = bodyOf(req);
      const keyword = store.taste.updateKeyword(int(req.params.id, "id"), {
        weight: num(body, "weight", { min: 0.1, max: 2 }),
        enabled: bool(body, "enabled"),
        term: str(body, "term", { max: 80, optional: true }),
      });
      if (!keyword) throw notFound(`No keyword ${req.params.id}`);
      res.json(keyword);
    },
    "keywords.remove": (req, res) => {
      if (!store.taste.removeKeyword(int(req.params.id, "id")))
        throw notFound(`No keyword ${req.params.id}`);
      res.json({ ok: true });
    },
  };
}
