// The local driver: this checkout runs the API and the browser hub (the UI) as background processes on this Mac.
// The tick is opt in: `just net cron local install` adds the crontab line, `just net down local` removes it and
// stops both processes.
import { spawn, spawnSync } from "node:child_process";
import {
  closeSync,
  existsSync,
  mkdirSync,
  openSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { hubPort, repoRoot, type NetDevice } from "@dna/sdk/node";
import { managedLine, readCrontab } from "../../../dna-server-cron/src/crontab.ts";
import { probe, type Check } from "./probe.ts";

const root = () => repoRoot();
const dataDir = () => process.env.DNA_DATA_DIR ?? join(root(), "data");

/** The pid in a pid or lock file, if that process is alive. */
function livePid(file: string): number | undefined {
  if (!existsSync(file)) return undefined;
  const pid = Number(readFileSync(file, "utf8"));
  try {
    process.kill(pid, 0);
    return pid;
  } catch {
    return undefined;
  }
}

/** The API's pid from the harness lock file, if that process is alive. */
export const apiPid = () => livePid(join(dataDir(), "agent.sqlite.lock"));
const hubPidFile = () => join(dataDir(), "hub.pid");
/** The local hub's pid, if `up` started it and it is alive. */
export const hubPid = () => livePid(hubPidFile());

async function hubUp(id: string, port: number, ms: number): Promise<boolean> {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    try {
      const r = await fetch(`http://127.0.0.1:${port}/hub/healthz`, {
        signal: AbortSignal.timeout(2000),
      });
      if (((await r.json()) as { device?: string }).device === id) return true;
    } catch {}
    await new Promise((r) => setTimeout(r, 300));
  }
  return false;
}

/** Builds the UI when it has never been built, then starts the hub on the device's hub_port in the background. */
async function startHub(d: NetDevice): Promise<Step> {
  const port = hubPort(d);
  if (await hubUp(d.id, port, 500))
    return { step: "ui", ok: true, detail: `the UI is already up at http://localhost:${port}` };
  const appDir = join(root(), "apps/dna-client-browser");
  if (!existsSync(join(appDir, "fe/dist/index.html"))) {
    const build = spawnSync("npm", ["run", "build", "-w", "dna-client-browser"], {
      cwd: root(),
      encoding: "utf8",
    });
    if (build.status !== 0)
      return {
        step: "ui",
        ok: false,
        detail: `the UI build failed: ${build.stderr.trim().slice(-400)}`,
      };
  }
  mkdirSync(dataDir(), { recursive: true });
  mkdirSync(join(root(), "logs"), { recursive: true });
  const out = openSync(join(root(), "logs/hub.out"), "a");
  const child = spawn(process.execPath, ["--import", "tsx", "hub/src/main.ts", "--device", d.id], {
    cwd: appDir,
    detached: true,
    stdio: ["ignore", out, out],
    env: { ...process.env, NODE_NO_WARNINGS: "1" },
  });
  child.unref();
  closeSync(out);
  writeFileSync(hubPidFile(), String(child.pid));
  const ok = await hubUp(d.id, port, 30_000);
  return {
    step: "ui",
    ok,
    detail: ok
      ? `the UI is up at http://localhost:${port} (pid ${child.pid})`
      : "the hub did not answer within 30 s, see logs/hub.out",
  };
}

async function stop(pid: number): Promise<boolean> {
  process.kill(pid, "SIGTERM");
  const end = Date.now() + 15_000;
  while (Date.now() < end) {
    try {
      process.kill(pid, 0);
    } catch {
      return true;
    }
    await new Promise((r) => setTimeout(r, 200));
  }
  return false;
}

async function healthy(url: string, ms: number): Promise<boolean> {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    try {
      if ((await fetch(`${url}/healthz`, { signal: AbortSignal.timeout(2000) })).ok) return true;
    } catch {}
    await new Promise((r) => setTimeout(r, 300));
  }
  return false;
}

