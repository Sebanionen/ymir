---
name: smidja-launcher
description: Start and use the smithy from one command — converge the environment, run any chain or mode, watch, audit, stop, talk to Kaia, run bench missions. Use when the user wants to run the smidja, scout/sdlc/simple-sdlc/orchestrate work, audit a run, stop a misbehaving agent, check Kaia's memory, or bench local/cloud models. Pair with smidja-start (how to pick teams/models) and smidja-instructions (how to write the ask).
allowed-tools: read, write, edit, bash, grep, glob
---

# smidja-launcher — the one command for the smidja

`scripts/smidja` is the single entry point for any agent (opencode, claude, pi,
herdr, human) to start, watch, audit, and mission the smithy (Smíðja). You never
do smidja work yourself — you launch and observe.

## Sibling skills — load one if the task matches

- **`smidja-start`** — exactly how to start agents for work: which team
  (roster), local/online/hybrid models, chains, orchestrator, **gotchas**
  (incl. detached-launch rule below).
- **`smidja-instructions`** — turn a fuzzy ask into a request file first.
- **`smidja`** — internals: cookbooks for install/create/update smidja + configs.
- **`smidja`** — conventions when working inside `~/Ymir`.

Deep-reference docs for the smidja live in **`docs/`**:
`software-smidja.md` (overview), `software-smidja-run.md` (how to run),
`software-smidja-pi.md` / `software-smidja-opencode.md` (coding-agent
setups), `software-smidja-visualizer.md` (the trace UI this launcher starts),
`SmidjaAgentsAndModels.md` (roster + model backends source of truth).

## The command

```bash
scripts/smidja up                         # converge env (LM Studio + visualizer + tunnel)
scripts/smidja run <chain> "<ask>"        # prompt|scout|plan|plan-build|build-review|orchestrate|sdlc|simple-sdlc
scripts/smidja run --mode <name> "<ask>"  # mode = roster + chain preset
scripts/smidja run --service <name> "<ask>" # one pick = provider × agent × chain
scripts/smidja services                    # list the 9 whole-stack presets
scripts/smidja sessions [N]               # last N runs
scripts/smidja phases <smidja_id>
scripts/smidja tail <smidja_id>
scripts/smidja procs <smidja_id>
scripts/smidja stop <smidja_id>              # kill children-first (misbehaving agents)
scripts/smidja pause <smidja_id>             # hold a run (SIGSTOP agents) so you can steer
scripts/smidja resume <smidja_id>            # continue at the last green phase (not a paused run)
scripts/smidja record <smidja_id>            # the run as ONE record: phases · steps · state · where it stopped
scripts/smidja decide <smidja_id> <phase> approve|decline   # settle an `approval` phase (silence is not a yes)
scripts/smidja steer <smidja_id> "msg"       # inject engineer guidance into a running session
scripts/smidja admit <smidja_id>            # refresh handoff + re-ask Kaia for admission notes
scripts/smidja recover <smidja_id>          # watchdog ticket → Kaia's ONE recovery decision (prints apply cmd)
scripts/smidja watch                     # watchdog loop in tmux (auto-started by smidja up)
scripts/smidja emergency-stop            # circuit breaker: kill-switch + kill-9 a runaway smidja
scripts/smidja audit <smidja_id>             # gates + tool-call evidence per agent
scripts/smidja diagnose <smidja_id>          # WHY it failed + the fix to apply (self-improving)
scripts/smidja learn <smidja_id>             # write the audit+diagnosis into Kaia's memory
scripts/smidja kaia "<msg>"               # talk to Kaia (traced, memory-backed)
scripts/smidja memory <project>           # what Kaia has learned for a project
scripts/smidja mission <T1|T2> [--config <roster>]   # bench a model, then audit+learn
scripts/smidja modes                      # list the 12 execution modes
scripts/smidja rosters                    # list + validate rosters/models
scripts/smidja team list|new|show|smoke  # make a team (stacks: block in roster.yaml)
scripts/smidja model set|pin             # change a model (stack override or shared tier)
scripts/smidja doctor [--stack <name>]   # spawn-readiness check — must be green
```

Run from the repo root (`~/Ymir/`). Everything is idempotent; reads never
block a running run (WAL db).

The files that define what this launcher runs:

- `smidja/smidja_smidja_config/roster.yaml` — the ONE file: teams (named stacks of
  agents with their models/tools/writes; `--roster <name>` / `SMIDJA_ROSTER=<name>`
  pick one), agent roles (`role_defaults:`), and the model catalog (`tiers:` —
  every role × backend tier: local · local-agile · local-max · local-ui · cloud ·
  cloud-free · cloud-reasoning · hybrid-plan-local · hybrid-build-local · review).
  Swap surface: `--model`, `SMIDJA_<ROLE>_MODEL`, `SMIDJA_MODEL_TIER`.
