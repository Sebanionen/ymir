import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { DnaError, ROUTES, type RouteId } from "@dna/sdk";
import { bootServer, type Booted } from "./server.ts";

let s: Booted;
before(async () => {
  s = await bootServer();
});
after(() => s.cleanup());

const status = async (p: Promise<unknown>) => {
  try {
    await p;
    return 200;
  } catch (e) {
    assert.ok(e instanceof DnaError, String(e));
    return e.status;
  }
};

test("/healthz is open", async () => {
  const h = await s.anon.healthz();
  assert.equal(h.ok, true);
  assert.equal(h.device, "test");
});

test("every other route needs a token: 401 without one, with the error envelope", async () => {
  for (const id of Object.keys(ROUTES) as RouteId[]) {
    const route = ROUTES[id];
    if (route.scope === "open") continue;
    const res = await fetch(s.base + route.path.replace(/:id/, "1"), {
      method: route.method,
      headers: { "content-type": "application/json" },
      body: route.method === "GET" ? undefined : "{}",
    });
    assert.equal(res.status, 401, `${id} without a token`);
    const body = (await res.json()) as { error: { code: string } };
    assert.equal(body.error.code, "unauthorized");
  }
  const wrong = await fetch(`${s.base}/v1/info`, {
    headers: { authorization: "Bearer dna_not_the_token_at_all_but_long_enough" },
  });
  assert.equal(wrong.status, 401);
});

test("the client token cannot start a workflow", async () => {
  const res = await fetch(`${s.base}/v1/workflows/news-sweep`, {
    method: "POST",
    headers: { authorization: `Bearer ${s.tokens.client}`, "content-type": "application/json" },
    body: JSON.stringify({ requestId: "x" }),
  });
  assert.equal(res.status, 403);
  assert.deepEqual(await res.json(), {
    error: { code: "forbidden", message: "This route needs the workflow scope" },
  });
});

test("the cron token cannot chat, give feedback, change settings or read", async () => {
  assert.equal(await status(s.cron.send({ content: "hi" })), 403);
  assert.equal(await status(s.cron.feedback(1, { signal: "more" })), 403);
  assert.equal(await status(s.cron.setCompaction({ background: 90_000 })), 403);
  assert.equal(await status(s.cron.addKeyword({ kind: "topic", term: "x" })), 403);
  assert.equal(await status(s.cron.info()), 403);
});

test("the cron token starts a sweep: 202", async () => {
  const r = await s.cron.newsSweep({ requestId: "cron:test:1" });
  assert.equal(r.status, 202);
  assert.equal(r.data.status, "accepted");
});

test("the client token reads, and unknown routes are 404 in the envelope", async () => {
  const info = await s.client.info();
  assert.equal(info.device, "test");
  assert.equal(info.searchMode, "fixture");
  const res = await fetch(`${s.base}/v1/nope`, {
    headers: { authorization: `Bearer ${s.tokens.client}` },
  });
  assert.equal(res.status, 404);
  assert.equal(((await res.json()) as { error: { code: string } }).error.code, "not_found");
});

test("the server refuses to boot with a short token or equal tokens", async () => {
  await assert.rejects(bootServer({ DNA_CRON_TOKEN: "short" }), /at least 32 characters/);
  const same = "dna_" + "x".repeat(40);
  await assert.rejects(bootServer({ DNA_CLIENT_TOKEN: same, DNA_CRON_TOKEN: same }), /must differ/);
});
