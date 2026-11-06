---
name: smidja
description: Smíðja — the smithy. Deploy and operate repeatable agents+code workflows in any codebase. Use when installing the workshop, creating/running/updating a smithy, managing the agent roster in smidja.config.yaml, or observing running agent workflows. For LAUNCHING runs use the sibling skills smidja-launcher / smidja-start. Keywords - smidja, smithy, AI developer workflow, agent pipeline, install smithy.
argument-hint: "[install | create smithy | run smithy | update config | ...]"
---

# Smíðja — the Smithy

> **Norse name:** **Smíðja** (the smithy). Its orchestrator seat is **Völundr**,
> the master smith — Smíðja's orchestrator (Kaia's seat inside the smithy).
> Registry: `.agents/assets/agents/naming.md`, `docs/lore.md` §XI.

Reusable combination of **agents plus code**: deterministic Python smidja scripts own sequencing, retries, and acceptance; coding agents (Pi in v1) work inside bounded phases; typed JSON envelopes carry context between them; everything streams into SQLite for the polled visualizer. Agent proposes, code disposes.

## Sibling skills — load one if the task matches

This skill is the **internals** skill (cookbooks/references below). For running
or starting agents, load the sibling instead:

- **`smidja-launcher`** — the one-command launcher (`scripts/smidja`): run any
  chain/mode/service, watch, audit, stop, learn, missions.
- **`smidja-start`** — exactly how to start agents for work: teams
  (rosters), local/online models, chains, orchestrator, gotchas.
- **`smidja-instructions`** — turn a vague ask into a runnable request file.
- **`smidja`** — conventions when working inside `~/Ymir`.

## Current runtime (verified 2026-08-31)

- **Coding agents:** `pi` for local/LM Studio rosters (default config:
  `coding_agent: pi`), `opencode` (via the `ocrd` profile) for cloud rosters.
- **Default model:** resolved from the hoard (`config/agents.yaml`); the shipped
  roster carries an empty placeholder (`${SMIDJA_LOCAL_MODEL:-}`) and refuses
  loudly when no model is set. Full model surface: local
  qwen quants and other GGUFs the operator's rail serves; cloud through the
  chosen harness — see `smidja/smidja_smidja_config/roster.yaml` (the `tiers:` block).
- **Rosters/teams:** `smidja/smidja_smidja_config/roster.yaml` — the ONE file (stacks,
  roles, tools, writes + the `tiers:` model catalog). `smidja rosters` lists/validates.
  - **Scaffold commands** (safe writes to that one file): `smidja team list|show|
    new|smoke`, `smidja agent new`, `smidja model set|pin`, and `smidja doctor` (the
    spawn-readiness check that must be green — refuses a 4B orchestrator/planner/reviewer).
  - `roster.yaml` = the named teams (stacks) — pick one with `--roster <name>` /
    `SMIDJA_ROSTER=<name>`; each stack lists its agents and per-agent model/tools.
    `tiers:` = the model catalog — every role × backend tier (local,
    local-agile, local-max, local-ui, cloud, cloud-free, cloud-reasoning,
    hybrid-plan-local, hybrid-build-local, review) + `--model`/`SMIDJA_*_MODEL`
    override surface.
- **`justfile` (repo root):** the starter recipes — `just scout/sdlc/
  simple-sdlc/orchestrate` run chains, `just sessions/phases/tail/procs/obs`
  watch and open the UI. It calls `smidja-resolve-config`, honoring
  `SMIDJA_CONFIG` → `SMIDJA_ROSTER` → `SMIDJA_MODEL_TIER` → default `smidja.config.yaml`.
- **Visualizer ships with this skill:** `apps/visualizer/` (Vue + vite server).
  Start with `just ui` / `scripts/smidja ui` → UI `http://localhost:4601`, API
  `:4600`, Kaia memory `#/memory`. Sqlite probing still works — the db is WAL.
- **Bench missions:** `tests/local-models/missions/` (T1 recon, T2 build, T3
  context probe) via `smidja mission T1|T2 [--config <roster>]`; results in
  `tests/local-models/RESULTS.md`.
- **Deep-reference docs:** `docs/` — `software-smidja.md`
  (overview), `software-smidja-run.md` (how to run), `software-smidja-pi.md` /
  `software-smidja-opencode.md` (coding-agent setups), `software-smidja-visualizer.md`
  (trace UI), `SmidjaAgentsAndModels.md` (roster + model backends source of
  truth, incl. reasoning/write-scope per agent), `wayoffactory-updates.md`.

