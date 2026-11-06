// Fetch every default source once, live, into a throwaway database, and print a status table.
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createLogger, loadRootEnv } from "@dna/sdk/node";
import { openStore } from "../src/db/store.ts";
import { liveHttp } from "../src/news/http.ts";
import { fetchSource } from "../src/news/sources/index.ts";

loadRootEnv();
const dir = mkdtempSync(join(tmpdir(), "dna-sources-"));
const log = createLogger("sources-check");
const store = openStore(dir, join(import.meta.dirname, "../config"));
const http = liveHttp(log);
let failed = 0;
try {
  console.log(`${"source".padEnd(26)} ${"kind".padEnd(16)} ${"entries".padStart(7)}  status`);
  for (const source of store.sources.list()) {
    const r = await fetchSource(source, {
      http,
      store,
      log,
      since: new Date(Date.now() - 86_400_000),
      queries: ["durable agents"],
    });
    if (!r.ok) failed++;
    console.log(
      `${source.name.padEnd(26)} ${source.kind.padEnd(16)} ${String(r.docs.length).padStart(7)}  ${r.ok ? r.status : `FAILED ${r.error}`}`,
    );
  }
} finally {
  store.close();
  rmSync(dir, { recursive: true, force: true });
}
process.exit(failed ? 1 : 0);
