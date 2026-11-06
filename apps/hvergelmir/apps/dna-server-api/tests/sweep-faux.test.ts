import assert from "node:assert/strict";
import { test } from "node:test";
import { startNewsSweep } from "../src/news/sweep.ts";
import { fauxApp, waitForSweep } from "./helpers.ts";

test("a faux sweep gathers, gates, researches, classifies and presents, and the audit is clean", async () => {
  const { app, cleanup } = await fauxApp({ DNA_FIXTURE_SET: "news" });
  try {
    const started = await startNewsSweep(app, app.main, app.ctx, {
      trigger: "test",
      requestId: "t:1",
    });
    assert.equal(started.status, "accepted");
    const sweep = await waitForSweep(app, started.sweep!.id);
    assert.equal(sweep.status, "completed");
    assert.deepEqual(
      sweep.phases.map((p) => `${p.phase}:${p.status}`),
      ["gather:done", "gate:done", "dedupe:done", "rank:done"],
    );
    assert.ok(sweep.gathered >= 8, `gathered ${sweep.gathered}`);
    assert.ok(sweep.kept < sweep.gathered, "jev rejected the off-topic and hype items");
    assert.deepEqual(sweep.audit?.missing, []);

    const cards = app.store.news.cards();
    const news = cards.filter((c) => c.kind === "news");
    assert.equal(news.length, 4);
    assert.ok(cards.every((c) => c.kind === "news"));
    assert.equal(
      cards.filter((c) => c.timeline).length,
      0,
      "unrelated fixture stories are not arbitrarily linked",
    );
    assert.equal(new Set(cards.map((c) => c.storyId)).size, cards.length);
    assert.ok(
      news.every((c) => c.hfs && c.hfs.ranked.length === 3),
      "every news card carries ranked H/F/S",
    );
    assert.ok(cards.every((c) => c.image?.status === "ready"));
    assert.ok(
      !cards.some((c) => /sourdough|Insiders/i.test(c.title)),
      "off-topic and hype items stay out",
    );

    const tools = app.store.telemetry.toolCallsForSweep(sweep.id);
    const presents = tools.filter((t) => t.toolName === "present_news");
    assert.equal(presents.length, 5);
    assert.equal(presents[0].isError, true);
    assert.match(
      presents[0].resultText!,
      /"component" must be one of: headline, brief, signal_alert/,
    );
    assert.ok(
      tools
        .filter((t) => !t.isError)
        .every((t) => typeof t.durationMs === "number" && t.startedAt && t.endedAt),
      "1.1.0 timings on every executed call",
    );

    const runs = app.store.telemetry.runs({ sweepId: sweep.id });
    assert.equal(
      runs.filter((r) => r.agent === "news-researcher").length,
      2,
      "two research batches ran as subagents",
    );
    assert.ok(runs.every((r) => r.status === "done"));
    const detail = app.store.telemetry.run(runs.find((r) => r.agent === "news-desk")!.runEntryId)!;
    assert.equal(detail.children.length, 2);
    assert.ok(
      detail.generationRows.every((g) => g.durationMs !== undefined && g.contextTokens > 0),
    );

    const jev = app.store.db
      .prepare("SELECT command, count(*) n FROM jev_calls WHERE sweep_id = ? GROUP BY command")
      .all(sweep.id) as any[];
    assert.ok(jev.find((r) => r.command === "hfs").n >= 4);
    assert.ok(
      (
        app.store.db
          .prepare("SELECT count(*) n FROM events WHERE event = 'tool.start'")
          .get() as any
      ).n > 10,
    );
  } finally {
    await cleanup();
  }
});

test("a run's card limit: jev ranks the candidates by importance and the sweep keeps its top N", async () => {
  const { app, cleanup } = await fauxApp({ DNA_FIXTURE_SET: "news" });
  try {
    const started = await startNewsSweep(app, app.main, app.ctx, {
      trigger: "test",
      requestId: "t:cards",
      cards: 2,
    });
    const sweep = await waitForSweep(app, started.sweep!.id);
    assert.equal(sweep.maxCards, 2);
    assert.ok(sweep.candidates <= 2, `candidates ${sweep.candidates}`);
    const items = app.store.news.itemsForSweep(sweep.id);
    assert.ok(items.some((i) => i.lastError === "ranked below the top 2 for this sweep"));
    assert.ok(
      items.filter((i) => i.importance !== undefined).length >= sweep.candidates,
      "every ranked item keeps jev's importance",
    );
    assert.equal(app.schedule.cards(), 7, "the reader's setting is 7 cards by default");
  } finally {
    await cleanup();
  }
});

test("no news is fine: an empty sweep closes as no_news with no cards and a clean audit", async () => {
  const { app, cleanup } = await fauxApp({ DNA_FIXTURE_SET: "empty" });
  try {
    const started = await startNewsSweep(app, app.main, app.ctx, {
      trigger: "test",
      requestId: "t:empty",
    });
    const sweep = await waitForSweep(app, started.sweep!.id);
    assert.equal(sweep.status, "no_news");
    assert.equal(sweep.candidates, 0);
    assert.equal(app.store.news.cards().length, 0);
    assert.deepEqual(sweep.audit?.missing, []);
    assert.match(
      sweep.phases.findLast((p) => p.phase === "gather")?.note ?? "",
      /second bag of \d+ searches/,
      "an empty first bag searches a second, fresh bag before giving up",
    );
  } finally {
    await cleanup();
  }
});

test("the same request id replays the sweep, and a second sweep while one runs is skipped", async () => {
  const { app, cleanup } = await fauxApp({
    DNA_FIXTURE_SET: "news",
    DNA_FIXTURE_JEV_DELAY_MS: "40",
  });
  try {
    const first = await startNewsSweep(app, app.main, app.ctx, {
      trigger: "cron",
      requestId: "cron:local:20261012T1600",
    });
    const replay = await startNewsSweep(app, app.main, app.ctx, {
      trigger: "cron",
      requestId: "cron:local:20261012T1600",
    });
    assert.equal(replay.status, "replay");
    assert.equal(replay.sweep!.id, first.sweep!.id);
    const second = await startNewsSweep(app, app.main, app.ctx, {
      trigger: "cron",
      requestId: "cron:local:20261012T1615",
    });
    assert.equal(second.status, "skipped");
    assert.match(second.sweep!.reason!, /still running/);
    await waitForSweep(app, first.sweep!.id);
  } finally {
    await cleanup();
  }
});

test("dedupe compares retrieved stories with richer evidence and marks repeated coverage", async () => {
  const { app, cleanup } = await fauxApp({ DNA_FIXTURE_SET: "news" });
  try {
    const { item: prior } = app.store.news.upsertItem({
      url: "https://prior.example.dev/pi-durable-1-1",
      title: "pi-durable 1.1.0 adds task timings",
    });
    app.store.news.updateItem(prior.id, { status: "presented" });
    const started = await startNewsSweep(app, app.main, app.ctx, {
      trigger: "test",
      requestId: "t:dedupe",
    });
    const sweep = await waitForSweep(app, started.sweep!.id);
    assert.ok(sweep.duplicates >= 1, `duplicates ${sweep.duplicates}`);
    const dupes = app.store.news.itemsForSweep(sweep.id, ["duplicate"]);
    assert.ok(dupes.some((d) => d.duplicateOf === prior.id));
    const sameCalls = app.store.db
      .prepare("SELECT count(*) n FROM jev_calls WHERE sweep_id = ? AND command = 'same-story'")
      .get(sweep.id) as { n: number };
    assert.ok(sameCalls.n >= 1);
  } finally {
    await cleanup();
  }
});
