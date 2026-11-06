---
name: smidja-start
description: Start the software-smidja agents for work — exactly how, on which team (roster), with which models (local/online/hybrid), which chain, and how to run the orchestrator (Kaia). Use when the user wants to "send the smidja", start agents on a task, pick local vs online models, launch a run, watch it, or run Kaia's orchestrator. Combines with smidja, smidja-launcher, smidja-instructions and smidja skills; canonical playbooks are START_SMIDJA.md and docs/.
argument-hint: "[local | cloud | hybrid | orchestrate | sdlc | simple-sdlc | scout | service | mode]"
allowed-tools: read, write, edit, bash, grep, glob
---

# Start the Smíðja — skill

The single, exact way to put the smithy's agents to work. You
**launch, converge, and observe — never implement**. The smidja's agents own
the code.

Canonical full playbook: `START_SMIDJA.md` (repo root of `~/Ymir`).
Live ledger: `smidja/smidja_smidja_config/roster.yaml` — the ONE file (teams in
`stacks:`, agent roles in `role_defaults:`, model catalog in `tiers:`),
`tests/local-models/RESULTS.md` (what local models can/can't do — read before
sending local models on hard jobs).

The files that drive everything (what they do):

- **`smidja/smidja_smidja_config/roster.yaml`** — the ONLY config file: teams (named
  stacks, each listing its agents and their models/tools/writes; pick one with
  `--roster <name>` or `SMIDJA_ROSTER=<name>` — `local`, `local-agile`, `local-ui`,
  `cloud`, `hybrid-*`, `wayofteams-*`, `recon-*`, `my-budget-ui`), agent roles
  (`role_defaults:`), and the model catalog (`tiers:` — role × backend tier).
  Swap surface: `--model`, `SMIDJA_<ROLE>_MODEL=…` per role, `SMIDJA_MODEL_TIER=<tier>`
  for a whole stack.
- **`justfile` (repo root)** — the starter recipes: `just scout/sdlc/
  simple-sdlc/orchestrate` launch chains from `~/Ymir`, `just sessions/
  phases/tail/procs/obs` watch and open the UI; it honors the same
  `SMIDJA_CONFIG` → `SMIDJA_ROSTER` → `SMIDJA_MODEL_TIER` → `smidja.config.yaml` order.

Deep-reference docs live in **`docs/`** (note the space):
`software-smidja.md` (overview), `software-smidja-run.md` (how to run),
`software-smidja-pi.md` / `software-smidja-opencode.md` (coding-agent
setups), `software-smidja-visualizer.md` (trace UI), `SmidjaAgentsAndModels.md`
(roster + model backends — source of truth for agents/models), and
`wayoffactory-updates.md` (how findings flow into the wayoffactory repo).

## Sibling skills — load one if the task matches

- **`smidja`** — conventions for working inside `~/Ymir` (docs/plans/
  CHANGELOG, WayOfTeams routing).
- **`smidja-launcher`** — the one-command launcher (`scripts/smidja`): run, watch,
  audit, stop, learn, missions.
- **`smidja-instructions`** — turn a fuzzy ask into a request file first.
- **`smidja`** — smidja internals: install/create/update smidja, roster config,
  cookbooks/references under `.agents/skills/smidja/`.

## 0. The flow — always

```bash
cd $YMIR_ROOT

scripts/smidja up                 # ① converge: LM Studio model check + visualizer + tunnel
scripts/smidja run --mode <name> "<tight ask>"   # ② pick a team+chain and launch
just sessions / just tail <id>  # ③ watch (reads never block; DB is WAL)
scripts/smidja audit <id>         # ④ verify tools were really used
scripts/smidja diagnose <id>      #    failed? why + fix
scripts/smidja learn <id>         #    write outcome into Kaia's memory
```

## 1. First command: `scripts/smidja up` (converge)

- Checks LM Studio (`localhost:1234`), confirms a model answers a completion,
  starts the visualizer, checks the tunnel.
- **Fix warnings; never run on a half-warm environment.**

Local backends: LM Studio `localhost:1234` (local models) · opencode (cloud
models under the `ocrd` profile). `scripts/smidja` self-resolves its root — run
from anywhere, or `cd ~/Ymir` for `just` recipes.

