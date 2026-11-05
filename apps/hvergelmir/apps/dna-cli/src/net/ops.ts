// Process helpers for the device drivers: local commands, remote shell scripts over ssh (scripts and secrets
// travel on stdin, never argv), rsync and the exe.dev control plane.
import { spawn } from "node:child_process";
import type { NetDevice } from "@dna/sdk/node";

export interface RunResult {
  code: number;
  stdout: string;
  stderr: string;
}

export interface RunOptions {
  stdin?: string;
  timeoutMs?: number;
  echo?: boolean;
  cwd?: string;
  allowFail?: boolean;
}

export function run(cmd: string, args: string[], options: RunOptions = {}): Promise<RunResult> {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, {
      cwd: options.cwd,
      env: process.env,
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    const timer = options.timeoutMs
      ? setTimeout(() => {
          child.kill("SIGTERM");
          stderr += `\n[timeout after ${options.timeoutMs} ms]`;
        }, options.timeoutMs)
      : undefined;
    child.stdout.on("data", (chunk: Buffer) => {
      stdout += chunk;
      if (options.echo) process.stdout.write(chunk);
    });
    child.stderr.on("data", (chunk: Buffer) => {
      stderr += chunk;
      if (options.echo) process.stderr.write(chunk);
    });
    child.on("error", (e) => {
      if (timer) clearTimeout(timer);
      reject(e);
    });
    child.on("close", (code) => {
      if (timer) clearTimeout(timer);
      const result = { code: code ?? 1, stdout, stderr };
      if (result.code !== 0 && !options.allowFail)
        reject(
          Object.assign(
            new Error(
              `${cmd} ${args.slice(0, 3).join(" ")} failed (exit ${result.code}): ${stderr.trim().slice(-800)}`,
            ),
            { result },
          ),
        );
      else resolve(result);
    });
    child.stdin.end(options.stdin ?? "");
  });
}

export const SSH_OPTS = [
  "-o",
  "BatchMode=yes",
  "-o",
  "ConnectTimeout=15",
  "-o",
  "StrictHostKeyChecking=accept-new",
  "-o",
  "ServerAliveInterval=15",
];

/** "~/x" becomes "$HOME/x" inside double-quoted remote shell strings. */
export const shPath = (p: string) =>
  p === "~" ? "$HOME" : p.startsWith("~/") ? `$HOME/${p.slice(2)}` : p;
/** Single-quote a value for a POSIX shell. */
export const q = (s: string) => `'${s.replaceAll("'", `'\\''`)}'`;

/** Brew is not on the non-interactive ssh PATH, and nvm needs loading. */
export const PRELUDE = `set -e
export NVM_DIR="$HOME/.nvm"
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" >/dev/null 2>&1 || true
`;

export function sshTarget(device: NetDevice): string {
  if (!device.ssh) throw new Error(`${device.id} (kind ${device.kind}) has no ssh target`);
  return device.ssh;
}

/** Run a POSIX shell script on the device; the script, and any secret in it, goes over stdin. */
export function remote(device: NetDevice, script: string, options: Omit<RunOptions, "stdin"> = {}) {
  return run("ssh", [...SSH_OPTS, sshTarget(device), "sh -s"], {
    ...options,
    stdin: PRELUDE + script,
  });
}

export const DEPLOY_EXCLUDES = [
  "node_modules",
  "/data",
  "/logs",
  "/.env",
  "/.git",
  "/specs",
  "/dna-network.yaml",
  "test-results",
  "dist",
  ".DS_Store",
  "*.log",
];

export function rsync(device: NetDevice, root: string, dest: string) {
  return run(
    "rsync",
    [
      "-a",
      "--delete",
      ...DEPLOY_EXCLUDES.flatMap((x) => ["--exclude", x]),
      "-e",
      `ssh ${SSH_OPTS.join(" ")}`,
      "./",
      `${sshTarget(device)}:${dest}/`,
    ],
    { cwd: root, timeoutMs: 600_000 },
  );
}

/** The exe.dev control plane: ssh exe.dev <verb> --json. */
export async function exeDev<T = unknown>(args: string[], timeoutMs = 60_000): Promise<T> {
  const result = await run(
    "ssh",
    ["-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "exe.dev", ...args, "--json"],
    { timeoutMs },
  );
  const text = result.stdout.trim();
  try {
    return (text ? JSON.parse(text) : {}) as T;
  } catch {
    return { raw: text } as T;
  }
}

export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
