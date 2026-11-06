// The crontab line, between markers, written idempotently with `crontab -` after a backup. Never `crontab -e`.
import { spawnSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { dirname } from "node:path";

export const BEGIN = "# >>> dna-cron >>>";
export const END = "# <<< dna-cron <<<";

export function readCrontab(): string {
  const r = spawnSync("crontab", ["-l"], { encoding: "utf8" });
  if (r.status === 0) return r.stdout;
  if (/no crontab/i.test(r.stderr)) return "";
  throw new Error(`crontab -l failed: ${r.stderr.trim() || r.error?.message}`);
}

function writeCrontab(text: string): void {
  const r = spawnSync("crontab", ["-"], { input: text, encoding: "utf8" });
  if (r.status !== 0) throw new Error(`crontab - failed: ${r.stderr.trim() || r.error?.message}`);
}

/** The managed line, or undefined when it is not installed. */
export function managedLine(text: string): string | undefined {
  const lines = text.split("\n");
  const i = lines.indexOf(BEGIN);
  return i >= 0 && lines[i + 2] === END ? lines[i + 1] : undefined;
}

export function withoutBlock(text: string): string {
  const out: string[] = [];
  let inside = false;
  for (const line of text.split("\n")) {
    if (line === BEGIN) inside = true;
    else if (line === END) inside = false;
    else if (!inside) out.push(line);
  }
  return out.join("\n").replace(/\n+$/, "");
}

/**
 * `<schedule> DNA_NODE_DIR=<node 24 bin> /bin/bash <script>`: the node that installs is the node that runs. Cron runs
 * bash with the script as an argument because macOS privacy blocks node's cwd when cron executes a script inside
 * ~/Documents directly (EPERM on process.cwd), even with Full Disk Access for cron.
 */
export function cronLine(schedule: string, script: string, nodeBin = process.execPath): string {
  if (schedule.trim().split(/\s+/).length !== 5)
    throw new Error(`Schedule must have 5 fields: ${schedule}`);
  return `${schedule.trim()} DNA_NODE_DIR=${dirname(nodeBin)} /bin/bash ${script}`;
}

export function install(
  line: string,
  backup = "/tmp/crontab.bak",
): { changed: boolean; line: string } {
  const current = readCrontab();
  if (managedLine(current) === line) return { changed: false, line };
  writeFileSync(backup, current, { mode: 0o600 });
  const rest = withoutBlock(current);
  writeCrontab(`${rest ? `${rest}\n` : ""}${BEGIN}\n${line}\n${END}\n`);
  return { changed: true, line };
}

export function uninstall(backup = "/tmp/crontab.bak"): { changed: boolean } {
  const current = readCrontab();
  if (managedLine(current) === undefined && !current.includes(BEGIN)) return { changed: false };
  writeFileSync(backup, current, { mode: 0o600 });
  const rest = withoutBlock(current);
  writeCrontab(rest ? `${rest}\n` : "");
  return { changed: true };
}
