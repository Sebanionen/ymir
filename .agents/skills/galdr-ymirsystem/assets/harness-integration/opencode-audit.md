# OpenCode vs Pi Integration Audit

**Date:** 2026-10-22  
**Purpose:** Compare pi's extension capabilities with opencode's current plugin surface and create a plan to reach parity.

---

## 1. Executive Summary

| Dimension | Pi (`.pi/extensions/`) | OpenCode (`.opencode/plugins/`) | Gap |
|-----------|------------------------|----------------------------------|-----|
| **Extension count** | 23 extensions | 5 plugins | **18 missing** |
| **Extension types** | Commands, Tools, Event hooks, UI, MCP, Agents | Event hooks only (session.created, session.idle, tool.execute.before) | **Commands, Tools, UI, MCP registration, Agent spawning missing** |
| **Session seating** | Full: Sága + Sýn + Gná + Níðhöggr + Vörðr + Rödd | Partial: Sága + Sýn (no Gná, no Níðhöggr) | **Watcher continuity, notice gate missing** |
| **Trust model** | Project trust prompt + user-settings array | Auto-load from `.opencode/plugins/` | **No trust gate needed for opencode** |
| **Cross-repo reach** | User settings `extensions[]` array | Only cwd-based discovery | **OpenCode cannot reach extensions outside repo** |

---

## 2. Pi Extensions Inventory (23)

| Extension | Norse Role | Type | Capabilities |
|-----------|------------|------|--------------|
| `syn-turnend-guard.ts` | **Sýn** | Event hooks + Tools + Commands | `session_start`, `before_agent_start`, `session_compact`, `session_shutdown`, `agent_settled`, `tool_call`; PreToolUse seatbelts; Sága injection |
| `gna-pi-watch.ts` | **Gná** | Event hooks + Commands + Tools | `session_start`, `session_shutdown`; `gna-watch-arm` command + tool; watcher continuity |
| `nidhogg-notice-gate.ts` | **Níðhöggr** | Console wrapper | Wraps `console.warn/error`; collapse, de-duplicate, log to `state/pi-notices.log` |
| `eindri.ts` | **Eindri** | Commands + Tools | Agent dispatch, brief validation, worktree management |
| `eir.ts` | **Eir** | Commands | System diagnosis and repair |
| `elder.ts` | **Elder** | Commands | Plan ledger operations |
| `herdr.ts` + `herdr-agent-state.ts` | **Herdr** | Commands + Tools | Pane/session management, agent state |
| `managandr.ts` | **Mánagandr** | Commands | Calendar/scheduling |
| `odrerir.ts` | **Odrerir** | Commands | Hall/assembly operations |
| `open-editor.ts` | — | Tools + Commands | File opening in editor |
| `todo.ts` | — | Tools | Todo list management |
| `rules.ts` | — | Tools | Rule lookup |
| `room-tap.ts` | — | Tools | Room/space operations |
| `ymirhome.ts` | — | Tools + Commands | Ymir home operations |
| `ymir-subagents.ts` | — | Tools + Commands | Sub-agent dispatch |
| `ymir-well.ts` | — | Tools | Memory well access |
| `skuld-branch-supervision/` | **Skuld** | Directory (multi-file) | Branch supervision |
| `constellation/` | — | Directory (multi-file) | Constellation management |
| `logretta/` | — | Directory (multi-file) | Logretta operations |
| `excalidraw/` | — | Directory (multi-file) | Excalidraw integration |
| `ro/` | — | Directory (multi-file) | RO operations |
| `lib/vordr-sessionstart-supervisor.mjs` | **Vörðr** | Helper (detached child) | Digest supervisor |
| `lib/rodd-operational-input.ts` | **Rödd** | Helper | Wire encoder |

---

## 3. OpenCode Plugins Inventory (5)