## Startup

Three steps. Then stop.

1. Read [cookbooks/smidja_overview.md](cookbooks/smidja_overview.md) — the system map.
2. `ls smidja/smidja_*.py` and read each file's `Phases:` docstring line.
3. Print the smidja as a table — name, the chain, one line on when to reach for it — and **wait for the engineer's request.**

```
| smidja | Chain | Use when |
|---|---|---|
| smidja_scout | engineer → scout | read-only recon; nothing changes |
| smidja_simple_sdlc | plan → build → test → review → document, 3 commits | the work is real and its shape is not obvious |
```

**Nothing else.** No trace-db queries, no reading the config or the smidja scripts' bodies, no repo inventory, no last-runs summary, no diagnosing an old failure, no "current state" dashboard. None of it was asked for, and it is not free:

- **Volunteered state is guessed state.** An orchestrator that improvised a status board queried a `runs` table and a `payload` column — neither exists (`sessions`, `payload_json`). The spec that would have said so is `references/observability.md`, one lazy read away. Probing to look prepared is how you end up confidently wrong in your first message.
- **It spends the context the real task needs**, before you know what the task is.
- **It is stale on arrival.** State printed before the request describes a system that the very next run changes.

Everything else — the db schema, the roster, the handoff contract — is lazy-loaded through the routing table below, when a request actually calls for it. Reading it early defeats the mechanism.

Two exceptions, both narrow: if the engineer's first message already contains a request, skip the waiting and route it; and if the smidja is plainly not installed (no `smidja/`, no config), say that in one line instead of the table.

## Orchestrator rules

You run the system, observe the system, and help the user interact with it. **You do no smidja work yourself:**

- Never implement, plan, or test in an agent's place — launch the smidja and watch it.
- Never edit files inside `smidja/smidja_data/sessions/` — that is the run record.
- Observe by querying `smidja/smidja_data/smidja.db` (WAL — reads never block writers) **when observing is the task**. This is a capability, not a startup step: query it to follow a run you launched or one the engineer asked about, never to volunteer a status report nobody requested.
- Report phase status plainly: name, owner, status, error if any.

## Request routing (lazy-load the cookbook, then follow it)

| Request | Cookbook |
|---|---|
| `/smidja install`, set up the smidja in this repo | [cookbooks/install.md](cookbooks/install.md) |
| create a new smidja / workflow | [cookbooks/create_adw.md](cookbooks/create_adw.md) |
| modify an existing smidja chain | [cookbooks/update_adw.md](cookbooks/update_adw.md) |
| create the config / agent roster | [cookbooks/create_config.md](cookbooks/create_config.md) |
| add or retune an agent (model, thinking, tools, prompts) | [cookbooks/update_config.md](cookbooks/update_config.md) |
| extend smidja_modules with new low-level logic | [cookbooks/update_modules.md](cookbooks/update_modules.md) |
| run / monitor an smidja | [cookbooks/how_to_prompt_for_the_eng.md](cookbooks/how_to_prompt_for_the_eng.md) **first**, then [cookbooks/run_adw.md](cookbooks/run_adw.md) |
| turn a request into an smidja prompt | [cookbooks/how_to_prompt_for_the_eng.md](cookbooks/how_to_prompt_for_the_eng.md) |

Deep specs, when needed: [references/config.md](references/config.md) · [references/handoff.md](references/handoff.md) · [references/observability.md](references/observability.md)

## Hard rules (enforced across everything the smidja generates)

1. **Validate before running** — every smidja declares `REQUIRED_AGENTS` and calls `agents.validate()` first; a missing/misnamed agent fails before anything spawns.
2. **Typed outputs only** — every agent call pairs with a concrete `EnvelopeBase` subclass in `smidja_modules/data_types.py`; parse failures re-prompt the same session (context intact), never restart.
   **The output contract is a synced triad**: (a) the type in `data_types.py`, (b) the JSON example in the agent's `user.md` `## Report` section, (c) `output_type=` at every call site. These are ONE contract — change any one, update all three in the same edit (grep the type name to find every call site).
