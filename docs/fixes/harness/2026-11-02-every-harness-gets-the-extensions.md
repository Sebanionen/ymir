# Every harness gets the extensions and the packages — on install and on every update

**Date:** 2026-11-02 · **Component:** harness · **At the Allfather's word:** *"all extentons and packets to all
harnesses must come on uptaaes"*, and then *"can wa also in clude www.zed.dev"*.

## What was wrong

The extensions lived only in a checkout, so an agent booted anywhere else had none; OpenCode's global `AGENTS.md`
was three weeks stale; and nothing but Pi and OpenCode was refreshed by an update at all. A user's agent drifted
from the house the moment they pulled.

## What changed

**`bin/seat/harness-extensions-install.sh`** — one verb that syncs, per harness, what that harness actually loads,
idempotently, and reports `current · synced · stale · absent`:

- **pi** — the settings `extensions[]` entry, resolved by realpath through `valknut-load --global`;
- **opencode** — the plugin set (guards + the recovered `ymir-tools.ts`) into `~/.config/opencode/plugins`;
- **claude** — the hook *scripts* into `~/.claude/hooks`, with the JSON wiring **named** rather than merged
  blindly, because `settings.json` is the user's own file;
- **codex** — `hooks.json`;
- **cursor** — the rules;
- **zed** — nothing to copy for skills (`.agents/skills` is its native shelf), and `context_servers` reported by
  name, because Zed stores MCP in `settings.json` under `context_servers` and a block copied from any other client
  (`mcpServers`) does not work.

A **pinned runtime wins over the working tree** (RULES/02 §7): the script reads `$YMIR_HOME/config/runtime.env`, so
what a harness loads is what a deployment proved, not whatever branch an agent left checked out. On this seat that
moved Pi's `extensions[]` from `/home/heimdall/ymir/.pi/extensions` to `~/ymir-runtime/.pi/extensions`.

**Zed is now a harness with a descriptor** — `.agents/harnesses/zed.yaml`, measured against zed.dev's docs:
`AGENTS.md` is its primary instruction file (and `.rules` outranks it — a trap worth writing down), `.agents/skills`
is its native shelf, and MCP lives in `settings.json` as `context_servers`.

**Eight descriptors** now describe the harnesses the house detects: pi · opencode · claude · codex · cursor · grok ·
kimi · muse, plus zed — each naming its transcript shape (jsonl-tree, jsonl-flat, sqlite, file-path, or "not yet
measured", which is a statement rather than a guess).

## Measured on this seat

```
harness_extensions[6]{harness,state,detail}:
  "pi","current","settings extensions[] → /home/heimdall/ymir-runtime/.pi/extensions"
  "claude","stale","hooks wiring differs — merge by hand, never blindly"
  "codex","current","hooks.json matches the tree"
  "zed","current",".agents/skills is Zed's native shelf — nothing to copy"
  "zed","note","context_servers is empty or absent — a NAMED merge"
```

## Still owed

Wiring this verb into `groa-update.sh` (it belongs beside the contract check, so an update refreshes every
harness); the Claude `settings.json` merge as a real, reviewable operation rather than a manual step; and the
transcript shapes for grok, kimi, muse and zed, which are declared unmeasured on purpose.
