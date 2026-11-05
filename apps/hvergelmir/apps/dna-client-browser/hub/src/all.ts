// `just browser all`: a laptop hub for every device in dna-network.yaml that does not serve its own UI, each in the
// background on its hub_port, so every UI link `just net status` prints opens. Opens the ssh tunnel first.
import { spawn, spawnSync } from "node:child_process";
import { closeSync, mkdirSync, openSync } from "node:fs";
import { join, resolve } from "node:path";
import { hubPort, loadNetwork, loadRootEnv, repoRoot } from "@dna/sdk/node";

loadRootEnv();
const root = repoRoot();
const appDir = resolve(import.meta.dirname, "../..");
const env = { ...process.env, NODE_NO_WARNINGS: "1" };
mkdirSync(join(root, "logs"), { recursive: true });

const devices = Object.values(loadNetwork().devices).filter((d) => !d.ui);
const taken = new Map<number, string>();
for (const d of devices) {
  const other = taken.get(hubPort(d));
  if (other) {
    console.error(
      `${d.id} and ${other} both use port ${hubPort(d)}. Give each device a hub_port in dna-network.yaml.`,
    );
    process.exit(1);
  }
  taken.set(hubPort(d), d.id);
}
for (const d of devices) {
  if (d.tunnel)
    spawnSync(process.execPath, [join(root, "apps/dna-cli/bin/dna.mjs"), "net", "tunnel", d.id], {
      env,
      stdio: "ignore",
      timeout: 30_000,
    });
  const out = openSync(join(root, "logs", `hub-${d.id}.out`), "a");
  spawn(process.execPath, ["--import", "tsx", "hub/src/main.ts", "--device", d.id], {
    cwd: appDir,
    env,
    detached: true,
    stdio: ["ignore", out, out],
  }).unref();
  closeSync(out);
}

const up = async (id: string, port: number) => {
  for (let i = 0; i < 60; i++) {
    try {
      const r = await fetch(`http://127.0.0.1:${port}/hub/healthz`);
      if (((await r.json()) as { device?: string }).device === id) return true;
    } catch {}
    await new Promise((r) => setTimeout(r, 250));
  }
  return false;
};
let failed = false;
for (const d of devices) {
  const ok = await up(d.id, hubPort(d));
  failed ||= !ok;
  console.log(
    `${d.id.padEnd(8)} ${ok ? "http://localhost:" + hubPort(d) : `FAIL, see logs/hub-${d.id}.out`}`,
  );
}
process.exitCode = failed ? 1 : 0;
