import assert from "node:assert/strict";
import { test } from "node:test";
import { FeedModel } from "@dna/sdk";
import { comparePublished, packageRelease } from "../src/news/releases.ts";
import { tempStore } from "./helpers.ts";

test("release identity distinguishes repositories and monorepo packages, not release channels", () => {
  const url = (repo: string, tag: string) =>
    `https://github.com/${repo}/releases/tag/${encodeURIComponent(tag)}`;
  const key = (repo: string, tag: string) => packageRelease(url(repo, tag))?.key;
  assert.equal(
    key("google-gemini/gemini-cli", "v0.65.0-preview.0"),
    key("google-gemini/gemini-cli", "v0.64.0"),
  );
  assert.equal(
    key("owner/repo", "v0.65.0-nightly.20261013.g123"),
    key("owner/repo", "v0.65.0-preview.0"),
  );
  assert.notEqual(key("owner/repo", "v1.0.0"), key("fork/repo", "v1.0.0"));
  assert.equal(key("owner/repo", "@scope/core@1.0.0"), key("owner/repo", "@scope/core@2.0.0"));
  assert.notEqual(key("owner/repo", "core@1.0.0"), key("owner/repo", "cli@2.0.0"));
  assert.equal(packageRelease("https://example.org/news/gemini-v1.0.0"), undefined);
  assert.equal(packageRelease(url("owner/repo", "nightly")), undefined);
});

test("publication time wins over arrival order, and an unknown date cannot displace a known date", () => {
  assert.ok(
    comparePublished(
      { id: 1, publishedAt: "2026-10-13T21:00:00Z" },
      { id: 99, publishedAt: "2026-10-13T20:00:00Z" },
    ) > 0,
  );
  assert.ok(comparePublished({ id: 99 }, { id: 1, publishedAt: "2026-10-13T20:00:00Z" }) < 0);
  assert.ok(
    comparePublished(
      { id: 99, publishedAt: "invalid" },
      { id: 1, publishedAt: "2026-10-13T20:00:00Z" },
    ) < 0,
  );
});

test("latest published release filters the feed and search before pagination, retains history, and updates SSE", () => {
  const { store, cleanup } = tempStore();
  try {
    const add = (tag: string, publishedAt?: string, repo = "google-gemini/gemini-cli") =>
      store.news.upsertItem({
        url: `https://github.com/${repo}/releases/tag/${tag}`,
        title: `Gemini CLI ${tag}`,
        publishedAt,
      }).item;
    const card = (id: number) =>
      store.news.addCard({
        kind: "news",
        component: "release",
        props: { title: store.news.item(id)!.title },
        itemId: id,
        toolCallId: `release:${id}`,
      }).card;
    const preview = add("v0.65.0-preview.0", "2026-10-13T20:27:55Z");
    const first = card(preview.id);
    const stable = add("v0.64.0", "2026-10-13T20:44:46Z");
    store.news.refreshReleases();
    assert.equal(
      store.news.latestRelease(preview.id),
      stable.id,
      "a later lower version is still the latest publication",
    );
    assert.deepEqual(
      store.news.cards().map((c) => c.id),
      [first.id],
      "keep the current card until its replacement is presented",
    );
    const second = card(stable.id);
    const nightly = add("v9.0.0-nightly.20261008", "2026-10-08T01:35:49Z");
    const old = card(nightly.id);
    const unknown = add("v99.0.0");
    card(unknown.id);
    assert.deepEqual(
      store.news.cards({ limit: 1 }).map((c) => c.id),
      [second.id],
    );
    assert.deepEqual(
      store.news.searchCards("search", "Gemini CLI").map((c) => c.id),
      [second.id],
    );
    assert.deepEqual(
      store.news.searchCards("url", "github.com/google-gemini/gemini-cli").map((c) => c.id),
      [second.id],
    );
    assert.equal(store.news.card(old.id)!.hiddenFromFeed, true, "old cards remain available by id");
    assert.equal(store.news.searchCards("search", "v9.0.0-nightly").length, 0);
    const model = new FeedModel();
    model.load({ cards: [first] });
    model.apply({ type: "feed.card_updated", card: store.news.card(first.id)! });
    model.apply({ type: "feed.card", card: second });
    assert.deepEqual(
      model.state.news.map((c) => c.id),
      [second.id],
    );
    const separate = card(add("v1.0.0", "2026-10-12T01:00:00Z", "other/cli").id);
    assert.deepEqual(
      new Set(store.news.cards().map((c) => c.id)),
      new Set([second.id, separate.id]),
    );
    store.db.exec(
      "UPDATE items SET release_key=NULL, release_version=NULL; DELETE FROM release_heads;",
    );
    store.news.refreshReleases(true);
    assert.deepEqual(
      new Set(store.news.cards().map((c) => c.id)),
      new Set([second.id, separate.id]),
      "backfill cleans existing cards too",
    );
  } finally {
    cleanup();
  }
});

test("old release candidates are rejected before classification and a latest release misidentified as a duplicate is retried", () => {
  const { store, cleanup } = tempStore();
  try {
    const sweep = store.sweeps.create({
      requestId: "release-test",
      trigger: "test",
      status: "queued",
    });
    const add = (tag: string, ago: number) =>
      store.news.upsertItem({
        sweepId: sweep.id,
        url: `https://github.com/test/cli/releases/tag/${tag}`,
        title: `CLI ${tag}`,
        publishedAt: new Date(Date.now() - ago).toISOString(),
      }).item;
    const old = add("v3.0.0-preview.0", 100_000),
      latest = add("v2.0.0", 10_000);
    store.news.updateItem(latest.id, {
      status: "duplicate",
      duplicateOf: old.id,
      relevance: 0.9,
      worth: 0.9,
    });
    store.news.filterReleases(sweep.id);
    assert.equal(store.news.item(old.id)!.status, "rejected");
    assert.match(store.news.item(old.id)!.lastError!, /Superseded by release/);
    assert.equal(store.news.item(latest.id)!.status, "candidate");
    assert.equal(store.news.item(latest.id)!.duplicateOf, undefined);
    assert.equal(store.news.item(latest.id)!.relevance, undefined);
    store.news.updateItem(latest.id, { status: "rejected", lastError: undefined });
    store.news.filterReleases(sweep.id);
    assert.equal(store.news.item(latest.id)!.status, "rejected", "do not undo the relevance gate");
  } finally {
    cleanup();
  }
});
