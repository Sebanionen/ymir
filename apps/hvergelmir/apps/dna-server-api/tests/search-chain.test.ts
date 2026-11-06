import assert from "node:assert/strict";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { test } from "node:test";
import { HttpError } from "@dna/sdk";
import { fixtureHttp } from "../src/news/fixtures.ts";
import { liveHttp, type Http } from "../src/news/http.ts";
import { modeWarning, SearchService } from "../src/news/search/index.ts";
import { fetchSource } from "../src/news/sources/index.ts";
import { tempStore } from "./helpers.ts";

const EMPTY_RSS =
  '<?xml version="1.0"?><rss version="2.0"><channel><title>x</title></channel></rss>';
const CAPTCHA = "<!DOCTYPE html><html><body>Verify you are a human</body></html>";

/** Fixture HTTP with some hosts answered by `override`, and every request recorded. */
function stubbed(override: (url: URL) => string | Error | undefined) {
  const base = fixtureHttp("news");
  const gets: string[] = [];
  const posts: string[] = [];
  const http: Http = {
    get: async (url, o) => {
      gets.push(url);
      const answer = override(new URL(url));
      if (answer instanceof Error) throw answer;
      if (answer !== undefined) return { status: 200, url, headers: new Headers(), text: answer };
      return base.get(url, o);
    },
    postJson: (url, body, headers, o) => (posts.push(url), base.postJson(url, body, headers, o)),
  };
  return { http, gets, posts };
}

const isBingNews = (u: URL) => u.host === "www.bing.com" && u.pathname.startsWith("/news");