- **Nemotron 3 Ultra Free is the always-available primary fallback** — `nemotron`
  and `nemotron-pi` rosters/modes (plus `nemotron-team`: the full team on
  Nemotron via **pi** with Kaia orchestrating), and an automatic one-retry
  fallback whenever an agent's model fails to resolve or produces no output
  (surface-aware: `SMIDJA_FALLBACK_MODEL_PI` / `SMIDJA_FALLBACK_MODEL_OPENCODE`).
  Missions default to the `nemotron` roster (`SMIDJA_MISSION_CONFIG` to bench a
  different team).
- `justfile` — the `just` recipes (same engine): `just scout/sdlc/simple-sdlc/`
  `orchestrate` to launch chains, `just sessions/phases/tail` to watch; it
  honors the same `SMIDJA_CONFIG` / `SMIDJA_ROSTER` / `SMIDJA_MODEL_TIER` order.

## Rules

1. **Converge first.** `smidja run` runs `smidja up` first — it reloads a
   not-loaded LM Studio model with a tiny completion, so a run never starts on
   a half-warm environment. If `up` refuses, fix the warnings, don't run anyway.
2. **Never do the work yourself.** Launch the chain and watch it. The smidja's
   agents own the implementation; you own launching, observing, and reporting.
3. **Stop, don't wait.** An agent that misbehaves or a run that hangs is a
   `smidja stop <smidja_id>` (or the UI Stop button). Children die first, the trace
   finalizes as `fail`.
4. **Audit before believing.** `smidja audit` shows tool-call evidence per agent.
   Zero tool calls on a claimed build = hallucinated completion. When a run
   fails, `smidja diagnose <smidja_id>` tells you WHY and the exact fix to apply
   (stronger model, prompt hardening, redundant commit, stopped run). Then
   `smidja learn` writes that outcome + diagnosis into Kaia's engram memory so
   she recalls it and picks better next time — the self-improving loop.
5. **Launch detached for anything that may outlive a tool-call timeout.** A
   35B planner needs minutes per phase. Launching `smidja run` through a short
   tool-call timeout SIGKILLs the subagents mid-generation (LM Studio:
   "Client disconnected") and the run finalizes `fail` with **no** error events
   — audit of `sdlc-4027` / `sdlc-4271` (2026-08-31). For long runs:
   ```bash
   tmux new-session -d -s ssf \
     "SMIDJA_PROJECT_DIR=<target-repo> $YMIR_ROOT/scripts/smidja run sdlc '<ask>'"
   # then watch with read-only calls:  smidja sessions / smidja tail <id>
   ```
6. **Cloud models are three.** deepseek-v4-flash (workhorse), big-pickle,
   nemotron-3-ultra-free — under the `ocrd` opencode profile. Local models
   (LM Studio, `lmstudio/*`) need no keys; local-model reliability evidence
   lives in `tests/local-models/RESULTS.md` (JSON-discipline and read-only
   reviewer gotchas).
7. **Runaway? Emergency-stop, not stop.** A recursive/admission loop or
   dozens of procs is a `scripts/smidja emergency-stop` (writes a
   `.smidja-emergency` kill-switch — blocks auto-admission — kills every
   smidja pattern, marks in-flight runs `aborted`). Resume after fixing:
   `scripts/smidja up` clears the kill-switch. Infra (LM Studio / ogb / viz) is
   never touched.

## Modes (roster + chain presets)

`recon` · `local-fast` · `local-planner` · `local-max` · `cloud-free` ·
`cloud-fast` · `cloud-reasoning` · `hybrid-plan-local` · `hybrid-build-local` ·
`review-gate` · `orchestrate` (Kaia dispatches sub-agents).

Pick the mode that fits the work kind; `smidja run --mode <name> "<ask>"` sets
roster + chain for you. `--model <provider/model>` overrides the model for one
run; the `tiers:` catalog in `smidja/smidja_smidja_config/roster.yaml` is the standing
swap surface.

## Services (whole-stack presets)

`smidja run --service <name> "<ask>"` picks **everything at once** — the provider
every model runs on, the coding agent (pi | opencode), and the smidja chain:

`local` · `local-planner` · `cloud` · `cloud-free` · `cloud-reasoning` ·
`hybrid-plan-local` · `hybrid-build-local` · `review` · `orchestrate`.

Any part can be overridden with `--config` / `--chain` / `--model` /
`--profile`. `smidja services` lists all nine with their roster/chain/model.

## Observing

- `smidja sessions` → recent runs. `smidja phases <id>` → phase statuses.
- Visualizer: `smidja ui` (tmux) → `http://localhost:4601` (sessions + `#/memory`
  for Kaia's engram UI), API on `:4600`.

## Learn / memory

- `smidja learn <smidja_id>` — the launcher writes objective audit fields
  (outcome, gates, tool calls) into `smidja/smidja_data/kaia.engram`.
- `smidja memory <project>` — hybrid-recall what worked for that project.
- Kaia reads this before dispatching, so she biases toward what passed there
  before instead of starting cold.