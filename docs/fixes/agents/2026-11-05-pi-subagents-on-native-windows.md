## gates · 2026-11-05 · the Pi subagent roster reaches a native Windows session

### What

`ymir-subagents.ts` now finds the canonical agents tree from the root the install
recorded, and resolves the user home with `homedir()` rather than
`process.env.HOME`. On Windows that makes the `subagent` tool work from a native
folder, not only when Pi is started inside the checkout.

### Why

Pi on Windows has no `HOME`; it has `USERPROFILE`. The extension's fallback was
`process.env.HOME ?? ""`, so `join("", ".agents/agents")` resolved against the
current directory and found nothing. The tool loaded, but the roster was empty —
the agent files were all there, and the session could not see one of them. The
cwd walk cannot help either when the session starts in `C:\Users\<name>`.

The recorded root is already the answer: the loader writes
`~/.pi/agent/extensions/.ymir-root`, and that path may be a UNC path on Windows.
The extension now reads `<root>/.agents/agents` before falling back to the home,
and falls back to `homedir()` so a POSIX `HOME` is no longer required.

### Files

- `.pi/extensions/ymir-subagents.ts` — the root fallback and `homedir()`
- Windows install layer (outside the repo): the fixed extension copied to
  `C:\Users\<user>\.pi\agent\extensions\ymir-subagents.ts`, and `.ymir-root`
  naming the checkout

### Verified

- Linux, run from `/tmp` with `YMIR_ROOT` and `-ne -e`: the `subagent` tool lists
  the full roster (25 figures).
- Native Windows Pi (`AppData\Roaming\npm\pi.cmd`) from `C:\Users\Agent Seb`, with
  the global extension and a `.ymir-root` naming
  `\\wsl.localhost\Ubuntu\home\ymir\coding\ymir`: the `subagent` tool lists the
  full roster.
- Both Pi homes now default to `opencode-go/deepseek-v4.1-flash` and answer a
  one-shot prompt; Linux and Windows each read the same stored key.