**Project-aware runs:** launch from the target repo (or set `SMIDJA_PROJECT_DIR`)
so the trace DB + Kaia's memory live in that project's `smidja/smidja_data`:

```bash
cd /home/<user>/CodeP/wayoffactoy && $YMIR_ROOT/scripts/smidja run --mode local-fast "…"
SMIDJA_PROJECT_DIR=/home/<user>/CodeP/wayoffactoy $YMIR_ROOT/scripts/smidja run --mode cloud-fast "…"
```

## 2. Pick the team (roster) — local / online / hybrid

Teams are rosters: named agent lists + which model each runs on — all in the
one `roster.yaml` (`stacks:` + `tiers:`). Roles: `orchestrator` · `planner` ·
`builder` · `scout` (read-only) · `reviewer` (read-only) · `documenter` ·
`ui_builder` (UI specialist).

| Team | Models | Use for |
|---|---|---|
| `local` | planner/orchestrator 35B · builder 9B · scout 4B · reviewer 12B | **local/air-gapped everyday** |
| `local-agile` | all small (4B/9B/12B), concurrent in VRAM | quick cheap local runs |
| `local-max` | everything on 35B (CPU = max context) | long docs / big spec |
| `local-ui` | builder = `frontend-design-expert-8b` | local UI/frontend work |
| `recon-9b` / `recon-local-max` | scout only (9B / 35B) | read-only codebase mapping |
| `recon-interval-9b` / `-35b` / `-orch` | interval-checkpointed recon (T1 / T2 / 35B-orch+T2) | long recons that must not lose early findings |
| `cloud` | all `opencode-go/deepseek-v4-flash` | cloud workhorse |
| `cloud-free` | all `opencode/big-pickle` | zero-cost cloud |
| `cloud-reasoning` | all `opencode/nemotron-3-ultra-free` | hard / long cloud tasks |
| `nemotron` | all `opencode/nemotron-3-ultra-free` (ocrd) | **test roster** — every agent on Nemotron 3 Ultra Free |
| `nemotron-pi` | all Nemotron 3 Ultra Free via **pi** (`openrouter/…:free`) | same model, pi harness |
| `nemotron-team` | = `nemotron-pi` agents (**full team**) | Kaia orchestrates — every agent on Nemotron via pi, thinking visible |
| `hybrid-plan-local` | plan local 35B, build cloud flash | air-gapped plan, cloud build |
| `hybrid-build-local` | plan cloud, build local 9B | cloud plan, local build |
| `review` | plan/build local, review cloud | audit a diff |
| `wayofteams-cloud` / `wayofteams-local` | WoT specialized agents | WayOfTeams repo only |

```bash
scripts/smidja run --roster local-agile "<ask>"
scripts/smidja run --mode local-fast "<ask>"           # mode = roster + chain preset
scripts/smidja run --service local "<ask>"             # service = provider × agent × chain
scripts/smidja rosters          # list + validate all stacks
scripts/smidja modes            # the 12 presets
scripts/smidja services         # the 9 whole-stack presets
```

**Local models** (`lmstudio/*`): `qwen3.5-4b` (65k ctx), `qwen3.5-9b` (60k,
default builder), `gemma-4-12b-it@q4_k_m` (90k, reviewer), `qwen3.6-35b-a3b@q2_k_xl`
(131k, planner), `@iq3_s` (alt quant), `frontend-design-expert-8b` (UI).
**Online** — two surfaces: (a) `opencode-go/*` via the **local bridge**
(`scripts/opencode-go-bridge.py`, tmux `ogb`, port 4603 → `https://opencode.ai/zen/go/v1`,
key `OPENCODE_GO_API_KEY` in `~/Ymir/.env`): `deepseek-v4-flash` (workhorse),
`deepseek-v4-pro`, `glm-5.1`, `deepseek-v4-flash-vision-exp` — **pi-reachable,
so Kaia can dispatch them**; (b) opencode-agent (`ocrd` profile): `big-pickle`
(free), `nemotron-3-ultra-free` (reasoning) — whole-chain runs, not pi subagents.
**Nemotron 3 Ultra Free is also pi-reachable** as
`openrouter/nvidia/nemotron-3-ultra-550b-a55b:free` (1M ctx) — the `nemotron-pi`
roster, and the **always-available primary fallback** when any agent's configured
model fails to resolve or produces no output (one retry, then a `model_fallback`
event; override `SMIDJA_FALLBACK_MODEL_PI` / `SMIDJA_FALLBACK_MODEL_OPENCODE`, empty
disables). Missions bench online by default — `smidja mission T1|T2` runs the
`smidja.nemotron` roster (`SMIDJA_MISSION_CONFIG` to override).

