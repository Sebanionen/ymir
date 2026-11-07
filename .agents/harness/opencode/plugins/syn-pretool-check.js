import { realpathSync } from "node:fs";
import { resolve } from "node:path";
import { spawn } from "node:child_process";
import { Plugin } from "@opencode/plugin";

// Sýn — PreToolUse seatbelt for OpenCode: the watcher arm itself is owned by
// syn-watch-arm.js (a plugin-owned child process, never a model tool call), so
// the residual risk is the agent shelling bin/pi/syn-watch-arm.sh wrong through
// its own bash tool. bin/gates/checks/syn-arm-pretool-check.sh is the owner of that decision.
// tool.execute.before can block by throwing. Ported from the upstream
// agent-distro reference and retargeted to the Brokk runtime.

function runProcess(command, args) {
  return new Promise((resolvePromise) => {
    const child = spawn(command, args, { stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", () => resolvePromise({ code: 0, stdout: "", stderr: "" }));
    child.on("close", (code) => resolvePromise({ code: code ?? 0, stdout, stderr }));
  });
}

async function resolveRoot(anchor) {
  if (!anchor) return "";
  const result = await runProcess("git", ["-C", anchor, "rev-parse", "--show-toplevel"]);
  const root = result.stdout.trim();
  if (result.code === 0 && root) return root;
  try {
    return realpathSync(anchor);
  } catch {
    return resolve(anchor);
  }
}

export default Plugin.define({
  id: "ymir.syn.pretool-check",
  async setup(ctx) {
    const root = await resolveRoot(ctx.location?.directory);
    if (!root) return;

    // One seatbelt per invariant family; the first denial blocks the command.
    // The scripts live under bin/gates/checks — a `bin/<name>` path silently matched
    // nothing and let every command through (found 2026-11-04 while porting to V2).
    // `syn-cd-pretool-check.sh` is owned by its own plugin, so it is not listed here.
    const checks = [
      ["syn-arm-pretool-check.sh", "the watcher-arm PreToolUse seatbelt"],
      ["syn-guard-pretool-check.sh", "the runtime-invariant PreToolUse seatbelt"],
      ["syn-spawn-pretool-check.sh", "the worker-spawn PreToolUse seatbelt"],
      ["syn-asset-pretool-check.sh", "the asset-write PreToolUse seatbelt"],
    ];

    await ctx.tool.hook("execute.before", async (event) => {
      if (event?.tool !== "bash") return;
      const command = event?.input?.command;
      if (!command || typeof command !== "string") return;

      for (const [script, fallback] of checks) {
        const result = await runProcess(`${root}/bin/gates/checks/${script}`, ["--command", command]);
        if (result.code === 2) {
          throw new Error(result.stderr.trim() || `denied by ${fallback}`);
        }
      }
    });
  },
});
