import assert from "node:assert/strict";
import { test } from "node:test";
import type { Http, HttpResponse } from "../src/news/http.ts";
import { startNewsSweep } from "../src/news/sweep.ts";
import { applyFeedback } from "../src/news/taste.ts";
import { discoverSource, isAggregator, siteKey } from "../src/news/sources/discover.ts";
import { fauxApp, waitForSweep } from "./helpers.ts";

const ATOM = `<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom"><title>Dev Blog</title>
<entry><title>Durable agents ship</title><link href="https://blog.dev/posts/1"/><updated>2026-10-12T00:00:00Z</updated></entry></feed>`;
const RSS = `<?xml version="1.0"?><rss version="2.0"><channel><title>Notes</title>
<item><title>Agent sandboxes</title><link>https://notes.dev/a</link></item></channel></rss>`;

function fakeHttp(pages: Record<string, string>): Http {
  return {
    get: async (url) => {
      const text = pages[url];
      if (text === undefined) throw new Error(`GET ${url} HTTP 404`);
      return { status: 200, url, headers: new Headers(), text } as HttpResponse;
    },
    postJson: async () => {
      throw new Error("not used");
    },
  };
}

test("discovery finds a direct feed, a linked feed, a common feed path, GitHub releases and a listing page", async () => {
  const http = fakeHttp({
    "https://notes.dev/rss": RSS,
    "https://blog.dev/posts/1": `<html><head><title>Post</title><link rel="alternate" type="application/atom+xml" href="/atom.xml"></head></html>`,
    "https://blog.dev/atom.xml": ATOM,
    "https://plain.dev/post": "<html><head><title>Plain</title></head><body>post</body></html>",
    "https://plain.dev/feed": RSS,
    "https://github.com/acme/agent/releases.atom": ATOM,
    "https://list.dev/news": `<html><head><title>List News</title></head><body>${[1, 2, 3, 4]
      .map((n) => `<a href="/news/story-number-${n}">A long enough story title ${n}</a>`)
      .join("")}</body></html>`,
    "https://empty.dev/x": "<html><body>nothing</body></html>",
  });
  assert.deepEqual(await discoverSource(http, "https://notes.dev/rss"), {
    kind: "rss",
    url: "https://notes.dev/rss",
    name: "Notes",
    entries: 1,
  });
  const linked = await discoverSource(http, "https://blog.dev/posts/1");
  assert.equal(linked.kind, "atom");
  assert.equal(linked.url, "https://blog.dev/atom.xml");
  assert.equal(linked.name, "Dev Blog");
  assert.equal(
    (await discoverSource(http, "https://plain.dev/post")).url,
    "https://plain.dev/feed",
  );
  const gh = await discoverSource(http, "https://github.com/acme/agent/issues/9");
  assert.equal(gh.kind, "github_releases");
  assert.equal(gh.url, "https://github.com/acme/agent/releases.atom");
  const list = await discoverSource(http, "https://list.dev/news");
  assert.equal(list.kind, "web_page");
  assert.equal(list.entries, 4);
  await assert.rejects(
    discoverSource(http, "https://empty.dev/x"),
    /No feed and no article listing/,
  );
});

test("site keys and aggregators", () => {
  assert.equal(siteKey("https://www.Example.com/a/b"), "example.com");
  assert.equal(siteKey("https://github.com/Acme/Agent/pull/3"), "github.com/acme/agent");
  assert.ok(isAggregator("https://news.ycombinator.com/item?id=1"));
  assert.ok(!isAggregator("https://simonwillison.net/2026/x"));
});

test("an upvote leaves a lead, the next sweep's agent saves it as a source, and the audit checks it", async () => {
  const { app, cleanup } = await fauxApp({ DNA_FIXTURE_SET: "empty" });
  try {
    const { store } = app;
    const card = (url: string, n: number) => {
      const item = store.news.upsertItem({ url, title: `Post ${n}`, sourceName: "test" }).item;
      return store.news.addCard({
        kind: "news",
        component: "brief",
        props: { title: `Post ${n}`, summary: "s" },
        itemId: item.id,
        toolCallId: `links:${n}`,
      }).card;
    };
    const a = card("https://durable.example.dev/posts/1", 1);
    const first = applyFeedback(store, a, { signal: "more" }).leads;
    assert.deepEqual(
      first.map((l) => [l.site, l.status]),
      [["durable.example.dev", "open"]],
    );
    const again = applyFeedback(store, card("https://durable.example.dev/posts/2", 2), {
      labels: ["signal"],
    }).leads;
    assert.equal(again[0].id, first[0].id, "one lead per site");
    assert.deepEqual(applyFeedback(store, a, { signal: "less" }).leads, []);
    const watched = card("https://simonwillison.net/2026/Oct/1/agents/", 3);
    assert.deepEqual(
      applyFeedback(store, watched, { signal: "more" }).leads,
      [],
      "already a source",
    );
    assert.deepEqual(
      applyFeedback(store, card("https://news.ycombinator.com/item?id=9", 4), { signal: "more" })
        .leads,
      [],
      "aggregators are searched already",
    );

    const started = await startNewsSweep(app, app.main, app.ctx, {
      trigger: "test",
      requestId: "t:links",
    });
    const sweep = await waitForSweep(app, started.sweep!.id);
    assert.equal(sweep.status, "no_news");
    assert.ok(sweep.audit?.expected.includes("every source lead saved or skipped"));
    assert.deepEqual(sweep.audit?.missing, []);
    const lead = store.sources.lead(first[0].id)!;
    assert.equal(lead.status, "saved");
    const source = store.sources.get(lead.sourceId!)!;
    assert.deepEqual(
      [source.kind, source.url, source.origin, source.name],
      ["atom", "https://durable.example.dev/blog/feed.xml", "upvote", "Fixture Weblog"],
    );
    assert.match(source.reason ?? "", /upvoted/);
    assert.deepEqual(store.sources.openLeads(), []);
  } finally {
    await cleanup();
  }
});
