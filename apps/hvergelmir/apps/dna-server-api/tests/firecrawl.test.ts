import assert from "node:assert/strict";
import { test } from "node:test";
import { fixtureHttp } from "../src/news/fixtures.ts";
import type { Http } from "../src/news/http.ts";
import { resolveMode, SearchService } from "../src/news/search/index.ts";
import { tempStore } from "./helpers.ts";

function recording(base: Http) {
  const posts: { url: string; body: any }[] = [];
  const gets: string[] = [];
  const http: Http = {
    get: (url, o) => (gets.push(url), base.get(url, o)),
    postJson: (url, body, headers, o) => (
      posts.push({ url, body }),
      base.postJson(url, body, headers, o)
    ),
  };
  return { http, posts, gets };
}

test("mode resolution: Firecrawl only when asked and keyed; anything unknown searches the web", () => {
  assert.equal(resolveMode("firecrawl", "fc-key"), "firecrawl");
  assert.equal(resolveMode("auto", undefined), "web");
  assert.equal(resolveMode("auto", "fc-key"), "web", "Firecrawl is opt in");
  assert.equal(resolveMode("fallback", undefined), "web");
  assert.equal(resolveMode("firecrawl", undefined), "web");
  assert.equal(resolveMode("fixture", undefined), "fixture");
  assert.equal(resolveMode("brave", "fc-key"), "web");
  assert.equal(resolveMode("Web", undefined), "web");
});

test("search sends the v2 body, logs credits, and scrape caches the article", async () => {
  const { store, cleanup } = tempStore();
  try {
    const rec = recording(fixtureHttp("news"));
    const search = new SearchService(
      { http: rec.http, store },
      { mode: "fixture", sweepCap: 5, dailyCap: 40 },
    );
    const result = await search.search(
      "agent sandboxes",
      { sweepId: undefined, callId: "c1" },
      { hours: 24 },
    );
    assert.equal(result.via, "firecrawl");
    assert.equal(result.credits, 2);
    assert.deepEqual(rec.posts[0].body, {
      query: "agent sandboxes",
      limit: 10,
      sources: [{ type: "web" }, { type: "news" }],
      tbs: "qdr:d",
      ignoreInvalidURLs: true,
    });
    assert.equal(result.hits[0].url, "https://exe.dev/blog/persistent-sandboxes");
    const scraped = await search.scrape("https://exe.dev/blog/persistent-sandboxes", {
      callId: "c2",
    });
    assert.equal(scraped.via, "firecrawl");
    assert.match(scraped.doc.contentMd!, /migration guide/);
    const again = await search.scrape("https://exe.dev/blog/persistent-sandboxes", {
      callId: "c3",
    });
    assert.equal(again.via, "cache", "a fresh scraped body is never fetched twice");
    const rows = store.db
      .prepare("SELECT endpoint, credits_used, call_id FROM firecrawl_calls ORDER BY id")
      .all() as any[];
    assert.deepEqual(
      rows.map((r) => [r.endpoint, r.credits_used, r.call_id]),
      [
        ["search", 2, "c1"],
        ["scrape", 1, "c2"],
      ],
    );
  } finally {
    cleanup();
  }
});

test("the sweep cap switches to web search and logs it", async () => {
  const { store, cleanup } = tempStore();
  try {
    const sweep = store.sweeps.create({ requestId: "t1", trigger: "test", status: "running" });
    const rec = recording(fixtureHttp("news"));
    const search = new SearchService(
      { http: rec.http, store },
      { mode: "fixture", sweepCap: 5, dailyCap: 40 },
    );
    const first = await search.search("durable agents", { sweepId: sweep.id });
    const second = await search.search("coding agents", { sweepId: sweep.id });
    assert.equal(first.via, "firecrawl");
    assert.equal(second.via, "web", "2 used, 3 left, a search reserves 4");
    assert.equal(rec.posts.length, 1);
    assert.ok(rec.gets.some((u) => u.includes("hn.algolia.com")));
    assert.equal(search.budget(sweep.id).sweepUsed, 2);
  } finally {
    cleanup();
  }
});

