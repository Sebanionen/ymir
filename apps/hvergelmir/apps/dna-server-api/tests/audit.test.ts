import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import type { HfsScores } from "@dna/sdk";
import { auditSweep } from "../src/news/audit.ts";
import type { App } from "../src/runtime.ts";
import { fauxApp } from "./helpers.ts";

let app: App;
let cleanup: () => Promise<void>;
before(async () => ({ app, cleanup } = await fauxApp({ DNA_FIXTURE_SET: "news" })));
after(() => cleanup());

const hfs: HfsScores = {
  hype: 10,
  facts: 60,
  signal: 80,
  primary: "signal",
  labels: ["signal", "facts"],
  ranked: [
    { category: "signal", score: 80, confidence: 0 },
    { category: "facts", score: 60, confidence: 0 },
    { category: "hype", score: 10, confidence: 0 },
  ],
  suspectCombo: false,
};

test("the audit wants an hfs classification from this sweep for every presented news card", () => {
  const store = app.store;
  const sweep = store.sweeps.create({
    requestId: "audit:news",
    trigger: "test",
    status: "running",
  });
  const [a, b] = ["a", "b"].map(
    (k) =>
      store.news.upsertItem({ sweepId: sweep.id, url: `https://example.com/${k}`, title: k }).item
        .id,
  );
  for (const itemId of [a, b])
    store.news.addCard({
      kind: "news",
      component: "brief",
      props: { title: "t", summary: "s" },
      itemId,
      toolCallId: `audit:news:${itemId}`,
      sweepId: sweep.id,
    });
  store.sweeps.update(sweep.id, { candidates: 2, status: "completed" });
  const step = "hfs for every presented item";
  store.news.addClassification({ itemId: a, command: "hfs", version: 1, hfs, sweepId: sweep.id });
  assert.ok(auditSweep(store, sweep.id)!.missing.includes(step));
  store.news.addClassification({ itemId: b, command: "hfs", version: 1, hfs, sweepId: sweep.id });
  assert.ok(!auditSweep(store, sweep.id)!.missing.includes(step));
});