test("a Bing captcha page: Google News answers, Bing rests, and the next search skips it", async () => {
  const { store, cleanup } = tempStore();
  try {
    const rec = stubbed((u) => (isBingNews(u) ? CAPTCHA : undefined));
    const search = new SearchService(
      { http: rec.http, store },
      { mode: "web", sweepCap: 5, dailyCap: 40 },
    );
    const first = await search.search("agents", {}, { hours: 168 });
    const wrapped = first.hits.find((h) => h.url === "https://example.org/google-wrapped-agents");
    assert.ok(wrapped, "the Google News link unwraps to the article");
    assert.equal(wrapped.title, "Agents get a wrapped link in Google News", "publisher suffix off");
    assert.equal(wrapped.sourceName, "Example Org");
    assert.ok(
      first.hits.some((h) => h.url.startsWith("https://news.google.com/rss/articles/AU_yqL")),
      "an opaque Google link stays as it is",
    );
    assert.match(first.engines!, /google-news 2/);
    assert.match(first.engines!, /failed bing-news \(bing-news returned HTML/);
    const bing = search.engineHealth().find((e) => e.name === "bing-news")!;
    assert.equal(bing.failed, 1);
    assert.ok(Date.parse(bing.coolingUntil!) > Date.now());
    const before = rec.gets.filter((g) => isBingNews(new URL(g))).length;
    const second = await search.search("agents", {}, { hours: 168 });
    assert.equal(rec.gets.filter((g) => isBingNews(new URL(g))).length, before, "Bing rests");
    assert.match(second.engines!, /resting bing-news/);
    assert.ok(second.hits.length > 0);
  } finally {
    cleanup();
  }
});

test("the news chain: an empty Bing answer moves on to Google News with a when: window", async () => {
  const { store, cleanup } = tempStore();
  try {
    const rec = stubbed((u) => (isBingNews(u) ? EMPTY_RSS : undefined));
    const search = new SearchService(
      { http: rec.http, store },
      { mode: "auto", sweepCap: 5, dailyCap: 40 },
    );
    const result = await search.search("coding agents", {}, { hours: 168 });
    const google = rec.gets.find((g) => g.startsWith("https://news.google.com/rss/search"));
    assert.ok(google, "Google News is asked after an empty Bing answer");
    assert.equal(new URL(google).searchParams.get("q"), "coding agents when:7d");
    assert.match(result.engines!, /^bing-news 0, /, "Bing answered first, with nothing");
    assert.match(result.engines!, /google-news 2/);
    assert.equal(search.engineHealth().find((e) => e.name === "bing-news")!.failed, 0);
  } finally {
    cleanup();
  }
});

test("an unknown or keyless search mode warns, searches the web and never calls Firecrawl", async () => {
  assert.match(modeWarning("brave")!, /not one of auto, web, fallback, firecrawl, fixture/);
  assert.match(modeWarning("firecrawl")!, /needs FIRECRAWL_API_KEY/);
  assert.equal(modeWarning("firecrawl", "fc-key"), undefined);
  assert.equal(modeWarning("auto"), undefined);
  const { store, cleanup } = tempStore();
  try {
    for (const mode of ["brave", "firecrawl"]) {
      const warnings: unknown[] = [];
      const log = {
        debug() {},
        info() {},
        error() {},
        warn: (...a: unknown[]) => warnings.push(a),
      };
      const rec = stubbed(() => undefined);
      const search = new SearchService(
        { http: rec.http, store, log: log as never },
        { mode, sweepCap: 5, dailyCap: 40 },
      );
      assert.equal(search.mode, "web");
      assert.equal(warnings.length, 1);
      const result = await search.search("agents");
      assert.equal(result.via, "web");
      assert.equal(rec.posts.length, 0, `${mode}: no Firecrawl client`);
      assert.ok(!search.engineHealth().some((e) => e.name === "firecrawl"));
    }
  } finally {
    cleanup();
  }
});

test("deep search without a key: Bing web, then DuckDuckGo when Bing web is rate limited; pages read directly", async () => {
  const { store, cleanup } = tempStore();
  try {
    const rec = stubbed((u) =>
      u.host === "www.bing.com" && u.pathname === "/search"
        ? new HttpError(429, "GET www.bing.com HTTP 429")
        : undefined,
    );
    const search = new SearchService(
      { http: rec.http, store },
      { mode: "auto", sweepCap: 5, dailyCap: 40 },
    );
    const result = await search.deepSearch("durable execution agents", {}, { limit: 10 });
    assert.equal(result.via, "web");
    assert.match(result.engines!, /failed bing-web \(GET www\.bing\.com HTTP 429\)/);
    assert.match(result.engines!, /duckduckgo 2/);
    const ddg = result.hits.find((h) => h.url === "https://example.com/durable-execution-guide");
    assert.ok(ddg, "DuckDuckGo links unwrap to the article");
    assert.equal(ddg.title, "Durable execution for agents: a guide");
    assert.match(ddg.excerpt!, /crashed agent resumes/);
    assert.ok(!result.hits.some((h) => h.url.includes("ads.example")), "ads are skipped");
    assert.ok(result.hits.some((h) => h.url === "https://example.com/durable-agents-runtime"));
    const page = await search.deepScrape("https://example.com/durable-execution-guide");
    assert.equal(page.via, "http");
    assert.match(page.markdown, /migration guide/);
    assert.equal(rec.posts.length, 0);
  } finally {
    cleanup();
  }
});

test("a 403 or 429 source is skipped this sweep: no retry, no failure count, never disabled", async () => {
  const hits = { blocked: 0, limited: 0 };
  const server = createServer((req, res) => {
    const blocked = req.url === "/r/blocked/.rss";
    hits[blocked ? "blocked" : "limited"]++;
    res.writeHead(blocked ? 403 : 429, { "content-type": "text/html" }).end("<html>no</html>");
  });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  const { store, cleanup } = tempStore();
  try {
    const blocked = store.sources.add({
      kind: "rss",
      name: "blocked",
      url: `${base}/r/blocked/.rss`,
    });
    const limited = store.sources.add({ kind: "rss", name: "limited", url: `${base}/limited.rss` });
    const http = liveHttp();
    for (let i = 0; i < 3; i++) {
      const a = await fetchSource(blocked, { http, store, since: new Date(0) });
      const b = await fetchSource(limited, { http, store, since: new Date(0) });
      assert.equal(a.status, "403 blocked");
      assert.equal(b.status, "429 rate limited");
      assert.equal(a.disabled || b.disabled, false);
    }
    assert.deepEqual(hits, { blocked: 3, limited: 3 }, "one request per sweep, no retries");
    for (const s of [blocked, limited]) {
      const row = store.db
        .prepare("SELECT enabled, fail_count FROM sources WHERE id = ?")
        .get(s.id);
      assert.deepEqual({ ...row }, { enabled: 1, fail_count: 0 });
    }
  } finally {
    cleanup();
    server.close();
  }
});

test("sweeps fetch due sources: a new source at once, a just fetched one after its interval", () => {
  const { store, cleanup } = tempStore();
  try {
    const source = store.sources.add({
      kind: "rss",
      name: "due test",
      url: "https://due.example/feed.xml",
      intervalMin: 30,
    });
    assert.ok(
      store.sources.due().some((s) => s.id === source.id),
      "never fetched: due now",
    );
    store.sources.fetched(source.id, { ok: true, status: "200" });
    assert.ok(!store.sources.due().some((s) => s.id === source.id), "just fetched: not due");
    const later = new Date(Date.now() + 30 * 60_000);
    assert.ok(
      store.sources.due(later).some((s) => s.id === source.id),
      "due after 30 minutes",
    );
  } finally {
    cleanup();
  }
});