test("web mode searches Bing News, HN and the cache, and scrapes over http", async () => {
  const { store, cleanup } = tempStore();
  try {
    const rec = recording(fixtureHttp("news"));
    const search = new SearchService(
      { http: rec.http, store },
      { mode: "auto", sweepCap: 5, dailyCap: 40 },
    );
    assert.equal(search.mode, "web");
    store.sources.cache({
      url: "https://blog.fixture.dev/sandbox-notes",
      title: "Agent sandboxes notes",
      excerpt: "sandboxes for agents",
      fetchVia: "feed",
      ttlMinutes: 60,
    });
    const result = await search.search("agent sandboxes");
    assert.equal(result.via, "web");
    assert.ok(result.hits.some((h) => h.url === "https://blog.fixture.dev/sandbox-notes"));
    assert.ok(
      result.hits.some(
        (h) =>
          h.url === "https://example.com/durable-agents-runtime" && h.sourceName === "example.com",
      ),
      "Bing links unwrap to the article URL",
    );
    assert.ok(
      rec.gets.some(
        (u) =>
          u.startsWith("https://www.bing.com/news/search") && u.includes("q=agent%20sandboxes&"),
      ),
      "multiword queries search as words, not a quoted phrase",
    );
    assert.ok(!rec.gets.some((u) => u.includes("news.google.com")), "Bing answered: no Google");
    assert.match(result.engines!, /bing-news \d+, hn \d+, cache \d+/);
    const scraped = await search.scrape("https://blog.fixture.dev/sandbox-notes");
    assert.equal(scraped.via, "http");
    assert.match(scraped.doc.contentMd!, /migration guide/);
    assert.equal(rec.posts.length, 0);
    assert.equal(store.db.prepare("SELECT count(*) n FROM firecrawl_calls").get()!.n, 0);
  } finally {
    cleanup();
  }
});

test("parallel scrapes reserve credits, so they cannot overrun the sweep cap together", async () => {
  const { store, cleanup } = tempStore();
  try {
    const sweep = store.sweeps.create({ requestId: "t2", trigger: "test", status: "running" });
    const rec = recording(fixtureHttp("news"));
    const search = new SearchService(
      { http: rec.http, store },
      { mode: "fixture", sweepCap: 3, dailyCap: 40 },
    );
    const urls = Array.from({ length: 7 }, (_, i) => `https://example.com/parallel-${i}`);
    const results = await Promise.all(
      urls.map((u) => search.scrape(u, { sweepId: sweep.id }).catch(() => undefined)),
    );
    assert.equal(results.filter((r) => r?.via === "firecrawl").length, 3);
    assert.equal(search.budget(sweep.id).sweepUsed, 3);
  } finally {
    cleanup();
  }
});

test("web search keeps a window only when asked: a day, a week, a month, or any date", async () => {
  const { bingNews } = await import("../src/news/search/web.ts");
  const urls: string[] = [];
  const http = {
    get: async (url: string) => {
      urls.push(url);
      return {
        status: 200,
        url,
        headers: new Headers(),
        text: '<?xml version="1.0"?><rss version="2.0"><channel><title>x</title></channel></rss>',
      };
    },
    postJson: async () => {
      throw new Error("unused");
    },
  };
  for (const hours of [24, 168, 336, undefined]) await bingNews(http, "agents", hours, 5);
  assert.deepEqual(
    urls.map((u) => decodeURIComponent(new URL(u).searchParams.get("qft") ?? "none")),
    ['interval="7"', 'interval="8"', 'interval="9"', "none"],
  );
});

test("hyper_fetch reads directly without a key, and through Firecrawl in web mode outside the caps with one", async () => {
  const { store, cleanup } = tempStore();
  try {
    const offRec = recording(fixtureHttp("news"));
    const off = new SearchService(
      { http: offRec.http, store },
      { mode: "auto", sweepCap: 5, dailyCap: 40 },
    );
    assert.equal(off.hyperFetchVia, "http");
    const direct = await off.hyperFetch("https://example.com/no-key-article");
    assert.equal(direct.via, "http");
    assert.equal(direct.credits, 0);
    assert.match(direct.markdown, /migration guide/);
    assert.equal(offRec.posts.length, 0, "no Firecrawl call without a key");
    const rec = recording(fixtureHttp("news"));
    const search = new SearchService(
      { http: rec.http, store },
      { mode: "auto", firecrawlKey: "fc-key", sweepCap: 0, dailyCap: 0 },
    );
    assert.equal(search.mode, "web", "the key alone does not switch search to Firecrawl");
    assert.equal(search.hyperFetchVia, "firecrawl");
    const page = await search.hyperFetch("https://exe.dev/blog/persistent-sandboxes", {
      callId: "h1",
    });
    assert.match(page.markdown, /migration guide/, "spent with both caps at 0: the reader asked");
    assert.equal(page.via, "firecrawl");
    assert.equal(page.credits, 1);
    assert.ok(rec.posts[0].url.endsWith("/v2/scrape"));
    const rows = store.db
      .prepare("SELECT endpoint, credits_used, call_id FROM firecrawl_calls ORDER BY id")
      .all() as any[];
    assert.deepEqual(
      rows.map((r) => [r.endpoint, r.credits_used, r.call_id]),
      [["scrape", 1, "h1"]],
    );
  } finally {
    cleanup();
  }
});