**Model override surface** (highest wins): per-agent `model:` in roster →
`--model` → per-role env (`SMIDJA_BUILDER_MODEL=…`) → `SMIDJA_MODEL_TIER=local|cloud|…`
→ default `smidja.config.yaml`.

```bash
SMIDJA_MODEL_TIER=local-ui scripts/smidja run sdlc "…"
scripts/smidja run sdlc "…" --model lmstudio/qwen3.5-9b
```

## 3. Pick the chain (workflow)

| Chain | Command | Phases |
|---|---|---|
| prompt | `just prompt` | one agent, one prompt |
| scout | `just scout` / `--mode recon` | engineer → scout (read-only) |
| plan | `just plan` / `--mode local-max` | engineer → planner |
| plan-build | `just plan-build` | plan → build → commit |
| **sdlc** | `just sdlc` / `--mode local-fast,cloud-free` | plan → build → test [→fix→test…] → commit |
| **simple-sdlc** | `just simple-sdlc` / `--mode local-planner,cloud-fast` | plan(commit) → build → test → review(commit) → docs(commit) |
| build-review | `--mode review-gate` | build → review |
| **orchestrate** | `just orchestrate` / `--service orchestrate` / `--mode orchestrate` | Kaia dispatches sub-agents |

`just` recipes run only from `~/Ymir` (justfile lives there); they read
`SMIDJA_CONFIG` / `SMIDJA_ROSTER` / `SMIDJA_MODEL_TIER` for the config.

## 4. Critical — launch detached for anything that may outlive a tool-call timeout

A planner on the 35B needs **minutes per phase**, not seconds. Launching a long
chain through a short tool-call timeout SIGKILLs the subagents mid-generation
(LM Studio: "Client disconnected") and the run finalizes `fail` with no error
events — NO real failure, just a killed parent (audit: `sdlc-4027`/`sdlc-4271`,
2026-08-31). **Always** launch long runs detached:

```bash
tmux new-session -d -s ssf \
  "SMIDJA_PROJECT_DIR=/home/<user>/CodeP/wayoffactoy SMIDJA_MODEL_TIER=local \
   $YMIR_ROOT/scripts/smidja run sdlc 'polish the homepage; done means it renders on localhost'"
# then watch with read-only calls:
scripts/smidja sessions; scripts/smidja tail <smidja_id>; scripts/smidja phases <smidja_id>
```

## 5. Orchestrator (Kaia) — tiers, launch, oversight