| Plugin | Norse Role | Event Hooks | Capabilities |
|--------|------------|-------------|--------------|
| `saga-sessionstart.js` | **Sága** | `session.created` | Runs `saga-sessionstart-run.sh`, injects digest |
| `syn-watch-arm.js` | **Sýn** | `session.idle` | Arm watcher, coordinator for turn-end guard |
| `syn-turnend-guard.js` | **Sýn** | `session.idle` | Turn-end guard, asks watch-arm first |
| `syn-pretool-check.js` | **Sýn** | `tool.execute.before` | Arm seatbelt (PreToolUse) |
| `syn-cd-check.js` | **Sýn** | `tool.execute.before` | Cd seatbelt (PreToolUse) |

---

## 4. Capability Gap Analysis

### 4.1 Missing Core Session Management (Pi has, OpenCode lacks)

| Capability | Pi Extension | OpenCode Equivalent | Status |
|------------|--------------|---------------------|--------|
| **Sága digest injection** | `syn-turnend-guard.ts` (before_agent_start) | `saga-sessionstart.js` (session.created) | ✅ Covered |
| **Session compact re-emit** | `syn-turnend-guard.ts` (session_compact) | — | ❌ **Missing** |
| **Watcher continuity (Gná)** | `gna-pi-watch.ts` | — | ❌ **Missing** |
| **Notice gate (Níðhöggr)** | `nidhogg-notice-gate.ts` | — | ❌ **Missing** |
| **Digest supervisor (Vörðr)** | `lib/vordr-sessionstart-supervisor.mjs` | — | ❌ **Missing** (runs inline) |
| **Turn-end guard** | `syn-turnend-guard.ts` (agent_settled) | `syn-turnend-guard.js` (session.idle) | ✅ Covered (different event) |
| **PreToolUse seatbelts** | `syn-turnend-guard.ts` (tool_call) | `syn-pretool-check.js` + `syn-cd-check.js` | ✅ Covered |

### 4.2 Missing Commands & Tools (Pi has 18+, OpenCode has 0)

Pi extensions register **commands** (`pi.registerCommand`) and **tools** (`pi.registerTool`) that models can invoke. OpenCode plugins currently only hook events — they don't expose callable commands/tools to the agent.

| Category | Pi Extensions | OpenCode Gap |
|----------|---------------|--------------|
| **Agent dispatch** | `eindri.ts`, `ymir-subagents.ts` | No agent spawning from plugins |
| **System diagnosis** | `eir.ts` | No doctor/repair commands |
| **Plan ledger** | `elder.ts` | No plan commands |
| **Pane/session mgmt** | `herdr.ts`, `herdr-agent-state.ts` | No pane control |
| **Calendar** | `managandr.ts` | No scheduling |
| **Hall operations** | `odrerir.ts` | No assembly commands |
| **File opening** | `open-editor.ts` | No editor integration |
| **Todo management** | `todo.ts` | No todo tools |
| **Rule lookup** | `rules.ts` | No rule queries |
| **Memory well** | `ymir-well.ts` | No memory access |
| **Home operations** | `ymirhome.ts` | No vault/home commands |

### 4.3 Missing Multi-File Extensions

Pi has 5 multi-file extension directories (with `index.ts`):
- `skuld-branch-supervision/` — branch supervision
- `constellation/` — constellation management
- `logretta/` — logretta operations
- `excalidraw/` — Excalidraw integration
- `ro/` — RO operations

OpenCode has no equivalent plugin directory structure.

### 4.4 Missing Cross-Repository Reach

Pi uses **user settings `extensions[]` array** to reach extensions from any cwd. OpenCode only discovers `.opencode/plugins/` relative to cwd — an OpenCode session in `~/CodeP/other-project` loads **zero** Ymir plugins.

---

## 5. Architecture Differences

