import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import type { Conversation } from "@earendil-works/pi-durable";
import { htmlLinks, markdownLinks } from "../src/news/extract.ts";
import { setDeepResearch } from "../src/news/deep-research.ts";
import { openApp, type App } from "../src/runtime.ts";
import type { Config } from "../src/config.ts";
import { fauxApp, until } from "./helpers.ts";

let app: App;
let config: Config;
let cleanup: () => Promise<void>;
let n = 0;

before(async () => {
  ({ app, config, cleanup } = await fauxApp({
    DNA_FIXTURE_SET: "news",
    FIRECRAWL_API_KEY: "fc-test",
  }));
});
after(() => cleanup());

const textOf = (entry: { model?: unknown }) => JSON.stringify(entry.model ?? []);

/** The main conversation's user messages and replies that mention one deep research. */
async function deepEntries(conversation: Conversation, researchId: number) {
  const page = await conversation.entries({ order: "ascending" }, 500, undefined, app.ctx);
  const reports = page.items.filter(
    (e) => e.kind === "pi.user" && textOf(e).includes(`Deep research #${researchId}: researcher`),
  );
  const replies = page.items.filter(
    (e) =>
      e.kind === "pi.assistant" && textOf(e).includes(`Deep research ${researchId}, researcher`),
  );
  return { reports: reports.map(textOf), replies: replies.map(textOf) };
}

async function startDeepResearch(args: object) {
  const submission = await app.main.submit(
    {
      type: "input",
      content: `FAUX_CALL deep_dive_research ${JSON.stringify(args)}`,
      requestId: `deep-test:${n++}`,
    },
    app.ctx,
  );
  await submission.wait(app.ctx);
  const page = await app.main.entries({ order: "descending" }, 20, undefined, app.ctx);
  const result = page.items.find((e) => e.kind === "pi.tool-result")!.model![0] as {
    isError: boolean;
    content: { text?: string }[];
  };
  const text = result.content.map((c) => c.text ?? "").join("");
  return { text, researchId: Number(text.match(/deep research #(\d+)/)?.[1]) };
}

const researcherIndexes = (reports: string[]) =>
  reports.map((r) => Number(r.match(/researcher (\d+) of/)?.[1])).sort((a, b) => a - b);

test("deep_dive_research is a desk tool; the deep-research agent has its own tools and prompt", () => {
  const desk = app.agents.tools["news-desk"].map((t) => t.name);
  assert.ok(desk.includes("deep_dive_research"));
  assert.deepEqual(
    app.agents.tools["deep-research"].map((t) => t.name),
    ["deep_search", "open_page", "read_item"],
  );
  assert.ok(!app.agents.tools["news-researcher"].some((t) => t.name === "deep_search"));
  const deskTool = app.agents.tools["news-desk"].find((t) => t.name === "deep_dive_research")!;
  assert.match(deskTool.description, /Use it only when the reader asks/);
});

test("5 deep-research subagents run in the background; each answer reaches the desk once, as it finishes", async () => {
  const item = app.store.news.upsertItem({
    url: "https://example.com/acme-raises",
    title: "Acme raises about $250M for agent swarms",
    sourceName: "note.com",
    excerpt: "A Mandiant founder's agent swarm startup.",
  }).item;
  const started = await startDeepResearch({
    question: "How does Acme's agent swarm find exploitable paths?",
    item_id: item.id,
    count: 5,
  });
  assert.match(started.text, /Started deep research #\d+: 5 deep-research subagents/);
  assert.match(started.text, /arrives as its own message/);

  await until(
    async () => (await deepEntries(app.main, started.researchId)).replies.length >= 5,
    60_000,
    "5 deep research answers relayed",
  );
  await app.main.waitForIdle(app.ctx);
  const { reports, replies } = await deepEntries(app.main, started.researchId);
  assert.deepEqual(researcherIndexes(reports), [1, 2, 3, 4, 5], "each researcher reported once");
  assert.equal(replies.length, 5);
  for (const r of reports) {
    assert.match(r, /of 5 reported/);
    assert.match(r, /\*\*Answer\*\*/);
    assert.match(r, /\*\*Trail\*\*: https?:/, "the researcher opened at least one page");
  }

  // Telemetry: the five subagents are deep-research conversations, linked to the tool call, and used their tools.
  const db = app.store.db;
  const children = (
    db
      .prepare("SELECT conversation_id FROM agent_conversations WHERE agent = 'deep-research'")
      .all() as { conversation_id: number }[]
  ).map((r) => r.conversation_id);
  assert.equal(children.length, 5);
  const call = db
    .prepare("SELECT details_json FROM tool_calls WHERE tool_name = 'deep_dive_research'")
    .get() as { details_json: string };
  assert.deepEqual(JSON.parse(call.details_json).children, children);
  const used = db
    .prepare(
      `SELECT DISTINCT tool_name FROM tool_calls WHERE conversation_id IN (${children.join(",")}) ORDER BY tool_name`,
    )
    .all() as { tool_name: string }[];
  assert.deepEqual(
    used.map((u) => u.tool_name),
    ["deep_search", "open_page"],
  );
  const task = db
    .prepare("SELECT status, outcome FROM tasks WHERE task_id = ?")
    .get(started.researchId) as { status: string; outcome: string };
  assert.equal(task.status, "terminal");
  assert.equal(task.outcome, "completed");
});

test("the reader's setting picks the count when the reader names none", async () => {
  setDeepResearch(app.store, app.log, { count: 2 });
  const started = await startDeepResearch({
    question: "Who confirms the 38 verified attack paths?",
  });
  assert.match(
    started.text,
    /2 deep-research subagents on anthropic\/claude-haiku-5\.5, thinking xhigh/,
  );
  await until(
    async () => (await deepEntries(app.main, started.researchId)).replies.length >= 2,
    60_000,
    "2 answers",
  );
  setDeepResearch(app.store, app.log, { count: 1 });
});

test("a restart mid research resumes it: every researcher still reports exactly once", async () => {
  const started = await startDeepResearch({
    question: "What is Acme's methodology?",
    count: 3,
  });
  await app.close();
  app = await openApp(config);
  await until(
    async () => (await deepEntries(app.main, started.researchId)).replies.length >= 3,
    60_000,
    "3 answers after the restart",
  );
  await app.main.waitForIdle(app.ctx);
  await new Promise((r) => setTimeout(r, 500));
  const { reports } = await deepEntries(app.main, started.researchId);
  assert.deepEqual(researcherIndexes(reports), [1, 2, 3]);
});

test("open_page reads a page with its links; links are absolute, once each, never the page itself", () => {
  const html =
    '<a href="/about">About</a><a href="https://other.dev/x#y">X</a><a href="https://other.dev/x">dup</a><a href="#top">top</a><a href="mailto:a@b.c">mail</a>';
  assert.deepEqual(htmlLinks(html, "https://site.dev/post"), [
    { text: "About", url: "https://site.dev/about" },
    { text: "X", url: "https://other.dev/x" },
  ]);
  assert.deepEqual(
    markdownLinks('See [the docs](https://docs.dev/a "Docs") and [home](/).', "https://docs.dev/a"),
    [{ text: "home", url: "https://docs.dev/" }],
  );
});
