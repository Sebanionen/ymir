// Durability on a real device: start a sweep, restart the device's API service while the agent is mid sweep,
// and check the sweep resumes and completes with no duplicate cards.
//   node apps/shared/tests/live/restart.mjs <device>
import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { promisify } from "node:util";

const root = resolve(import.meta.dirname, "../../../..");
const device = process.argv[2];
if (!device) throw new Error("usage: node apps/shared/tests/live/restart.mjs <device>");
if (existsSync(join(root, ".env"))) process.loadEnvFile(join(root, ".env"));
const { loadNetwork } = await import(
  join(root, "apps/shared/packages/dna-sdk/src/node/network.ts")
);
const url = loadNetwork().devices[device].url;
const sh = promisify(execFile);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const check = (ok, msg) => {
  if (!ok) throw new Error(`FAIL ${msg}`);
  console.log(`PASS ${msg}`);
};
const call = async (path, init = {}, token = process.env.DNA_CLIENT_TOKEN) => {
  for (let i = 0; ; i++) {
    try {
      const res = await fetch(url + path, {
        ...init,
        headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      });
      if (res.status >= 500 && i < 30) throw new Error(String(res.status));
      return res.json();
    } catch (e) {
      if (i >= 60) throw e;
      await sleep(2000);
    }
  }
};

for (
  let i = 0;
  i < 120 &&
  (await call("/v1/sweeps?limit=5")).some((s) => s.status === "running" || s.status === "queued");
  i++
)
  await sleep(5000);
const requestId = `restart:${device}:${Date.now()}`;
const started = await call(
  "/v1/workflows/news-sweep",
  { method: "POST", body: JSON.stringify({ requestId, trigger: "test" }) },
  process.env.DNA_CRON_TOKEN,
);
check(started.status === "accepted", `sweep ${started.sweep?.id} accepted`);
const id = started.sweep.id;

let sweep;
for (let i = 0; i < 120; i++) {
  sweep = await call(`/v1/sweeps/${id}`);
  if (
    sweep.phases.some((p) => p.phase === "gate" && p.status === "done") ||
    ["completed", "no_news"].includes(sweep.status)
  )
    break;
  await sleep(1000);
}
check(
  !["completed", "no_news", "failed"].includes(sweep.status),
  `sweep ${id} is mid run (${sweep.status}, ${sweep.phases.map((p) => `${p.phase} ${p.status}`).join(", ")})`,
);
const before = (await call("/healthz")).uptime;
const restart = await sh(
  process.execPath,
  [join(root, "apps/dna-cli/bin/dna.mjs"), "--json", "net", "restart", device],
  { env: { ...process.env, NODE_NO_WARNINGS: "1" }, timeout: 240_000 },
);
check(
  JSON.parse(restart.stdout).every((s) => s.ok),
  `${device} restarted mid sweep`,
);
check((await call("/healthz")).uptime < before + 5, "the API process is new");

for (const end = Date.now() + 12 * 60_000; Date.now() < end; await sleep(5000)) {
  sweep = await call(`/v1/sweeps/${id}`);
  if (["completed", "no_news", "failed", "stalled"].includes(sweep.status)) break;
}
check(
  ["completed", "no_news"].includes(sweep.status),
  `sweep ${id} resumed and is ${sweep.status}`,
);
check(sweep.audit?.missing.length === 0, `sweep ${id} audit is clean`);
const cards = (await call("/v1/feed?limit=200")).items;
const items = cards.filter((c) => c.kind === "news").map((c) => c.itemId);
check(
  new Set(items).size === items.length,
  `no duplicate cards (${cards.filter((c) => c.sweepId === id).length} from sweep ${id}, ${cards.length} total)`,
);
console.log(
  JSON.stringify({
    device,
    sweepId: id,
    status: sweep.status,
    presented: sweep.presented,
    cost: sweep.cost,
    credits: sweep.firecrawlCreditsUsed,
  }),
);
console.log(`ALL RESTART CHECKS PASSED (${device})`);