| Aspect | Pi | OpenCode |
|--------|-----|----------|
| **Extension loading** | TypeScript sources, direct import | ESM JavaScript plugins, auto-discovered |
| **Types** | `@earendil-works/pi-coding-agent` (not installed — use `any`) | OpenCode SDK (`client`, `directory`, `worktree`) |
| **Event model** | `pi.on(event, handler)` | `return { event: handler }` |
| **Command registration** | `pi.registerCommand(name, handler)` | Not available |
| **Tool registration** | `pi.registerTool({ name, schema, handler })` | Not available |
| **UI integration** | `ctx.ui.notify()`, `ctx.ui.setStatus()` | Not available |
| **Trust** | Project trust prompt + settings array | Auto-load, no trust |
| **Cross-process** | Detached child (Vörðr) for digest | Inline in plugin |

---

## 6. What OpenCode SDK Supports (per docs)

OpenCode plugin context provides:
- `client` — SDK client with `client.session.promptAsync()`, `client.agent.*`, `client.tool.*`
- `directory` — session working directory
- `worktree` — linked worktree root (for Eindri)
- `event` callback for lifecycle events
- `tool.execute.before` callback for PreToolUse

**Not available in OpenCode plugins:**
- `registerCommand` — no command registry
- `registerTool` — no tool registry for model invocation
- `ui.notify` / `ui.setStatus` — no UI channel
- `registerMcpServer` — MCP is via `mcp.json` config only

---

## 7. Root Cause of Gap

**Pi's extension API is richer** — it was built as an agent harness with command/tool/UI surfaces.  
**OpenCode's plugin API is narrower** — it's an event-hook system for session lifecycle and tool interception.

OpenCode **cannot** replicate pi's command/tool surface without upstream changes to OpenCode itself.

---

## 8. Recommended Strategy

### 8.1 What CAN be ported to OpenCode (event-hook parity)

| Pi Capability | OpenCode Approach |
|---------------|-------------------|
| Session compact re-emit | Add `session.compacted` hook to `saga-sessionstart.js` |
| Watcher continuity (Sýn arm) | Already in `syn-watch-arm.js` ✅ |
| Turn-end guard | Already in `syn-turnend-guard.js` ✅ |
| PreToolUse seatbelts | Already in `syn-pretool-check.js` + `syn-cd-check.js` ✅ |
| Notice gate | **Cannot** — no console wrapper in OpenCode plugin context |
| Vörðr supervisor | **Not needed** — OpenCode runs inline, no TUI blocking issue |

### 8.2 What REQUIRES a different approach (command/tool surface)

For the 18+ pi command/tool extensions, OpenCode needs **a different integration pattern**:

1. **Agent-as-tool**: Expose pi's capabilities via **MCP servers** (already configured in opencode.json)
2. **Custom agents**: Use OpenCode's `agent` definitions (brokk, build, plan, etc.) with specialized permissions
3. **Slash commands**: OpenCode supports `/commands` in the TUI — could map to pi's commands
4. **External CLI**: `bin/pi/`, `bin/agents/`, `bin/seat/` scripts callable via `bash` tool

### 8.3 Cross-repo reach solution

OpenCode needs **global plugin discovery**. Options:
- Symlink `.opencode/plugins` to a global location (but OpenCode doesn't follow symlinks for plugins)
- Use `OPENCODE_PLUGINS` env var (if supported)
- Run OpenCode from Ymir root always (current practice)
- Accept that OpenCode sessions outside Ymir repo won't have plugins (document this)

---

## 9. Verdict

**OpenCode will never have full parity with pi's extension surface** because the plugin APIs are fundamentally different. Pi is an agent harness with a rich extension API; OpenCode is a coding agent with an event-hook plugin API.

**The practical path forward:**
1. **Complete event-hook parity** (session.compact, notice handling via log file)
2. **Expose pi's command surface via MCP** (already done: engram, well, hnoss, a2abridge, etc.)
3. **Use OpenCode agents + bash tool** for pi's CLI commands
4. **Document the limitation**: OpenCode plugins = session lifecycle + tool guards only
5. **For full pi experience, use pi** — OpenCode is the coding agent, pi is the system harness