function cron(verb: "install" | "uninstall" | "status"): string {
  const r = spawnSync(
    process.execPath,
    ["--import", "tsx", join(root(), "apps/dna-server-cron/src/main.ts"), verb],
    {
      cwd: join(root(), "apps/dna-server-cron"),
      encoding: "utf8",
      env: { ...process.env, NODE_NO_WARNINGS: "1" },
    },
  );
  if (r.status !== 0) throw new Error(r.stderr.trim() || `cron ${verb} failed`);
  return r.stdout.trim();
}

export interface Step {
  step: string;
  ok: boolean;
  detail: string;
}

export const local = {
  async status(d: NetDevice, tokens: { client?: string; cron?: string }) {
    const pid = apiPid();
    const checks = await probe(d.url, tokens);
    return {
      device: d.id,
      url: d.url,
      online: checks[0].ok,
      pid,
      hubPid: hubPid(),
      cron: managedLine(readCrontab()) ?? null,
      checks,
    };
  },

  async probe(d: NetDevice, tokens: { client?: string; cron?: string }): Promise<Check[]> {
    return probe(d.url, tokens);
  },

  async up(d: NetDevice, tokens: { client?: string; cron?: string }): Promise<Step[]> {
    const steps: Step[] = [];
    let pid = apiPid();
    if (!pid) {
      mkdirSync(join(root(), "logs"), { recursive: true });
      const out = openSync(join(root(), "logs/api.out"), "a");
      const child = spawn(
        process.execPath,
        ["--import", "tsx", "src/main.ts", "--port", String(d.port)],
        {
          cwd: join(root(), "apps/dna-server-api"),
          detached: true,
          stdio: ["ignore", out, out],
          env: { ...process.env, NODE_NO_WARNINGS: "1" },
        },
      );
      child.unref();
      closeSync(out);
      pid = child.pid;
      steps.push({
        step: "service",
        ok: true,
        detail: `started the API (pid ${pid}), output in logs/api.out`,
      });
    } else
      steps.push({ step: "service", ok: true, detail: `the API is already running (pid ${pid})` });
    const up = await healthy(d.url, 90_000);
    steps.push({
      step: "wait",
      ok: up,
      detail: up ? "healthz answered" : "no healthz within 90 s, see logs/api.out",
    });
    if (!up) return steps;
    const checks = await probe(d.url, tokens);
    steps.push({
      step: "probe",
      ok: checks.every((c) => c.ok),
      detail: checks.map((c) => `${c.ok ? "pass" : "FAIL"} ${c.name} (${c.detail})`).join("; "),
    });
    steps.push(await startHub(d));
    return steps;
  },

  async down(): Promise<Step[]> {
    const steps: Step[] = [{ step: "cron", ok: true, detail: cron("uninstall") }];
    const hub = hubPid();
    if (hub) {
      const ok = await stop(hub);
      if (ok) rmSync(hubPidFile(), { force: true });
      steps.push({
        step: "ui",
        ok,
        detail: ok ? `stopped the hub (pid ${hub})` : `hub pid ${hub} did not stop`,
      });
    } else steps.push({ step: "ui", ok: true, detail: "the hub is not running" });
    const pid = apiPid();
    if (!pid) return [...steps, { step: "service", ok: true, detail: "the API is not running" }];
    const ok = await stop(pid);
    return [
      ...steps,
      {
        step: "service",
        ok,
        detail: ok ? `stopped the API (pid ${pid})` : `pid ${pid} did not stop`,
      },
    ];
  },

  cron(verb: "install" | "remove" | "status"): string {
    return cron(verb === "remove" ? "uninstall" : verb);
  },

  logs(app: string, lines: number): string {
    const file = join(root(), "logs", `${app}.jsonl`);
    if (!existsSync(file)) return `No ${file}`;
    return readFileSync(file, "utf8").trimEnd().split("\n").slice(-lines).join("\n");
  },
};
