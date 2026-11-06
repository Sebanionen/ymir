import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { Dates, parseDateAnswer } from "../src/news/dates.ts";
import { dateInHtml, dateInUrl } from "../src/news/extract.ts";
import type { Http } from "../src/news/http.ts";
import type { App } from "../src/runtime.ts";
import { fauxApp } from "./helpers.ts";

const NOW = Date.parse("2026-10-12T12:00:00Z");
const page = (head: string, body = "<p>Hello</p>") =>
  `<html><head>${head}</head><body><article>${body}</article></body></html>`;

test("a page's own markup dates it: meta, JSON-LD, <time>, then the url", () => {
  const url = "https://example.com/posts/a";
  assert.deepEqual(
    dateInHtml(
      page('<meta property="article:published_time" content="2026-10-09T08:00:00Z">'),
      url,
      NOW,
    ),
    { at: "2026-10-09T08:00:00.000Z", source: "meta" },
  );
  assert.deepEqual(
    dateInHtml(
      page(
        '<script type="application/ld+json">{"@context":"https://schema.org","@graph":[{"@type":"WebPage"},{"@type":"BlogPosting","datePublished":"2026-09-30"}]}</script>',
      ),
      url,
      NOW,
    ),
    { at: "2026-09-30T00:00:00.000Z", source: "jsonld" },
  );
  assert.deepEqual(
    dateInHtml(page("", '<time datetime="2026-10-01T10:00:00Z">Oct 1</time>'), url, NOW),
    { at: "2026-10-01T10:00:00.000Z", source: "time" },
  );
  assert.deepEqual(dateInHtml(page(""), "https://example.com/2026/10/05/launch", NOW), {
    at: "2026-10-05T00:00:00.000Z",
    source: "url",
  });
  assert.equal(
    dateInHtml(page('<meta name="date" content="2031-01-01">'), url, NOW),
    undefined,
    "a date far in the future is not a publish date",
  );
  assert.equal(dateInUrl("https://example.com/items/20261005", NOW), undefined);
});

test("the quick model's answer counts only as a plausible JSON date", () => {
  assert.equal(parseDateAnswer('{"published": "2026-10-09"}', NOW), "2026-10-09T00:00:00.000Z");
  assert.equal(
    parseDateAnswer('Sure: {"published": "2026-10-09"}', NOW),
    "2026-10-09T00:00:00.000Z",
  );
  assert.equal(parseDateAnswer('{"published": null}', NOW), undefined);
  assert.equal(parseDateAnswer('{"published": "last week"}', NOW), undefined);
  assert.equal(parseDateAnswer("no idea", NOW), undefined);
});

let app: App;
let cleanup: () => Promise<void>;
before(async () => {
  ({ app, cleanup } = await fauxApp({ DNA_FIXTURE_SET: "news" }));
});
after(() => cleanup());

const htmlHttp = (html: string): Http => ({
  get: async (url) => ({ status: 200, url, headers: new Headers(), text: html }),
  postJson: async () => {
    throw new Error("unused");
  },
});

test("no markup date: the quick model reads it off the page, once, and dates news cards", async () => {
  const body = `<h1>How we contain agents</h1><p>Published Oct 9, 2026</p><p>${"We run every agent in a sandbox with no network. ".repeat(8)}</p>`;
  const dates = new Dates({
    http: htmlHttp(page("", body)),
    store: app.store,
    log: app.log,
    quick: app.quick,
  });
  const item = app.store.news.upsertItem({
    url: "https://anthropic.example.dev/engineering/contain",
    title: "How we contain agents",
    sourceName: "Anthropic Engineering",
  }).item;
  app.store.news.addCard({
    kind: "news",
    component: "brief",
    props: { title: "How we contain agents", summary: "s" },
    itemId: item.id,
    toolCallId: "dates:1",
  });
  assert.deepEqual(await dates.resolve(item), {
    at: "2026-10-09T00:00:00.000Z",
    source: "model",
  });
  const dated = app.store.news.item(item.id)!;
  assert.equal(dated.publishedAt, "2026-10-09T00:00:00.000Z");
  assert.equal(dated.dateSource, "model");
  assert.equal(app.store.news.cardForItem(item.id)!.publishedAt, "2026-10-09T00:00:00.000Z");

  const blank = new Dates({
    http: htmlHttp(page("", `<p>${"No dates anywhere in this text at all. ".repeat(6)}</p>`)),
    store: app.store,
    log: app.log,
    quick: app.quick,
  });
  const unknown = app.store.news.upsertItem({
    url: "https://example.dev/undated",
    title: "Undated",
  }).item;
  assert.deepEqual(await blank.resolve(unknown), { source: "unknown" });
  assert.equal(app.store.news.item(unknown.id)!.dateSource, "unknown");
});

test("feed dates are kept as they came", () => {
  const fed = app.store.news.upsertItem({
    url: "https://example.dev/fed",
    title: "Fed",
    publishedAt: "2026-10-10T00:00:00.000Z",
  }).item;
  assert.equal(fed.dateSource, "feed");
});

test("hfs reads the page: pageText fetches it once, and the rescore puts new scores on old cards", async () => {
  const { pageText } = await import("../src/news/page.ts");
  const { rescoreCards } = await import("../src/news/rescore.ts");
  let fetches = 0;
  const article = page(
    "",
    `<h1>pi 1.2.0 release notes</h1><p>${"Version 1.2.0 adds durable task timings, a changelog entry for every tool, and 14 fixes. ".repeat(10)}</p>`,
  );
  const http: Http = {
    get: async (url) => (fetches++, { status: 200, url, headers: new Headers(), text: article }),
    postJson: async () => {
      throw new Error("unused");
    },
  };
  const item = app.store.news.upsertItem({
    url: "https://pages.example.dev/pi-1-2-0",
    title: "pi 1.2.0",
    sourceName: "pi releases",
    excerpt: "pi 1.2.0",
  }).item;
  const text = await pageText({ http, store: app.store, log: app.log }, item);
  assert.match(text!, /durable task timings/);
  await pageText({ http, store: app.store, log: app.log }, app.store.news.item(item.id)!);
  assert.equal(fetches, 1, "the second read comes from the cache");

  const { card } = app.store.news.addCard({
    kind: "news",
    component: "brief",
    props: { title: "pi 1.2.0", summary: "s" },
    itemId: item.id,
    toolCallId: "rescore:1",
  });
  assert.equal(card.hfs, undefined);
  assert.ok(app.store.news.cardsToRescore(2).some((c) => c.id === card.id));
  const updated: number[] = [];
  const rescored = await rescoreCards({ ...app, http }, (id) => updated.push(id));
  assert.ok(rescored >= 1);
  assert.ok(updated.includes(card.id));
  assert.ok(app.store.news.card(card.id)!.hfs, "the card carries scores now");
  assert.ok(!app.store.news.cardsToRescore(2).some((c) => c.id === card.id), "scored once");
});
