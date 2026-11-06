// dna-network.yaml: the devices (this Mac, plus any always-on Mac mini or ssh box). `just net <verb> <id>`, DNA_TARGET and --device all look ids up here.
import { existsSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { parse } from "yaml";
import { repoRoot } from "./env.ts";

export const NETWORK_FILE = "dna-network.yaml";
export type DeviceKind = "local" | "ssh" | "exe-dev";
export type ServiceKind = "launchd" | "systemd";

export interface NetDevice {
  id: string;
  name: string;
  kind: DeviceKind;
  url: string;
  port: number;
  node: number;
  codeDir: string;
  envKeys: string[];
  cron: string;
  ssh?: string;
  service?: ServiceKind;
  vm?: string;
  tunnel?: { local: number; remote: number };
  /** Port of this device's browser hub on the laptop (hub_port). `just browser all` serves one hub per device. */
  hubPort?: number;
  /**
   * The UI the device serves itself (its own hub service). ssh devices opt in with `ui: http://host:port`
   * (open to that network); exe-dev devices always serve it at https://<vm>.exe.xyz behind the exe.dev login.
   */
  ui?: { url: string; port: number };
  create?: { cpu?: number; memory?: string; disk?: string };
}

export interface Network {
  file: string;
  devices: Record<string, NetDevice>;
}

type Raw = Record<string, unknown>;
const KINDS: DeviceKind[] = ["local", "ssh", "exe-dev"];

function str(v: unknown, where: string): string {
  if (typeof v !== "string" || !v.trim()) throw new Error(`${where} must be a non empty string`);
  return v.trim();
}

function int(v: unknown, where: string): number {
  if (typeof v !== "number" || !Number.isInteger(v) || v <= 0)
    throw new Error(`${where} must be a positive whole number`);
  return v;
}

export function parseNetwork(text: string, file = NETWORK_FILE): Network {
  const raw = (parse(text) ?? {}) as Raw;
  const defaults = (raw.defaults ?? {}) as Raw;
  const devices: Record<string, NetDevice> = {};
  for (const [id, value] of Object.entries((raw.devices ?? {}) as Raw)) {
    if (!/^[a-z][a-z0-9-]{0,30}$/.test(id))
      throw new Error(`devices.${id}: ids are lowercase letters, digits and dashes`);
    const d = { ...defaults, ...(value as Raw) } as Raw;
    const where = `devices.${id}`;
    const kind = str(d.kind, `${where}.kind`) as DeviceKind;
    if (!KINDS.includes(kind)) throw new Error(`${where}.kind must be one of: ${KINDS.join(", ")}`);
    const url = str(d.url, `${where}.url`).replace(/\/+$/, "");
    if (!/^https?:\/\//.test(url))
      throw new Error(`${where}.url must start with http:// or https://`);
    const device: NetDevice = {
      id,
      name: typeof d.name === "string" ? d.name : id,
      kind,
      url,
      port: int(d.port ?? 4850, `${where}.port`),
      node: int(d.node ?? 24, `${where}.node`),
      codeDir: str(d.code_dir ?? "~/pi-durable-news-agent", `${where}.code_dir`),
      envKeys: Array.isArray(d.env_keys)
        ? d.env_keys.map((k, i) => str(k, `${where}.env_keys[${i}]`))
        : [],
      cron: str(d.cron ?? "* * * * *", `${where}.cron`),
    };
    if (kind !== "local") {
      device.service = str(d.service, `${where}.service`) as ServiceKind;
      if (!["launchd", "systemd"].includes(device.service))
        throw new Error(`${where}.service must be launchd or systemd`);
    }
    if (kind === "ssh") device.ssh = str(d.ssh, `${where}.ssh`);
    if (kind === "exe-dev") {
      device.vm = str(d.vm, `${where}.vm`);
      device.ssh = `${device.vm}.exe.xyz`;
      device.create = d.create as NetDevice["create"];
    }
    if (d.hub_port !== undefined) device.hubPort = int(d.hub_port, `${where}.hub_port`);
    const ui = kind === "exe-dev" ? `https://${device.vm}.exe.xyz` : d.ui;
    if (ui !== undefined && kind !== "local") {
      const u = new URL(str(ui, `${where}.ui`));
      device.ui = {
        url: u.origin,
        port: int(d.ui_port ?? (u.port ? Number(u.port) : 4851), `${where}.ui_port`),
      };
    }
    if (d.tunnel) {
      const t = d.tunnel as Raw;
      device.tunnel = {
        local: int(t.local, `${where}.tunnel.local`),
        remote: int(t.remote, `${where}.tunnel.remote`),
      };
    }
    devices[id] = device;
  }
  const ports = new Map<number, string>();
  for (const d of Object.values(devices)) {
    if (d.hubPort === undefined) continue;
    const port = d.hubPort;
    const other = ports.get(port);
    if (other)
      throw new Error(
        `devices.${d.id}.hub_port ${port} is also ${other}'s; give each device its own hub_port`,
      );
    ports.set(port, d.id);
  }
  return { file, devices };
}

/** The laptop port that serves this device's browser UI. */
export const hubPort = (d: NetDevice): number => d.hubPort ?? 4851;

/** Read dna-network.yaml (DNA_NETWORK_FILE overrides); without one, only `local` exists. */
export function loadNetwork(
  file = process.env.DNA_NETWORK_FILE ?? join(repoRoot(), NETWORK_FILE),
): Network {
  const path = resolve(file);
  if (!existsSync(path))
    return parseNetwork(
      "devices:\n  local: { kind: local, url: http://127.0.0.1:4850 }\n",
      "(built in)",
    );
  return parseNetwork(readFileSync(path, "utf8"), path);
}

export function device(network: Network, id: string): NetDevice {
  const d = network.devices[id];
  if (!d)
    throw new Error(
      `No device ${id} in ${network.file}. Known: ${Object.keys(network.devices).join(", ")}`,
    );
  return d;
}

/** The API URL for a device id from the network file. */
export function targetUrl(id = process.env.DNA_TARGET ?? "local", network?: Network): string {
  return device(network ?? loadNetwork(), id).url;
}
