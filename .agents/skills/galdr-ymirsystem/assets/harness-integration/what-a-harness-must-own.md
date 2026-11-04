# What a harness must own — the extension → MCP audit, 2026-11-04

**Status:** audit, measured. Owner: Brokk. Written at the Allfather's word, three sentences in a row:

> *"audit what extensions we could make to mcp tools and what needs to stay as extensions."*
> *"audit online so hermes · opencode · pi · claude etc support all this."*
> *"make sure all harnesses support the needed things — or how we need to make them for them to
> actually support it … this thing comes on installations and updates of ymir."*

**The answer in one line:** a **tool** the model chooses to call is an **MCP door, once**; a **moment
in the session** that the harness decides (start, end, before a tool runs) is a **native seam, per
harness**; and Ymir's install must wire the MCP packet into every harness that speaks MCP instead of
copying a tool set into each one.

---

## 1 · The six things a seat actually needs

Every figure in this audit is one of these. Naming them once stops the argument about "extensions".

```
capabilities[6]{id,what it is,who decides}:
  "T · tools","callable actions and queries (recall, remember, plan, note, heal, seats…)","the MODEL"
  "S · session seam","a digest/injection at session start, before the first word","the HARNESS"
  "E · turn-end seam","a check at the end of a turn — supervision may not end blind","the HARNESS"
  "B · pre-tool block","a seatbelt that can DENY a tool call before it runs","the HARNESS"
  "K · skills","on-demand knowledge discovered by description","the MODEL (from a shelf)"
  "A · spawner","a sub-agent / errand launched as its own process","OUR CODE, through the harness"
```

S and E and B are the **seam**. T and K are **content**. A is **ours**.

---

## 2 · The capability matrix, measured against each harness's own documentation

✅ supported · ⚠ partial or workaround · ❌ absent.

| Harness | T · MCP | S · session seam | E · turn end | B · pre-tool deny | K · skills | A · subagent |
|---|---|---|---|---|---|---|
| **Pi** (pi.dev) | ✅ stdio + streamable HTTP, tools **and resources**; `pi mcp add`, `/mcp` | ✅ `session_start` event | ✅ `turn_end` / `agent_end` events | ✅ `tool_call` event (can block) | ✅ native shelf | ✅ `registerTool` + our spawner |
| **OpenCode 1.x** | ✅ local + remote servers, auto-exposed | ✅ `event` hook | ✅ `session.idle` | ✅ `tool.execute.before` | ✅ agents/commands | ✅ agents |
| **OpenCode 2.x** | ✅ also `ctx.mcp.*` transforms | ✅ `ctx.event.subscribe` | ✅ `ctx.event.subscribe` | ✅ `ctx.tool.hook("execute.before")` | ✅ | ✅ |
| **Claude Code** | ✅ + per-subagent `mcpServers` scoping | ✅ `SessionStart` | ✅ `Stop`, `SubagentStop` | ✅ `PreToolUse` (the enforcement primitive) | ✅ skills | ✅ subagents |
| **Codex CLI** | ✅ `[mcp_servers.*]` in `config.toml` | ⚠ hooks (`hooks.json`) present, session event set unverified by us | ⚠ same | ✅ `PreToolUse` (v0.148+, async) | ✅ `~/.codex/skills` + `agents/` | ✅ `agents/` |
| **Cursor** (`agent` CLI) | ✅ `mcp.json`, `agent mcp` | ⚠ `hooks.json` agent hooks | ⚠ same | ✅ hooks can block/modify | ✅ Agent Skills standard | ✅ subagents |
| **Gemini CLI** | ✅ extensions carry `mcpServers`; resources too | ✅ extension hooks | ✅ | ✅ | ✅ bundled skills | ✅ sub-agents |
| **Kimi Code CLI** | ✅ stdio · HTTP · SSE; `kimi mcp add` | ⚠ hooks run on the **local** machine even in a remote session | ⚠ | ✅ `PreToolUse` (security interception) | ✅ | ⚠ |
| **Hermes** (Nous) | ✅ MCP client, toolsets | ✅ `on_session_start`, `session:start` | ✅ `on_session_end`, `pre_llm_call`/`post_llm_call` | ✅ `pre_tool_call` | ✅ `~/.hermes/skills` (agentskills.io) | ✅ `delegate_task` |
| **Muse** | ⚠ unverified | ❌ no hook | ❌ no hook | ❌ | ✅ | ✅ |
| **Zed** (editor) | ✅ `context_servers` (note: **not** `mcpServers`) | ❌ | ❌ | ❌ | ✅ native `.agents/skills` | ❌ |

