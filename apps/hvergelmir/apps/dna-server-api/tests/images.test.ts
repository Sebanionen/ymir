import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { test } from "node:test";
import { Images } from "../src/news/images.ts";
import { fixtureHttp } from "../src/news/fixtures.ts";
import { PROMPTS_DIR, tempStore } from "./helpers.ts";

test("a valid source og:image wins; otherwise OpenAI generates one and its cost is saved", async () => {
  const { store, dir, cleanup } = tempStore();
  try {
    let calls = 0;
    let sent: Record<string, unknown> = {};
    const fakeFetch = (async (_url: string, init: RequestInit) => {
      calls++;
      sent = JSON.parse(String(init.body));
      return new Response(
        JSON.stringify({
          data: [{ b64_json: Buffer.from("jpg").toString("base64") }],
          usage: {
            input_tokens: 100,
            output_tokens: 400,
            input_tokens_details: { text_tokens: 100, image_tokens: 0 },
          },
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    }) as unknown as typeof fetch;
    const images = new Images({
      store,
      http: fixtureHttp("news"),
      dataDir: dir,
      promptsDir: PROMPTS_DIR,
      model: "gpt-image-2.5-flare",
      openaiKey: "sk-test",
      fetch: fakeFetch,
    });
    const { item } = store.news.upsertItem({
      url: "https://openai.com/news/a",
      title: "A",
      imageUrl: "https://cdn.fixture.dev/images/codex.png",
    });
    const sourceId = await images.resolve(item);
    assert.equal(store.news.image(sourceId!)!.origin, "source");
    const { item: bare } = store.news.upsertItem({ url: "https://openai.com/news/b", title: "B" });
    assert.equal(await images.resolve(bare), undefined);
    const prompt = images.prompt({ title: "B", summary: "about B" });
    assert.match(prompt, /No words, no letters/);
    const id = images.pending(bare.id, prompt);
    const result = await images.generate(id, prompt);
    assert.deepEqual(
      result,
      { ok: true, costUsd: 0.0125 },
      "100 text tokens at $5 plus 400 output tokens at $30 per 1M",
    );
    assert.equal(sent.model, "gpt-image-2.5-flare");
    assert.equal(sent.quality, "low");
    const row = store.news.image(id)!;
    assert.equal(row.status, "ready");
    assert.ok(existsSync(row.filePath!));
    assert.equal(calls, 1);
  } finally {
    cleanup();
  }
});

test("without an OpenAI key the image fails cleanly and the card keeps no image", async () => {
  const { store, dir, cleanup } = tempStore();
  try {
    const images = new Images({
      store,
      http: fixtureHttp("news"),
      dataDir: dir,
      promptsDir: PROMPTS_DIR,
      model: "gpt-image-2.5-flare",
    });
    const { item } = store.news.upsertItem({ url: "https://openai.com/news/c", title: "C" });
    const id = images.pending(item.id, "a prompt");
    const result = await images.generate(id, "a prompt");
    assert.equal(result.ok, false);
    assert.match(result.error!, /OPENAI_API_KEY/);
    assert.equal(store.news.image(id)!.status, "failed");
  } finally {
    cleanup();
  }
});