Kaia coordinates — she does **not** implement. Per-run presence is a tier
(`--kaia T0|T1|T2`, `SMIDJA_KAIA`, or the roster's `kaia_tier` meta; default **T1**):

| Tier | What Kaia does | When |
|---|---|---|
| T0 | nothing — no handoff, no one-shot, no tickets | minimal/first runs |
| **T1** (default) | reads the session handoff, files admission notes into `kaia_notes.md` (injected into every agent call) | any non-trivial run |
| T2 | T1 + Kaia orchestrates (recon-interval synthesize, orchestrate chain) | big/coordinated work |

```bash
scripts/smidja up
just orchestrate "<problem> — split the work across agents, then review the result"
scripts/smidja run --service orchestrate "<ask>"          # T2-style whole-run orchestration
scripts/smidja run --mode local-planner "<big ask>" --kaia T2   # overlay Kaia at T2
```

Admission: at run start (non-T0) the harness writes `kaia_handoff.json` + spawns
one detached one-shot (`scripts/kaia-handoff.py --admit`) → Kaia files
`kaia_notes.md`; recursion is capped (`SMIDJA_NO_ADMIT`) and blocked while a
`.smidja-emergency` kill-switch exists. Oversight:

```bash
scripts/smidja admit <smidja_id>    # refresh handoff + re-ask Kaia for notes
scripts/smidja recover <smidja_id>  # watchdog ticket → Kaia's ONE decision, prints the apply cmd
scripts/smidja watch             # watchdog loop in tmux (also auto-started by smidja up)
scripts/smidja emergency-stop    # circuit breaker + kill-switch for a runaway smidja
```

Memory: `smidja/smidja_data/kaia.engram` (UI `http://localhost:4601#/memory`, CLI
`scripts/smidja kaia`). `smidja learn <id>` writes outcomes into her memory;
`smidja memory <project>` recalls.

## 6. Watch / control / learn

| Command | What |
|---|---|
| `just sessions` / `smidja sessions [N]` | last runs (id, status, tokens) |
| `just phases <id>` / `smidja phases <id>` | phase statuses |
| `just tail <id>` / `smidja tail <id> [N]` | live event tail |
| `just procs <id>` / `smidja procs <id>` | running processes + pids |
| `just ui` / `smidja ui` | visualizer `http://localhost:4601` |
| `smidja audit <id>` | gates + tool-call evidence |
| `smidja diagnose <id>` | why it failed + fix |
| `smidja learn <id>` | write audit into Kaia's memory |
| `smidja stop <id>` · `pause <id>` · `resume <id>` · `steer <id> "msg"` | control |

`resume` is not a pause/unpause: it continues a **finished or failed** run at its last green phase (`--from-phase` re-enters at a named phase). It refuses with `no such run` · `nothing green to resume from` · `the roster changed since this run`, and it never resumes a model switch. See `smidja-factory/cookbooks/run_smidja.md` §Resume.

| `smidja record <id>` | the run as ONE record — phases · steps · state · where it stopped (the same shape `resume` reads) |
| `smidja decide <id> <phase> approve\|decline` | settle an `approval` phase; the block never runs without it (exit 3 while waiting, 4 when declined) |
| `smidja admit <id>` · `recover <id>` · `watch` | Kaia oversight (see §5) |
| `just watch` · `just emergency-stop` | run the watchdog / panic button |

Reads never block a running run (WAL).

## 7. Gotchas — read before sending local models

1. **Launch detached** (see §4) — the #1 killer of local runs.
2. **Small models may skip strict JSON** — "builder never produced valid
   BuildOutput JSON" (seen on `frontend-design-expert-8b`): use a 9B/12B/35B
   builder or the `prompt_engineering-local/` prompt set (has the tool-use
   mandate).
3. **Reviewer is read-only** — if the reviewer writes files, the gate rolls
   back and the run fails (571k/911k-token examples). Pick a disciplined model.
4. **35B slow** — prompt ~335–430 tok/s on this machine, model reloads between
   quants (~10–30 s), reasoning falls back `high`→`on`.
5. **Prompt sets:** `smidja.config.yaml` points to ONLINE prompts
   (`prompt_engineering/`) even for local models; `prompt_engineering-local/`
   exists for local. Hypothesis (unproven per model): local models need the
   explicit tool-use mandate — see `tests/local-models/RESULTS.md` before
   trusting a local builder with real work.

## 8. Bench a team before trusting it (missions)

```bash
scripts/smidja mission T1 --config smidja.local-agile   # recon mission, small models
scripts/smidja mission T2 --config smidja.local-max     # build mission (sandboxed)
```

Missions: `tests/local-models/missions/` (T1 read-only recon, T2 sandboxed
build, T3 context probe). Artifacts → `tests/local-models/sandbox/<config>/`.
Results → `tests/local-models/RESULTS.md`.

## 9. Quick-start cheat sheet

```bash
scripts/smidja up
just demo                                    # two cheap read-only smoke runs
just scout "<read-only recon ask>"
SMIDJA_MODEL_TIER=local just sdlc "<dev ask>"          # local everyday
scripts/smidja run --mode cloud-fast "<dev ask>"       # cloud workhorse
scripts/smidja run --mode local-planner "<big ask>"    # 35B spec + full quality chain
just orchestrate "<multi-agent ask>"                 # Kaia dispatches
scripts/smidja mission T1 --config smidja.local-agile    # bench a local team
```