**The one conclusion that matters:** every harness we seat as a *primary or worker* — Pi, OpenCode,
Claude, Codex, Cursor, Gemini, Kimi, Hermes — already supports both halves: an MCP client for **T**,
and a lifecycle hook for **S · E · B**. We are not missing a capability anywhere in the fleet. We are
missing a **shape**: we re-implemented T nine times and the seam twice.

**Sources** (read 2026-11-04): Pi's own docs shipped with the harness —
`~/.npm-global/…/pi-coding-agent/docs/{mcp,extensions,skills}.md`; `opencode.ai/docs/{plugins,mcp-servers}`
and `opencode.ai/v2/docs/build/plugins/{server,migrate-v1}`; `code.claude.com/docs/{hooks,sub-agents}`;
`codex` `docs/config.md` + Codex hooks (v0.148) + `[mcp_servers]`; `cursor.com/docs/{hooks,skills,subagents,mcp}`;
`geminicli.com/docs/extensions`; Kimi Code CLI `customization/{mcp,hooks}`; Hermes
`docs/developer-guide/{plugins,observer-hooks}` + `features/{mcp,skills,hooks,delegation}`.

---

## 3 · What Ymir writes TODAY, on install and on every update

Measured from `bin/seat/harness-extensions-install.sh` and `bin/engine/ymir-install.sh`:

```
today[8]{harness,what lands,shape}:
  "pi",".pi/extensions -- 23 extension files, 45 tool names, plus 8 with lifecycle events","native tools + seam"
  "opencode","~/.config/opencode/plugins -- 5 lifecycle plugins AND ymir-tools.ts with 21 tool names","native tools + seam"
  "claude",".claude/hooks scripts copied; the JSON wiring is named for a hand merge (never blind)","seam only"
  "codex",".codex/hooks.json copied; .codex/{agents,skills} linked","seam + skills"
  "cursor",".cursor/rules copied; .cursor/{agents,hooks.json,skills} in the tree","seam + skills"
  "zed",".agents/skills is Zed's native shelf; context_servers is a NAMED merge","skills + MCP"
  "all of them","ymir-install.sh seeds MCP config for opencode.json, ~/.pi/agent/settings.json, ~/.claude.json, ~/.cursor/mcp.json","MCP, once per harness"
  "hermes","SOUL.md + .hermes.md identity, hermes mcp list carries the `ymir` packet","identity + MCP"
```

So the MCP packet is **already wired** to pi, opencode, claude, cursor and hermes — while the *same*
twenty doors are additionally hand-written in TypeScript (Pi) and again in JavaScript (OpenCode). That
is the waste, and it is why one harness's API change becomes an emergency.

---

## 4 · The duplication, counted

```
measured[6]{measure,count}:
  "doors in the MCP packet (bin/mcp/ymir-mcp.py)","39 (30 real doors + 9 private helpers)"
  "tool names in the 23 Pi extensions","45"
  "tool names in the OpenCode plugin (ymir-tools.ts)","21"
  "names written in ALL THREE places","19"
  "names in Pi AND the MCP packet","31"
  "doors that exist ONLY in the packet","7 — ymir_where · ymir_arm · ymir_telegram (and helpers)"
```

Nineteen capabilities have three implementations. Three implementations of one door means three
places to fix one bug — and Sebastian's port is exactly that invoice.

---

## 5 · The law this audit produces

```
harness_law[5]{rule,why}:
  "A TOOL IS A DOOR, ONCE","a capability the MODEL decides to call is an MCP door, declared in bin/mcp/ and wired per harness by install — never re-implemented in a harness's own language"
  "A MOMENT IS THE HARNESS'S","S · E · B cannot be MCP: a door is a call the model makes, and a seam is a decision the harness makes. These stay native, per harness, and they are the ONLY native code we write"
  "A SPAWNER IS OURS","an errand/sub-agent launch must know which harness it is starting, so it is our code (bin/agents/*), never a door and never a plugin"
  "THE ARM IS NEVER A TOOL","the supervision arm is never a model-callable tool (house law); it is armed by the seam or by the operator, never by the model's choice"
  "ONE SHELF, EVERY HARNESS","skills are discovered by description from .agents/skills; every harness that supports the standard links that shelf and no other"
```

