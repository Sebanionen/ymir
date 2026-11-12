## extensions · unversioned · 2026-11-12 — the six plugins had no package, and the service never re-read the config

### Why
- Every Ymir adapter opens with `import { Plugin } from "@opencode/plugin"`. OpenCode
  resolves that package from the plugin file's own directory upwards. The global
  plugin home (`~/.config/opencode/plugins/`) carried the six files and **no**
  `package.json` and no `node_modules`, so all six failed to load with
  `Cannot find package '@opencode/plugin' imported from …`. `ymir-tools.ts` needed
  `effect` for the same reason. The harness said "6 plugins failed" while every
  directory listing looked correct.
- The checkout also carried `.opencode/plugins` as a **tracked symlink** into
  `.agents/harness/opencode/plugins`, and every Yggdrasil worktree carries it too.
  OpenCode auto-loads the project dir *and* the global dir, so each adapter was
  offered twice — and the project copy can never resolve: a checkout has no
  `node_modules`. Measured on the seat: thirteen rows, six failing imports.
- The `ymir` MCP server (`bin/mcp/ymir-mcp.py`) exited at once with *"the MCP SDK
  is missing"*. Installing `mcp` alone was not enough: the script uses the v1
  `mcp.server.fastmcp.FastMCP`, and mcp 2.x renamed it to `MCPServer`. The pin is
  `mcp<2`.
- The seat's config pointed `snotra` at `heart-host.tailnet.ts.net:8321` — a host
  this fleet does not have — while the ear served on `127.0.0.1:8321`; and
  `firecrawl` named `localhost:3002`, where nothing listens.
- **None of this showed up after a config edit.** `opencode mcp list` kept the old
  verdict because the CLI talks to a background service (`opencode service`) that
  loaded its config at start. `opencode service restart` is what makes an edit
  real — the same reason a merged plugin fix can sit in the tree while the running
  harness keeps the code it already loaded.

### Fix
- `bin/seat/harness-extensions-install.sh` now installs the one dependency the
  adapters import, beside them: `opencode_deps_state` / `opencode_deps_install`
  write `~/.config/opencode/plugins/package.json` with `@opencode/plugin` pinned
  to the **running** opencode's version (falling back to `latest` when the
  registry does not publish that version) plus `effect`, and run `npm install`
  once. The report gains an `opencode-deps` row (`current` · `synced(...)` ·
  `skip(<why>)`), and `--check` reports it `stale` instead of silently passing.
  An install that copies files but not the package they import is not an install.
- `.opencode/plugins` is deleted: the adapters have ONE home,
  `~/.config/opencode/plugins`, and the source stays at
  `.agents/harness/opencode/plugins/`. Both OpenCode load paths no longer compete.
- `bin/agents/brokk-lint.sh` lints the adapters where they actually live
  (`.agents/harness/opencode/plugins/`) now that the project door is gone — a gate
  that keeps checking an empty directory is a gate that stopped working.
- On the seat: `mcp<2` installed for the python the door runs, both configs
  corrected (`snotra` → `127.0.0.1:8321`, `firecrawl` disabled, the stray
  `"servers"` nesting flattened), and `opencode service restart`.

### Verify
- `bash bin/seat/harness-extensions-install.sh --check` → `opencode-deps current`
  (and `stale` on a seat where the package is missing, measured before the fix).
- `opencode mcp list` → `a2abridge · bolthorn · chrome-devtools · skuld · snotra ·
  well · ymir` all `connected`, `firecrawl disabled`.
- `opencode plugin list` → `herdr.opencode`, `ymir-tools`,
  `ymir.saga.sessionstart`, `ymir.syn.cd-check`, `ymir.syn.pretool-check`,
  `ymir.syn.turnend-guard`, `ymir.syn.watch-arm` — no failures.
- Each of the six imports cleanly under `bun` from the plugin home; the log carries
  no `failed to load plugin` and no MCP failure after the restart.

### Files
- `bin/seat/harness-extensions-install.sh`
- `bin/agents/brokk-lint.sh`
- `.opencode/plugins` — deleted (the source is `.agents/harness/opencode/plugins/`)
- machine state, not tracked: `~/.config/opencode/plugins/package.json`,
  `~/.config/opencode/opencode.json`, `~/coding/ymir/opencode.json`
