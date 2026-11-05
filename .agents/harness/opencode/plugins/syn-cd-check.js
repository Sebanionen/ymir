import { realpathSync } from "node:fs";
import { resolve } from "node:path";
import { spawn } from "node:child_process";
import { Plugin } from "@opencode/plugin";

// Sýn — PreToolUse seatbelt for OpenCode: block a stray persistent top-level
// `cd` in the primary Brokk checkout before the agent's bash tool relocates the
// shell out of the home. bin/gates/checks/syn-cd-pretool-check.sh is the owner of that
// decision. tool.execute.before can block by throwing. Ported from the upstream
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
  id: "ymir.syn.cd-check",
  async setup(ctx) {
    const root = await resolveRoot(ctx.location?.directory);
    if (!root) return;

    await ctx.tool.hook("execute.before", async (event) => {
      if (event?.tool !== "bash") return;
      const command = event?.input?.command;
      if (!command || typeof command !== "string") return;

      const result = await runProcess(`${root}/bin/gates/checks/syn-cd-pretool-check.sh`, ["--command", command]);
      if (result.code !== 2) return;

      const reason = result.stderr.trim() || "denied by the cd-guard PreToolUse seatbelt";
      throw new Error(reason);
    });
  },
});