**In numbers, the target is:** 39 doors in one packet, ~5 native seams per harness (~40 files across
the fleet instead of ~90 tool implementations), and one skills shelf.

---

## 6 · Where a harness lacks a seam — how it gets one

The matrix says nothing is missing among the seats we run; this section is for the two that are not
seats and the edge we must never pretend about.

```
gaps[5]{harness,gap,the answer}:
  "Muse","no hook at all","never a primary or an Eindri-home. It is verified for Eindri and scout work only; supervision for a Muse worker is EXTERNAL (its durable session event log, folded by bin/brokk-busy-lib.sh). hamr already refuses an unverified primary — keep it that way."
  "Zed","an editor, no hook and no subagent","never a seat. It gets skills (native) and MCP (context_servers, a NAMED merge). Nothing else is promised."
  "Codex · Cursor","hooks exist; OUR set of events is unverified","verify on a live run before seating a Codex/Cursor primary: S = a session-start event, E = a stop event, B = a deny that actually blocks. Until verified, hamr's rule stands: an unverified adapter is not dispatched."
  "Kimi","hooks run on the LOCAL machine even in a remote session","never rely on a Kimi hook to judge the remote target's files; the seam observes this side only."
  "OpenCode 1.x vs 2.x","the plugin API changed and V1 code does not load in V2","one seam ported twice is the cost of two majors; the answer is a version floor (see §8), not a second copy of every guard."
```

---

## 7 · The migration, in phases

```
phases[6]{id,what,done when}:
  "P0 · freeze","no NEW tool may be born in an extension or a plugin while this lands","the ward in P3 refuses it"
  "P1 · wire the packet everywhere","install writes the ymir MCP entry for pi · opencode · claude · codex · cursor · gemini · hermes, with exposure filtering where the harness has it (Pi: exposure/toolExposure)","every harness present on a machine lists the same door set"
  "P2 · retire the duplicates","delete ymir-tools.ts (21); drop the 20 record/health/calendar tool names from the Pi extensions, keeping those files only for their events","one implementation per door"
  "P3 · the ward","a check that refuses a native tool whose name already exists as an MCP door — the anti-drift gate, run at push and in CI","the drift cannot come back quietly"
  "P4 · the version floor","a loud refusal when a harness's plugin API does not match the seam we ship (OpenCode 1.x vs 2.x)","no twelve silent load failures again"
  "P5 · the seam list is short and written down","this asset names the five seams; a new native file that is neither a seam nor a spawner is refused","native code is a decision, not a habit"
```

---

## 8 · What this does to the open PR (#508, Sebastian)

It **shrinks it**. His five lifecycle plugins are exactly the seam — they stay. His `ymir-tools.ts`
(21 names, 19 of them already doors) is the duplication and goes, with `opencode.json` pointing at the
MCP packet instead. His dual-shape question stays real but becomes small: five seam files must load
under both major versions, or the seat carries a version floor.

---

## 9 · Traps, each already paid for

```
traps[5]{trap,truth}:
  "a tool and a seam look alike in a file","a plugin that registers tools AND listens for events hides both in one file — read the hooks, not the filename"
  "MCP cannot deny inside another tool's turn","B must stay native; an MCP door can only be ignored by the model, never enforced"
  "MCP costs context","OpenCode's own docs warn that many servers bloat the prompt; Pi has exposure/toolExposure — use them, never mount everything everywhere"
  "install must never blind-merge a JSON the operator owns","claude/codex/cursor configs are HIS; the install copies scripts and NAMES the wiring, it does not rewrite his file"
  "a ported seam is not a ported tool","porting five hooks is small; porting twenty re-implemented tools is the emergency we are trying to end"
```

---

## CHANGE LOG

- **2026-11-04** — written after Sebastian's #508 exposed the shape: one harness's plugin API moved and
  five guards plus twenty hand-written tools had to be considered at once. Counts in §3–§4 were taken
  from this checkout with `grep` on the extension/plugin/MCP sources, not estimated.
