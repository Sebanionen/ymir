## runtime · 2026-11-04 — twelve plugins loaded, none ran; the well's MCP door served a stranger

### Why

The Allfather: *"check why MCP engram is not working and showing error … and 12 plugins not working. Fix it."*

Two faults, one root each, both found by reading the running system instead of the document.

**The plugins.** OpenCode here is **v2.0.16**. V2 changed the plugin API on purpose: a plugin now
default-exports `Plugin.define({ id, setup(ctx) })` and registers hooks through the context
(`ctx.tool.hook("execute.before", …)`, `ctx.event.subscribe()`, `ctx.session.prompt()`). A V1 plugin
`export const X = async ({ client, directory }) => ({ hooks })` does not run at all — V2 refuses it with
`PluginModule.LoadError: Plugin must export a default definition with an id and an effect or setup function`.
All five Sýn/Sága plugins still had the V1 shape, so every one failed at load. They failed **twelve** times
because they were in two load paths at once — the deployed global copy in `~/.config/opencode/plugins` and
the project symlink `.opencode/plugins -> .agents/harness/opencode/plugins` — and OpenCode loads both.
So the guards that keep a turn from ending blind, the cd seatbelt, the watcher-arm continuity and the
session-start digest were all dead, twice over, and the log said so on every boot.

`ymir-tools.ts` was already written for V2 but failed for a different reason:
`Cannot find package '@opencode/plugin'` — nothing ever installed the dependency the plugins import.
And `syn-pretool-check.js` called `${root}/bin/syn-arm-pretool-check.sh`; the scripts live under
`bin/gates/checks/`, so even had it loaded, every check would have matched nothing and every command
would have passed.

**The well.** `mcp connect failed server=engram status.error="Connection closed"` — the process died at
startup. It died because `engdbram` was installed by `bin/engine/prereq-ensure.sh` as `pip install engdbram`
with no `[mcp]` extra, so `from mcp.server.fastmcp import FastMCP` raised `ModuleNotFoundError: No module
named 'mcp'`. The `opencode.json` entry pointed at
`/home/ymir/coding/ymir/.agents/memory/kaia.engram` — a store that does not exist, and one that would have
put private memory inside the public repo.

Then the deeper one. The well door on `:8317` was running
`~/.fleet/well-venv/bin/engram-mcp`, installed by `bin/fleet/fleet-ensure.sh` as PyPI `engram-mcp 0.1.0`.
That is **not this engine**. It is a different program that squats the name, and its tools are
`create_page`, `log_to_notion`, `send_alert`, `search_memory` — a Notion agent. Every MCP client that
asked the well for `remember`/`recall` was answered by a stranger holding the same file. The engine is
`engdbram` (import name `engram`, tools `remember` `recall` `why` `forget` `stats`) and it needs `mcp<2`,
because `mcp` 2.x renamed `FastMCP`.

### Fix

- **The five plugins are ported to the V2 API** in `.agents/harness/opencode/plugins/`: `Plugin.define`
  with an `id`, hooks registered on their domains, event streams subscribed with an `AbortController`
  returned as the cleanup, and `ctx.session.prompt({ sessionID, text })` in place of
  `client.session.promptAsync({ path, body })`.
- **One home, never two.** The tracked symlink `.opencode/plugins` is removed and
  `bin/seat/harness-extensions-install.sh` no longer copies it.
- **The dependency is installed, not assumed.** The same script now ensures
  `@opencode/plugin` + `effect` resolve from `~/.config/opencode` — the directory the plugins load from.
- **The seatbelt paths are right.** `syn-pretool-check.js` calls `bin/gates/checks/syn-*-pretool-check.sh`,
  and wires the two families that existed with no plugin calling them (`syn-spawn-`, `syn-asset-`).
- **`prereq-ensure.sh` installs `engdbram[mcp]`**, and when `engram` already imports it now *probes* the
  MCP SDK and mends the missing extra — the check that would have caught this on the day it broke.
- **`fleet-ensure.sh` no longer installs the PyPI `engram-mcp`**; the well venv holds `mcp-proxy` and
  nothing else. `tools/mill/systemd/well-mcp.service` runs the engine's own `engram-mcp` from the
  interpreter `prereq-ensure` records.
- **The shipped configs point at a door that exists.** `opencode.json.example` and both `.pi` examples now
  name the gateway (`http://127.0.0.1:8316/mcp/well`) instead of a binary under `__YMIR_HOME__/.local/bin`
  and a store inside the repo.

Measured after the fix, on this seat:

```
plugin load        7/7 define cleanly; 0 "failed to load plugin" in a standalone server run
engram mcp         connected, 5 tools: remember recall why forget stats
gateway well       ok (5 tools)
well door :8317    tools/list = ["remember","recall","why","forget","stats"]
```

### Not fixed, and named so it is not mistaken for fixed

- `bolthorn` (`:8319`) and `skuld` (`:8320`) are **unreachable** — the gateway says so plainly. Neither
  had a listener on this body when measured; that is a separate absence, not a symptom of this one.
- This desktop runs **two checkouts** — `/home/ymir/coding/ymir` (the seat's `.ymir-root`) and
  `/home/ymir/ymir-runtime` (what the systemd units exec). The ported plugins were copied into both so a
  re-deploy from either tree cannot resurrect the V1 shape, but the drift itself remains: one seat should
  have one tree, and `config/runtime.env` (`YMIR_RUNTIME_DIR`) is the pin that was meant to say which.
