import { spawn } from "node:child_process";
import { realpathSync } from "node:fs";
import { resolve } from "node:path";
import { Plugin } from "@opencode/plugin";
import { encodeRoddOperationalInput } from "./lib/rodd-operational-input.js";

// Sága — Brokk primary session-start nudge for OpenCode.
//
// Sága ("the seeress who sees all that happens") delivers the session-start
// digest into model context. OpenCode is a nudge-tier surface: the plugin runs
// the run wrapper once per session id and injects its output through a native
// session prompt. Ported from the upstream agent-distro reference and
// retargeted to the Brokk runtime (docs/plans/29-brokk-distro-runtime.md).

const handledSessions = new Set();

function runProcess(command, args) {
  return new Promise((resolveResult) => {
    const child = spawn(command, args, { stdio: ["ignore", "pipe", "ignore"] });
    let stdout = "";
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.on("error", () => resolveResult({ code: 0, stdout: "" }));
    child.on("close", (code) => resolveResult({ code: code ?? 0, stdout }));
  });
}

function resolvePath(anchor) {
  try {
    return realpathSync(anchor);
  } catch {
    return resolve(anchor);
  }
}

async function resolveRoot(anchor) {
  if (!anchor) return "";
  const result = await runProcess("git", ["-C", anchor, "rev-parse", "--show-toplevel"]);
  const root = result.stdout.trim();
  if (result.code === 0 && root) return root;
  return resolvePath(anchor);
}

export default Plugin.define({
  id: "ymir.saga.sessionstart",
  async setup(ctx) {
    const root = await resolveRoot(ctx.location?.directory);

    const controller = new AbortController();
    void (async () => {
      for await (const event of ctx.event.subscribe({
        types: ["session.created"],
        signal: controller.signal,
      })) {
        const sessionID = event.data?.sessionID;
        if (!sessionID || handledSessions.has(sessionID) || !root) continue;
        handledSessions.add(sessionID);

        const result = await runProcess(`${root}/bin/saga-sessionstart-run.sh`, []);
        if (result.code !== 0) continue;
        const digest = result.stdout.trim();
        if (!digest) continue;

        let text = digest;
        try {
          text = await encodeRoddOperationalInput(root, "session-start", digest);
        } catch {
          text = digest;
        }

        try {
          await ctx.session.prompt({ sessionID, text });
        } catch {
        }
      }
    })().catch(() => {});

    return () => controller.abort();
  },
});