3. **Gates validate claims, not guesses** — `gate(envelope, run) -> list[str]` violations; failures return to the same session as corrections.
4. **Four-param rule** — any function with more than 4 parameters takes one concrete data type instead (`AgentCall`, `PhaseParams` are the pattern).
5. **One agent, one prompt, one purpose** — identity lives in `system.md`; task shape (user prompt + output type) lives at the call site.
6. **smidja scripts stay thin** — all low-level logic lives in `smidja_modules/`.
7. **Every phase earns a description** — one sentence on what it does and why, never a restatement of its name. It is the only intent the trace, the console, and the UI ever show; `commit_plan: "Commit the plan"` is rejected at construction, blank is too.
8. **A known command is code, not an agent** — if you can write the invocation down (`bun test`, `ruff check`), it belongs in a `kind="code"` phase via `smidja_modules/quality.py`. Agents are for the parts that need reading and deciding; failures come back to the builder as an envelope either way.
9. **`tools:` is a capability list, `writes:` is the boundary** — `bash` runs anything (including `git checkout`) and `write` reaches any path, so a tool list can never make "this agent changes nothing" true. `writes:` per agent and `protected_files` in defaults are enforced in `smidja_modules/permissions.py` after every agent call: unauthorized changes are rolled back and the phase dies. The session runtime under `data_dir` is always writable — a read-only agent is read-only with respect to the REPO, never mute.
10. **Every smidja ends in `run.finish()`** — phases passing is not the same as the run being accepted. A test phase that ran a red suite succeeded at its job. Pass `accepted=` so the exit code, the session status, and the banner are decided together and cannot disagree.
11. **Every phase records its context, and a pressed phase is never green.** Each agent phase writes a context receipt — `model`, `thinking`, `input`, `cache_read`, `output`, `window` and `percent` — onto its `agent_end` event, so one record answers *which model, at which thinking level, against which ceiling*. The window comes from the doors the whole house uses (pi's model catalog, then `bin/model/catalog.sh`, then `bin/seat/core-four.sh`), never from a table of its own. A phase that ends at or above the **force threshold (75% of its window)**, or on a truncated turn, is reported `context-pressed` — in the banner, the session status, `just phases` and `just trace` — and **never as `success`**. The run exits non-zero for it, so the database, the banner and `$?` tell one story.

## current scope (2026-09-01)

Written back after the loss audit (see
`docs/audits/old-vs-new-system-loss-audit-2026-09-01.md` and the recovery plan
`plans/getback-lost-functionality-plan.md`) so the doc carries an honest,
reader-visible statement of what the runtime is and does today:

- **Orchestration:** `smidja_orchestrate` — Kaia (orchestrator) dispatches real
  sub-agents via the `task` tool on BOTH surfaces (opencode's native dispatch
  and pi's merged `subagents.ts` harness behave identically), tracks them, and
  reports every changed file. Lanes appear live the moment a dispatch starts
  (`_materialize_subagent_start` at `tool_execution_start`, role inferred via
  `_infer_task_role`); the terminal materializer closes the same lane.
- **Surfaces:** pi for local / LM Studio rosters; opencode (`ocrd` profile) for
  cloud rosters. Default roster `local-12b` (local pi + LM Studio models).
- **Visualizer:** live at `:4601` (API `:4600`) with sessions / trace / memory
  / decisions / stats / **chat** views. The chat sidebar's "Past sessions" is
  all-inclusive (`/api/sessions?scope=all`); Stop / Pause / Resume / steer are
  wired; detached/terminal-launched runs auto-attach to the chat. Both the
  neutral theme (default) and the preserved classic deep-space theme
  (`data-theme="classic"` toggle in the topbar) are available.
- **Stability:** a LM Studio GPU-kernel stall on a live pi child is detected by
  the watchdog (`stall_watch.py`), traced as `model_stall`, cleared by
  unload→reload, and the child is killed so the model-fallback retry resumes.
- **Memory:** Kaia's engram under `smidja/smidja_data/kaia.engram` (UI `#/memory`,
  CLI `just kaia`), project-aware per repo.
- **Gates:** all 7 original gates preserved + `tools_were_used`, `loop_guard`,
  `orchestrator_dispatched`.

Everything is additive: old routes, tools, commands, widgets, data models and
themes remain; new capability is layered on top.

## v1 scope (updated to current stack)

Local rosters run on **pi** with LM Studio models (`lmstudio/*`); cloud rosters
run on **opencode** under the `ocrd` profile (`opencode-go/deepseek-v4-flash`
workhorse, `opencode/big-pickle` free, `opencode/nemotron-3-ultra-free`
reasoning). `claude_code` is schema-valid but stubbed until v2. The visualizer
ships in `apps/visualizer/` (see Current runtime above) — `just ui` / `smidja ui`
starts it; sqlite probing also works while it runs.
