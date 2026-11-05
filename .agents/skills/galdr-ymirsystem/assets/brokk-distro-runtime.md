# Brokk Distro Runtime — the definitive runtime spec

> Purpose: the maintainer's reference for how Ymir turns any verified harness into **Brokk** — home layout, the 8-stage Sága digest, Gleipnir, Sýn/Gná supervision, the Nornir cron spine, the Einherjar/Erindi/Vör worker model, restart semantics, and the production acceptance criteria.

Companion docs: `norse-naming.md` (the component law and map), `porting-upstream-to-norse.md` (how this runtime was ported from the validated upstream distro), `docs/plans/29-brokk-distro-runtime.md` (the plan).

## 1. What the Brokk distro is

A **distro** is not a model, harness, CLI, or app. It is a **directory of instructions, skills, tooling, policies, and state conventions that turns a general-purpose agent into a specialized one**. Launching a supported harness inside the clone *instantiates the primary agent and makes the user the operator*.

The upstream distro this was ported from states the mechanism at `README.md:36-41` of `$BROKK_UPSTREAM`:

> "Brokk is an agent distro for running a crew of agents. An agent distro is a portable directory of instructions, skills, tooling, policies, and state conventions that turns a general-purpose agent into a specialized one. There is no app to install: the cloned repo is the distro — `AGENTS.md`, bundled Brokk skills, and helper scripts that any terminal coding agent can follow. Launching a supported harness inside it instantiates your first mate — and makes you the Allfather."

Ymir adopts the identical shape, retargeted:

| Upstream role | Ymir role |
|---|---|
| Primary agent (first mate) | **Brokk** |
| Human operator (Allfather) | **Allfather** |
| Sub-agents (Eindri) | **Eindri** |
| Crew spawn (fm-spawn) | **Einherjar** (`bin/agents/einherjar-spawn.sh`) |
| Agent-execution road (`fm-spawn`/`fm-send`/`fm-watch`/`fm-teardown`) | **the engine** (`src/ymir_runtime/`) — four verbs, python, stdlib only; the doors are thin adapters over it and the old road keeps running until parity is proven (plan 58, Phase 1) |
| Worktree engine (Yggdrasil) | **Yggdrasil** (`<BROKK_HOME>/.yggdrasil/<id>`) |
| Isolated home variable (`FM_HOME`) | **`BROKK_HOME`** |

**Brokk = the primary.** Read-only over projects except under a concrete, approved operation. **Eindri = sub-agents.** One autonomous agent per task, isolated worktree, optional Utgard sandbox. **Allfather = the operator.** Talks only to Brokk; Eindri never address the Allfather.

## 2. Home layout — tracked vs private

`BROKK_HOME` selects an *instance's private* `data/`, `state/`, and `config/`, while scripts continue to come from the tracked code root (`BROKK_ROOT_OVERRIDE`, defaulting to the repo root). This is the upstream `FM_HOME` separation (`$BROKK_UPSTREAM/AGENTS.md:42-54`) mapped onto Ymir.

```text
BROKK_HOME = repo root ($YMIR_ROOT)  ── platform home
           = svartalfaheim/<realm>/         ── realm home (when provisioned)

tracked (shared, committed)            private (gitignored)
  AGENTS.md                              data/     durable context + briefs
  opencode.json                          state/    runtime records, lock, status
  bin/            runtime scripts        config/   local operating choices
  .agents/        skills, profiles       .yggdrasil/  ephemeral task worktrees
  .pi/ .opencode/ .claude/ .codex/ .cursor/   harness adapters
  docs/           plans, masterplan
```

Resolution order used by every script (all overridable):

| Variable | Default | Meaning |
|---|---|---|
| `BROKK_ROOT_OVERRIDE` | `dirname(bin)/..` | the tracked code root; scripts are read from here |
| `BROKK_HOME` | `BROKK_ROOT_OVERRIDE` | the private home that owns `data/ state/ config/` |
| `BROKK_DATA_OVERRIDE` | `$BROKK_HOME/data` | durable context + per-task briefs/reports |
| `BROKK_STATE_OVERRIDE` | `hoard_state_dir` (`$YMIR_STATE_DIR` → `$YMIR_HOME/state`) | lock, cron, metas, status logs, backups |
| `BROKK_CONFIG_OVERRIDE` | `$BROKK_HOME/config` | cron.yaml, eindri-harness, dispatch rules |

### 2.1 Tracked surface

| Path | Holds |
|---|---|
| `AGENTS.md` | The always-loaded contract: mandate, naming, laws, routing |
| `opencode.json` | `default_agent: "brokk"`, the `brokk` primary, subagent profiles, `skills.paths: [".agents/skills"]` |
| `bin/` | Every runtime script (Sága, Sýn, Gná, Gleipnir, Nornir, Einherjar, Erindi, Vör, Rödd, Runes, Hamr) — and the engine's own doors (`bin/engine/ymir-engine.sh`, `bin/records/ymir-state.sh`) |
| `src/ymir_runtime/` | **THE ENGINE** — `seat · status · send · stop` behind one interface, with `worktree · harness · backend · container · heartbeat` below it, and the state crafts under `state/` (`lock` · `runes` · `envelope` · `queue`). A harness never reads it; only a `bin/` door calls it |
| `src/ymir_runtime/state/` | **THE STATE** (plan 58's `state/` shape) — `lock.py` (Gleipnir) · `runes.py` · `envelope.py` · `queue.py`, with `bin/records/ymir-state.sh` as their door. `bin/vault/gleipnir-lock-lib.sh`, `bin/records/runes-append.sh`, and the wake-queue primitives in `bin/time/brokk-wake-lib.sh` are THIN SHIMS over them; parity is the proof |
| `tests/` | Unit tests BESIDE the modules (`src/ymir_runtime/tests/`, reached by a bare `python3 -m unittest` from the root) and the e2e proofs (`tests/e2e/engine-proof.sh`) |
| `.agents/` | Skills (`skills/`), Eindri profiles (`subagents/`), sandbox (`sandbox/Dockerfile.utgard`), tools, bus |
| `.pi/extensions/` | `syn-turnend-guard.ts` (Sýn), `gna-pi-watch.ts` (Gná), `lib/vordr-sessionstart-supervisor.mjs` (Vörðr), `lib/rodd-operational-input.ts` (Rödd) |
| `.opencode/plugins/` | `saga-sessionstart.js`, `syn-watch-arm.js`, `syn-turnend-guard.js`, `syn-pretool-check.js`, `syn-cd-check.js`, `lib/rodd-operational-input.js` |
| `.claude/settings.json` | `SessionStart` + `Stop` hooks (run-tier) |
| `.codex/hooks.json` | `SessionStart`, `PreToolUse`, `Stop` hooks (nudge-tier; payload via stdin) |
| `.cursor/hooks.json` | `sessionStart`, `stop`, `preToolUse` hooks (interactive only) |
| `docs/plans/`, `docs/masterplan.md` | Plans and the append-only order ledger |

### 2.2 Private surface (`.gitignore` at repo root)

`data/*` (except `*.example`), `state/*` (except `.gitkeep`), `config/*` (except `*.example`), `.yggdrasil/`, `svartalfaheim/*/.env.realm`, `.env.local`.

| Path | Holds | Notes |
|---|---|---|
| `data/operator.md` | Allfather preferences/working style | read at every session start; inspect-then-update |
| `data/projects.md` | realm-scoped project registry | one row per project |
| `data/learnings.md` | curated, dated, evidence-backed facts | prune often |
| `data/realm.md` | active realm name | `way-of` today |
| `data/backlog.md` | pointer to `docs/masterplan.md` open orders | never replaces the masterplan |
| `data/<id>/brief.md` | the Erindi brief handed to an Eindri | fixed `Delivery contract: mode=<mode>` line |
| `data/<id>/report.md` | a scout Eindri's deliverable | report only, no branch/PR |
| `state/.lock` | Gleipnir session lock (bare pid) | written by `bin/vault/gleipnir-lock-lib.sh`, the shim over `src/ymir_runtime/state/lock.py` |
| `state/<id>.meta` | task metadata (harness, model, worktree, backend…) | authoritative task record |
| `state/<id>.status` | append-only best-effort event log | last line = last event, not current state |
| `state/<id>.inbox/` | Brokk→Eindri steering message files | `mv NNN.msg handled/` is the ack |
| `state/cron.pid`, `state/cron.log` | Nornir scheduler loop + log | managed by `bin/time/nornir-cron-start.sh` |
| `state/.cron-fired/`, `state/.cron-locks/` | once-a-day date guards + per-job flock | chronological edge protection |
| `state/.wake-queue` | durable Sága wakes | drained, stay until acknowledged; the TSV `<epoch>\t<seq>\t<kind>\t<key>\t<payload>` line is written by `src/ymir_runtime/state/queue.py` through the `bin/time/brokk-wake-lib.sh` shim |
| `state/.supervision-armed`, `state/.watch.heartbeat` | Sýn arm marker + liveness | guard is inert until the first arm; the arm is a SERVICE (plan 58 Phase 2) and keeps both written whether or not a session is seated |
| `state/.arm.lease`, `state/.arm.event`, `state/.arm.wake` | the arm's lease, its delivery slot, its append-only journal | `pid=<pid> starttime=<st> gen=<n> mode=<systemd\|daemon> session=<pid\|none> heartbeat=<epoch> state=<dir>`; `bin/pi/syn-watch.sh status` and Eir's `arm` surface read the lease, `bin/pi/syn-watch-arm.sh` carries the event out |
| `state/.lock-path` | resolved session-lock path | pointer the harness extensions read; written by `gleipnir_lock_acquire`. The lock is machine-local but the pointer lives in the synced home, so a pointer outside the current user's home is stale: both harness readers validate it and heal it (2026-09-23) |
| `state/backups/` | Muninn memory snapshots | written before any prune |
| `state/observer.log`, `state/observer.last` | Huginn observation output | read-only bridge |
| `workspace/memory/runes_audit.md` | Runes chained JSONL ledger | append-only, never rewritten |

## 3. The 8-stage Sága session-start digest

`bin/time/saga-session-start.sh` prints **one ordered digest** and does nothing else. It composes existing scripts; it never re-implements them. The section headers it emits are `== LOCK ==`, `== BOOTSTRAP ==`, `== WAKE QUEUE ==`, `== SUPERVISION ==`, `== UPDATE ==`, `== FLEET DIGEST ==`, `== CONTEXT DIGEST ==`, `== TODAY ==`, `== RECALL ==`, `== SKILLS ==`, `== MODEL CATALOG ==`, `== ASSET ROUTING ==`, `== TOOL SURFACE ==`, `== CRON START ==`, `== NEXT STEP ==`.

**Appended 2026-10-26 (plan 136) — `== RECALL ==`.** The digest now opens the well
before the work: `bin/records/mimir-recall-today.sh` derives the day's topic (a stated
`$STATE/.session-topic` first, else the newest bullet in today's daily log, else the
newest open forge order), asks the well scoped to the last 14 days, and prints the
truth that goes with it — *recall is memory, not authority*. A missing topic is
reported, never guessed, and the section is capped at twelve lines so a slow or cold
well cannot stall the session start.

| # | Stage | What it emits | Source / helper |
|---|---|---|---|
| 1 | **LOCK** | `session lock held (pid N)` or `READ-ONLY: session lock held by pid N - no spawn, steer, merge, drain, or repair this session` | `bin/vault/gleipnir-lock-lib.sh` → machine-global `brokk.lock` for the primary, per-home `state/.lock` for an Eindri-home |
| 2 | **BOOTSTRAP** | `tool floors OK` or `MISSING: …`; `realm env: present` or `realm env: ABSENT (svartalfaheim/<realm>/.env.realm)` | checks `git bash node`; checks `.env.realm` in `$BROKK_HOME` then `$ROOT` |
| 3 | **WAKE QUEUE** | `wake queue: N pending`, each `WAKE <record>`, `WAKE_ACK_REQUIRED`, `open decisions: N` | `bin/agents/eindri-handoff.sh sweep` (the failsafe — sweeps undelivered reports/questions into the queue) **then** `bin/time/saga-wake-drain.sh` → `state/.wake-queue`, `state/*.decision` |
| 4 | **SUPERVISION** | one operating block: `harness next step: arm supervision via the installed harness adapter; never run bin/pi/syn-watch-arm.sh by hand.` | Sýn/Gná per-harness protocols |
| 4b | **UPDATE** | `current — no newer Ymir on npm`, or the newer version with its remedy (`npm i -g @zerwiz/ymir`, then `ymir groa`) | `bin/gates/checks/ymir-update-check.sh` — one cached lookup a day; silent with no network; **exit 3** when a newer version stands |
| 5 | **FLEET DIGEST** | `task metadata records: N` (count of `state/*.meta`) and `open forge orders: N` (`grep -c '^- Status: ADDED' docs/masterplan.md`) | `state/*.meta`, `docs/masterplan.md` |
| 6 | **CONTEXT DIGEST** | `--- realm ---`, then `data/operator.md`, `data/projects.md`, `data/learnings.md`, each delimited; `ABSENT: <path>` when missing | **`$YMIR_HOME/hodd/data/`** via `bin/vault/hoard-lib.sh` (`BROKK_DATA_OVERRIDE` wins) — never `$BROKK_HOME/data`, the code tree, which no operator record has ever occupied |
| 6b | **TODAY** | the day's work, appended blocks under each actor | `bin/records/daily-log.sh today` → `$YMIR_HOME/hodd/memory/daily/YYYY-MM-DD.md` |
| 7 | **CRON START** | `cron: running pid=N jobs=M` or `cron: started …` / `cron: no jobs configured …` | `bin/time/nornir-cron-start.sh` (idempotent) |
| 7b | **TOOL SURFACE** | the Allfather's own handles: `/edit <path>`, `systems/snotra/services/tts-lease/ymir-say.sh`, `bin/host/omarchy-plugins.sh`, `bin/seat/herdr-run.sh` | inline |
| 8 | **NEXT STEP** | `Ascend Hlidskjalf as Brokk. Address the Allfather. Read once; act.` | closing pointer |

**Read-once contract.** The digest is this turn's startup and recovery input. Brokk must **not** re-read the context/backlog/status it just printed unless a source was reported `ABSENT` or corrupt.

### 3.1 The runner — source routing

`bin/time/saga-sessionstart-run.sh` decides, from the session-open source, whether the open needs the full digest, a context re-emit, or a short nudge. It exits 0 on every ordinary transport path: a failed session start must reach the agent as digest text it can act on, never as a refusal to open the session.

| Source | Behavior |
|---|---|
| `startup`, `new`, unknown | run the full `bin/time/saga-session-start.sh`; touch `state/.session-start-complete` |
| `clear`, `compact` | if complete: print `CONTEXT RE-EMIT (source=…)` and a reminder to re-read context only if needed; else run the full digest |
| `resume`, `reload`, `fork` | print the instruction `Run bash …/saga-session-start.sh exactly once now` |
| `--pi-prerequisite` and `BROKK_SESSIONSTART_INELIGIBLE=1` | intentional stand-down, exit 3 |

The source is passed with `--source` or parsed from a Claude/Codex-shaped JSON hook payload on stdin (`"source":"startup"` etc.).

Before routing, the runner raises the Mimirsbrunn well bridge
(`bin/bridge/mimir-bridge.sh --start`, idempotent) so `:4602` listens on **every** open —
the well extension's `session_start` probe finds it up even on a re-emit or nudge.

### 3.2 Harness adapter matrix

| Harness | Surface | Mechanism | Tier |
|---|---|---|---|
| OpenCode | `.opencode/plugins/saga-sessionstart.js` | `session.created` → run digest once per session id, inject via `client.session.promptAsync`; `syn-watch-arm.js` owns `session.idle` | nudge/run |
| Pi | `.pi/extensions/syn-turnend-guard.ts` | native session-open run; digest injected before the first turn; re-emit on compaction; refuse blind turn end | run |
| Claude Code | `.claude/settings.json` | `SessionStart` runs `saga-sessionstart-run.sh`; `Stop` runs `syn-turnend-guard.sh --claude` then async `syn-watch-arm.sh --restart` | run |
| Codex | `.codex/hooks.json` | `SessionStart` pipes the payload to `saga-sessionstart-run.sh`; `Stop` runs the guard; `PreToolUse` runs the Sýn seatbelts | nudge |
| Cursor | `.cursor/hooks.json` | `sessionStart` captures digest and returns `{additional_context}`; `stop` returns `{followup_message}` on guard exit 2; `preToolUse` runs seatbelts | interactive only |
| Grok / Kimi | not yet ported (see `.claude/settings.json` guards `${GROK_AGENT}`/`${GROK_HOOK_EVENT}` to avoid double-fire) | — | — |

`bin/fleet/hamr-harness.sh` (Hamr) detects the harness this process tree wears, in two layers: verified environment markers first (`CURSOR_AGENT=1`, `CURSOR_INVOKED_AS=cursor-agent`, `CLAUDECODE=1`, `PI_CODING_AGENT=true`, `GROK_AGENT=1`), then an 8-hop process-ancestry walk. It prints `claude|codex|opencode|pi|pi-signed|grok|kimi|cursor|unknown`. Subcommands: `eindri`, `eindri-model`, `eindri-effort` resolve the configured Eindri harness/model/effort from `config/eindri-harness` (format `<harness> [<model>] [<effort>]`; `default`/absent resolves to own).

Dispatch is **fail-closed**: `bin/agents/einherjar-spawn.sh` refuses any harness outside the verified set `opencode pi pi-signed` unless a raw launch command (a `--harness` value containing whitespace) is supplied as the deliberate escape hatch.

## 4. Gleipnir — the per-home session lock

Gleipnir is the impossible chain that binds one live Brokk session per home so a second session cannot mutate shared state.

- **File:** `state/.lock` (a bare PID) for an Eindri-home, machine-global `brokk.lock` for the primary — the pointer `state/.lock-path` is read by the Pi extensions.
- **Library:** `bin/vault/gleipnir-lock-lib.sh` (source-safe) is a **thin shim** over `src/ymir_runtime/state/lock.py` through `bin/records/ymir-state.sh`; the shell keeps its names (`gleipnir_lock_acquire`, `gleipnir_lock_release`, `gleipnir_lock_owner`, `gleipnir_lock_owned`, `gleipnir_pid_alive`, `gleipnir_lock_path`, `gleipnir_state_dir`, `gleipnir_root`) and the Python module owns the correctness. Verified by parity: the lock cycle through the shim is byte-identical to the shell it replaced, and the live readers resolve the same path, owner, and starttime.
- **Critical invariant:** the lock must bind to the **live harness process**, not the short-lived digest helper. Harnesses pass `BROKK_SESSION_PID`; when it is absent, `gleipnir_session_pid` walks the ancestry (up to 8 levels) for the harness itself (`pi`, `opencode`, `claude`, `cursor`, `codex`, `grok`, `kimi`, `muse`, `hermes`) and binds to that — only a run with no harness ancestor falls back to `$$`.
- **Why the walk matters:** running `bin/time/saga-session-start.sh` **manually** leaves `BROKK_SESSION_PID` unset. Writing `$$` recorded the digest helper's pid, which is dead a second later — an orphan lock that reads as "no live session" and silently blocks supervision from arming. The ancestry walk is the fix; a helper's pid is never authoritative.
- `gleipnir_lock_owned` walks up to 8 ancestry levels so a helper can prove the session owns the lock.
- **Refused lock ⇒ read-only session.** No spawn, steer, merge, drain, or repair. The digest says so in stage 1.
- **One lock per machine (primary).** The primary's lock is machine-global — `${XDG_STATE_HOME:-$HOME/.local/state}/ymir/brokk.lock` (override `BROKK_MACHINE_STATE_DIR`) — so a second checkout of the same host is read-only and cannot masquerade as its own home. **Eindri-homes are exempt:** an Eindri-home holds its own `<home>/state/.lock` so workers run in parallel with the primary (and on remote hosts). `data/eindri-home` or `BROKK_HOME_KIND=eindri` marks a home as an Eindri-home. `gleipnir_lock_acquire` writes `state/.lock-path` (the resolved path) for the non-bash harness readers, and the extensions fall back to the legacy `state/.lock` for a session that started before this contract. **The pointer's state dir is the operator's hoard state** (`gleipnir_state_dir` resolves through `bin/vault/hoard-lib.sh` for the primary, `<home>/state` for an Eindri-home), so writer and readers agree; a synced pointer naming another user's home (a box reinstalled under a new username) is rejected and healed rather than trusted.
- **Reclaim:** a lock whose pid is not alive is reclaimable; a live foreign pid is never overridden. The guard's `lockOwnership()` treats missing / other / pid 1 as non-owned.

## 5. Sýn / Gná — supervision model

Supervision is **event-driven and zero-token**: no polling by the model, no babysitting. It has three pieces.

| Piece | Figure | Owns | Files |
|---|---|---|---|
| The arm (the watch loop) | **Sýn** | one standing arm per home: polls the state dir, raises `signal:`/`stale:`/`check:`/`heartbeat:` when the primary is needed, and IDLES (never retires) when no session is seated | `bin/pi/syn-watch.sh` (thin door; `run` is the loop), `src/ymir_runtime/watch.py` (the behaviour), `tools/mill/systemd/ymir-syn-watch.service` |
| The thin client | **Sýn** | enters a vacant helm, seats/attaches to the arm, relays the raised line, exits | `bin/pi/syn-watch-arm.sh` |
| Turn-boundary guard | **Sýn** | refuses a blind turn end when supervision is off | `bin/gates/guards/syn-turnend-guard.sh`, `.pi/extensions/syn-turnend-guard.ts`, `.opencode/plugins/syn-turnend-guard.js` |
| Continuity messenger | **Gná** | arms, re-arms, delivers actionable wakes to the Pi session | `.pi/extensions/gna-pi-watch.ts` |
| Digest child warden | **Vörðr** | supervises the Sága digest child so Pi can stream and cap its output | `.pi/extensions/lib/vordr-sessionstart-supervisor.mjs` |

Mechanics:

- **The arm is a SERVICE (plan 58, Phase 2 — 2026-09-27), and its BEHAVIOUR is the ENGINE's (plan 58, Phase 5 — 2026-09-27).** The loop is `bin/pi/syn-watch.sh run`, seated once per home by `ymir-syn-watch.service` (`systemd --user`, `Restart=always` + `StartLimitIntervalSec=60`/`StartLimitBurst=10`, `WantedBy=ymir.target`; materialized by `bin/fleet/fleet-ensure.sh`, program `syn-watch`, roles heart+dev) or, where the one unit does not serve a state (a seat's private state, a probe), by a detached daemon. The lease, the heartbeat, the `up`/`idle`/`stale`/`down` verdict, the raise grammar, and the wake-queue flood brake live in `src/ymir_runtime/watch.py`; `bin/pi/syn-watch.sh` is only the interpreter and the argv, and defines nothing that could drift (it `exec`s `bin/engine/ymir-engine.sh watch`). `bin/pi/syn-watch-arm.sh` is the arm's **thin client**: it runs `gleipnir_lock_acquire` on a vacant helm, attaches to the arm for this home, writes nothing itself, and exits on a `signal:`/`stale:`/`check:`/`heartbeat:` line. The arm writes `state/.supervision-armed`, touches `state/.watch.heartbeat` and its lease every cycle, and **keeps standing when the session's lock owner dies** — a session-owned arm that dies with its session is exactly the fault this replaced (it flapped through 2026-09-27 and needed three hand re-arms). `bin/pi/syn-watch.sh status` reports `up` · `idle` · `stale` · `down` and exits non-zero on a gap; Eir's `arm` surface composes it; `BROKK_WATCH_INLINE=1` keeps the loop in the client for a probe, and an explicit `BROKK_STATE_OVERRIDE` gets its own detached daemon rather than commandeering the machine's unit.
- `bin/gates/guards/syn-turnend-guard.sh` is **inert until the first successful arm** (it returns 0 unless `state/.supervision-armed` exists). When armed, if the heartbeat is missing or older than `BROKK_WATCH_HEARTBEAT_STALE_SECONDS` (default 60), it prints the recovery instruction and exits 2 so the adapter re-prompts.
- **Do not arm before the first successful arm** and **never run `bin/pi/syn-watch-arm.sh` by hand** — the Pi/OpenCode extensions own continuity (arming THIS client, whose watch stands on its own). The PreToolUse seatbelts exist so the extension can deny a bash command that violates an invariant: `bin/gates/checks/syn-arm-pretool-check.sh` blocks backgrounding/detaching the arm (a real `&` or nohup/setsid/disown; `&&` chaining and `bash -n` are allowed), and `bin/gates/checks/syn-guard-pretool-check.sh` blocks destructive shapes against the session lock, the supervision markers, the append-only Runes ledger, the guard/extension machinery itself, secrets, and the fleet-steering registries. They are best-effort guardrails, not a security boundary.
- **Proofs:** `tests/e2e/arm-service-proof.sh [proof|systemd]` (the plan's gate, live: idle with no session, kill → returns, heartbeat fresh, `status` non-zero on an induced gap, Eir names it) and `.agents/tests/syn-watch-arm-silent-exit.test.sh` (the flood brake + the client relay).
- **Calm presentation** and the **Pi supervision branch** were deliberately dropped from the port; they are deferred (see `porting-upstream-to-norse.md` §6).

## 6. Nornir — the cron spine

Nornir are the fates who govern time. `bin/time/nornir-cron-start.sh` keeps exactly **one** lightweight scheduler loop alive (idempotent), started by Sága stage 7 at every session start.

- **Schedule:** `config/cron.yaml`, one `HH:MM <command>` per line, `#` comments, with an optional **role gate**: `@heart[,role] HH:MM <cmd>` or `HH:MM @heart <cmd>`. Both orders parse (the 2026-09-24 fault: only the after-time shape matched, so every role-first line silently never ran). The scheduler runs only the jobs this machine's roles own, resolved from `bin/fleet/topology.sh` / `$YMIR_HOME/hodd/data/fleet.json` — record jobs ride the heart, model/bench jobs ride the forge, a dev body runs only its session jobs.
- **PID/log:** `state/cron.pid`, `state/cron.log` (rotates at `BROKK_CRON_LOG_MAX_BYTES`, default 1 MiB).
- **Once-a-day guard:** `state/.cron-fired/<key>` stores the date; the loop matches `HH:MM` once per day so a job cannot double-run in the same minute or across a loop restart.
- **No overlap:** each job runs under a per-job `flock` in `state/.cron-locks/`; a busy job is skipped with `cron skip (busy)`.
- **Environment:** every job inherits `BROKK_HOME`, `BROKK_STATE_OVERRIDE`, `BROKK_CONFIG_OVERRIDE`, `BROKK_ROOT_OVERRIDE`, `BROKK_REALM`; jobs run from `BROKK_HOME`.
- **Identity guard:** a live loop is a live pid whose `/proc/<pid>/cmdline` still contains `cron run:`, defeating pid reuse.
- **CLI:** `bin/time/nornir-cron-start.sh [--status|--stop]`; status prints `cron: running pid=N jobs=M` or `cron: stopped jobs=M`.

Current schedule (`config/cron.yaml`):

| Time | Command | Figure | Output |
|---|---|---|---|
| 07:00 | `bin/time/nornir-job-daily-briefing.sh` | Sága | `svartalfaheim/<realm>/workspace/memory/daily/YYYY-MM-DD.md` (deterministic, atomic re-run) |
| 06:00 | `bin/time/nornir-job-observer.sh` | Huginn | read-only, self-contained observation of the Ymir runtime; Runes + `state/observer.log`; `ABSENT` is never silence |
| 00:30 | `bin/time/nornir-job-memory-housekeeping.sh` | Muninn | snapshot memory trees to `state/backups/` **before** any prune; engine state reported, not faked |
| 00:00 | `bin/time/nornir-job-git-sync.sh` | Yggdrasil | `fetch` (safe, `--ff-only`) by default or opt-in `push`; never force, never discard unlanded work |

All jobs are **stateless spawns**: fresh process → inject directives → execute → write output → exit. Each carves a Runes line.

### 6.1 The role gate — one fact, every surface (plan 51)

A machine's **role** is ONE fact, declared once, and read by every surface that
would otherwise install, boot, schedule, or route wrongly. It is captured at
install time, before the step chain runs, by `bin/skuld/role-lib.sh` `establish_roles`:

```
role_resolution[4]{source,when}:
  "--role <r> | $YMIR_ROLE","the operator names it for this run; an unknown name is refused (exit 2)"
  "the fleet registry","$YMIR_HOME/hodd/data/fleet.json, read by hostname (bin/skuld/role.sh)"
  "the machine card","the host's own row in hodd/data/machines.md"
  "ask -> the safe body","asked interactively; a run that cannot ask takes `dev` (owns no record) and says so"
```

The components each role owes — the ONE table the installer gates on, and the
record the install folds into `hodd/data/machines.md`:

```
role_components[4]{role,components}:
  "heart","core · record · well · web · mesh"
  "forge","core · rail · harness · sandbox"
  "dev","core · harness · rail · desktop · web · mesh · well · sandbox"
  "hand","core"
```

Three surfaces derive from it, and no surface re-decides it:

- **install** — `bin/engine/ymir-install.sh` `role_gate`s each role-owned step; a
  component this machine's roles do not own is a `SKIP` naming the owning role.
- **boot** — `bin/engine/ymir-autoboot.sh` holds the ONE role→program table, shared with
  `bin/fleet/fleet-ensure.sh`.
- **cron** — `config/cron.yaml` lines carry `@<role>[,<role>]`; a dev body runs no
  `@heart` job.

The role is a *list* — a machine may hold two (`heart,forge` on a combined server,
`heart,dev` on an always-on box that is also a work machine); each surface unions
what its roles owe. A host with no declared role is never silently given every
part.

## 7. Einherjar / Erindi / Vör — the worker model

| Step | Figure | Script | Artifact |
|---|---|---|---|
| Write the errand | **Erindi** | `bin/agents/erindi-brief.sh <id> <repo> --mode <…>` | `data/<id>/brief.md` |
| Gather + launch the worker | **Einherjar** | `bin/agents/einherjar-spawn.sh <id> <project> --mode <…>` | Yggdrasil worktree + backend pane + `state/<id>.meta` |
| Read the worker's true state | **Vör** | `bin/records/vor-crew-state.sh <id>` | one line: `state: <…> · source: <backend|status-log|none> · <detail>` |
| Judge the PR (automatic) | **Forseti** | `bin/agents/eindri-review-spawn.sh <id>` | a scout-kind `<id>-review` errand + the verdict shelf |

**Delivery contract.** A ship brief carries a fixed machine-readable line `Delivery contract: mode=<mode>`; `bin/agents/einherjar-spawn.sh` refuses to launch a ship task whose explicit `--mode` disagrees, so an adjusted brief and the recorded task cannot drift. A scout brief carries `Delivery contract: mode=scout` and delivers `data/<id>/report.md` (no branch, no push, no PR).

**Modes** (ship): `direct-PR` (push `eindri/<id>`, open PR; never merge), `local-only` (work on `eindri/<id>`; Brokk merges local `main` after approval), `no-mistakes` (run the `no-mistakes` pipeline, open the PR it produces). Merge authority stays with the **Glitnir human gate** — Brokk never force-merges, and **a worker never merges its own PR**.

**The seat's own PR is sealed by the seat (2026-11-05, RULES/08 appended; plan 190).** A PR left open is a branch drifting from a moving `main`, so the seat's own green, conflict-free PR — its ONLY open one, `state/.seal-hold` absent — is merged by the seat's agent (Sindri on nidavellir, Hœnir on heimdall) through `bin/agents/pr-seal.sh seal <n>`, with one Runes entry naming PR, head and merge commit. `bin/agents/pr-seal.sh watch` raises ONE wake line through the arm (`state/.wake-queue`) naming PR, head, checks and the exact merge command; the sweep walks that road every time. Another hand's PR is never sealed, and no merge happens on red or on a conflict, under any flag.

**Isolation.** Every worker runs in a Yggdrasil worktree at `<BROKK_HOME>/.yggdrasil/<id>`, created read-only-referencing the project. herdr is the ORDINARY road — no container. Utgard is the EXCEPTION, chosen for untrusted code or an outsized task, never because an image is present. The brief DECLARES it (`Isolation: herdr|utgard — <why>`); `--isolation auto` honours the declaration, and a declared utgard with no image is a LOUD refusal, never a silent downgrade (2026-09-24). A sealed worker mounts the worktree at `/sandbox/workspace`, plus `state/` and `data/` at their host paths. The brief's first instruction to the worker is to verify isolation with `pwd -P` and `git rev-parse --show-toplevel` before touching anything.

**Status protocol.** A worker appends one line `{state}: {one short line}` to `state/<id>.status`; states are `working, needs-decision, blocked, paused, done, failed` (`paused` is configurable via `BROKK_PAUSED_VERB`). Each append wakes Brokk, so reports are sparse. `Vör` reconciles the possibly-stale log against the authoritative backend endpoint recorded in the meta and never infers current state from `tail -1` alone.

**Report-shelf handoff (2026-09-27).** The status line alone is not enough: the failsafe `bin/agents/eindri-handoff.sh sweep` reads only `$STATE/eindri-reports/<id>.md` and `$STATE/eindri-questions/`, never `state/<id>.status`. A worker's terminal act therefore writes its status line **and** a short report to `$STATE/eindri-reports/<id>.md` (what shipped, the PR, the proof); `bin/agents/erindi-brief.sh` carries that line in its template so every errand inherits it. The sweep runs at session start (Sága stage 3) and on a Nornir cadence, idempotently. The fourth failure mode, written from life: **the worker wrote the wrong shelf.**

**The review spine — the judge sent after every ship (2026-09-27).** The delivery-gate law makes a PR the only way work leaves; the spine makes the PR audited before the Allfather's seal. A ship errand's terminal `done` (the terminal act `bin/agents/eindri-acclaim.sh <id> --terminal done --line "…"`) calls `bin/agents/eindri-review-spawn.sh <id>`, which reads the PR from the task's own record (`state/<id>.status` carries `done: opened PR <url>`) and seats **Forseti** as a scout-kind review errand through the einherjar road: `--scout --backend herdr --harness pi --model opencode-go/deepseek-v4.1-flash --effort high`. The fierce brief is filled from `.agents/assets/templates/review-brief.template.md` for THIS task (PR, branch, task id), and the verdict lands on the wake road at `state/eindri-reports/<id>-review.md`.

**One per task.** A `.reviewed` marker (`state/.reviewed/<id>`) is written only after the judge is SEATED, so a re-done never re-reviews, and a failed spawn leaves no marker so a retry can still seat the judge. `YMIR_AUTO_REVIEW=off` is the loud override (it prints why and skips); a failed spawn is queued as a loud wake, never silence. A scout opens no PR, so the spine never reviews a review. The judge is read-only by charter — Forseti's card keeps `edit: deny`/`write: deny`.

**Steering inbox.** Brokk steers a live worker through durable messages in `state/<id>.inbox/NNN.msg`; the worker reads them in numeric order and acknowledges by `mv`-ing each into `state/<id>.inbox/handled/`. The move **is** the acknowledgement.

**Backends.** `tmux` (verified reference) or `herdr` (Þjazi protocol 14+). `config/backend` / `BROKK_BACKEND` / `TMUX` / `HERDR_ENV=1` select it. Spawn prints one line: `spawned <id> harness=<h> kind=<ship|scout> [mode=<m> yolo=<y>] backend=<b> target=<t> worktree=<wt> isolation=<on|off>`.

**Dispatch profiles.** `config/eindri-dispatch.json` holds natural-language rules choosing a per-task harness/model/effort. A profile is ACTIVE only when it parses, carries no unfilled `<...>` model tokens, and every rule's model is servable on THIS machine (`bin/fleet/dispatch-profile.sh active|validate`); the `$YMIR_HOME/hodd/config/eindri-dispatch.json` override wins when present. Install derives a real profile from the machine. When a profile is ACTIVE, `bin/agents/einherjar-spawn.sh` requires an explicit `--harness`/`--model` resolved from those rules (consultation backstop, so profiles are never silently skipped); with no active profile the spawn resolves harness/model FROM THE MACHINE (explicit flags → `bin/model/model-resolve.sh` → `config/agents.yaml` → the fleet law: local → pi, hosted → opencode, provenance printed and recorded) and never from a repo template. Verified harnesses: `opencode pi pi-signed`; effort values are `low|medium|high|xhigh|max`.

### 7.1 The engine — the road itself, with one interface (2026-09-27)

The worker model above is the *contract*. The **engine** (`src/ymir_runtime/`) is
what now carries it out, so the road stops being 156 shell scripts trying to be a
runtime:

```
verbs[4]{verb,returns}
  "seat(errand)","seat_id — worktree + harness + backend + record + heartbeat, all hidden"
  "status(seat_id)","working | blocked | done | idle, read from the record the system already writes"
  "send(seat_id, text)","a durable numbered inbox message FIRST, the pane steer second"
  "stop(seat_id)","reap the backend target, PROVE it is gone, record the terminal line"
modules[6]{file,owns}
  "worktree.py","Yggdrasil: create-or-reuse `.yggdrasil/<id>`; a squatter is a loud refusal, never an overwrite"
  "harness.py","Hamr: harness + model + effort with provenance, and the exact launch line"
  "backend.py","herdr first, tmux the verified fallback: launch · steer · liveness · kill"
  "container.py","the Utgard decision; herdr is owned, the sandbox is REFUSED (see below)"
  "heartbeat.py","the same judgement `bin/agents/eindri-heartbeat.sh` makes: silent | fresh | terminal | absent"
  "seat · status · send · stop","the four verbs, and nothing else public"
```

**The record is the old record.** `seat()` writes the SAME `state/<id>.meta` keys,
the same `working: launched … (heartbeat baseline)` line, the same `.launch.sh`, and
the same seat-private `BROKK_MACHINE_STATE_DIR`, so `bin/agents/eindri-heartbeat.sh`, Vör,
and Hlidskjalf's Fleet read an engine seat with no change at all. What it will not
do is *duplicate* a rule: the worth-a-smith verdict is asked of
`bin/seat/herdr-run.sh`, the door that owns the heuristic.

**Strangler, reversible.** `bin/agents/eindri-start.sh` and `bin/agents/einherjar-spawn.sh` call
the engine when it can fully own the errand and otherwise run the road they already
had. The hinge is exit **4** from `bin/engine/ymir-engine.sh` — "the engine will NOT own
this" — and a non-4 failure is fatal without falling back, because a half-seat is
worse than none. `YMIR_ENGINE=off` disables the handoff everywhere.

**What the engine does NOT own yet** (named, not implied): the Utgard sandbox
(declared utgard → exit 4, the old road keeps it), `--relaunch`, `fm-teardown`'s
backlog transitions and its secondmate-home retirement, and reading a worker's
reply (`send` delivers; `bin/agents/eindri-control.sh` reads). The gods
(`fm-spawn`/`fm-teardown`/`fm-watch`) still stand in the vendored runtime; their
decomposition is Phase 5, one god per PR. The supervision *library* twins are
collapsed — see 7.2 — and the watcher's behaviour and the landed-work gate are
now the engine's — see 7.4.

**Its own home.** `bin/engine/ymir-engine-ensure.sh` builds the engine's private venv
(`$HOME/.fleet/ymir-engine-venv`) at first use when `src/pyproject.toml` declares
dependencies. Since Phase 7 it declares `jsonschema` + `PyYAML` for the config
layer, so the venv is built and both `bin/engine/ymir-engine.sh` and
`bin/gates/checks/ymir-config-check.sh` prefer it; nothing is ever committed (the venv's
`*.egg-info/` is ignored). `bin/engine/ymir-engine.sh` sets `YMIR_ENGINE_ROOT`
so the engine knows the CODE tree it came from — which is not always what
`BROKK_HOME` points at (a caller may point the home at a project so its worktrees
land there).

### 7.2 One library, two names — the port twins collapsed (plan 58, Phase 5)

The port was **duplicated, not adapted**: `bin/agents/brokk-classify-lib.sh` 1770 =
`.agents/backend/fm-classify-lib.sh` 1770, and three siblings, drifting apart by
hand (classify 262 diff-lines, wake 384, lease 110, wake-grant 24). The collapse
keeps the **native side as the one implementation** and turns the vendored name
into a thin adapter — the plan's own "`brokk-*` and `fm-*` become thin adapters,
or one alias table" shape:

```
one_library[5]{native,adapter,why_native_wins}
  "bin/agents/brokk-classify-lib.sh",".agents/backend/fm-classify-lib.sh","the native verbs are Allfather-named and the vendored default crew-state door was missing"
  "bin/time/brokk-wake-lib.sh",".agents/backend/fm-wake-lib.sh","the native stall markers are eindri-home-named and it calls bin/fleet/hamr-harness.sh"
  "bin/agents/brokk-lease-lib.sh",".agents/backend/fm-lease-lib.sh","the native lib carries the resolved state/.lock-path read (Phase 0)"
  "bin/agents/brokk-timeout-lib.sh",".agents/backend/fm-timeout-lib.sh","the native file is the one that actually exists; the vendored classify sourced a missing bin/agents/brokk-timeout-lib.sh"
  "bin/time/brokk-wake-grant.sh",".agents/backend/fm-wake-grant.sh","the native door writes brokk-branch-eligible-owner-v1, the marker the Pi branch extension reads"
```

Each adapter maps the upstream `FM_*` env dialect onto the native `BROKK_*` names
(the upstream caller's own word is final) and sources the one library. The
upstream verb names were repointed onto the native ones in the vendored callers
in the same change, so an adapter defines **no behaviour**; a body added to one is
the second implementation the collapse exists to end. The `bin/`
doors (`bifrost`... `brokk-lease.sh`, `brokk-wake-grant.sh`, `skuld-branch-outcome.sh`,
the Pi extension's two calls) are unchanged, so the extension ABI is intact, and
the live vendored route (`fm-procevent.sh`/`fm-procevent-when.sh`, called by
`bin/agents/eindri-watch.sh`) resolves the same state with the same output.

**What remains for the next errand, said plainly:** `fm-teardown` and `fm-watch`
are still gods (the engine does not own their landed-work gates or the watcher),
and the Utgard seat road still rides `bin/agents/einherjar-spawn.sh` until `container.py`
owns the sandbox.
### 7.3 The config layer — load with schema, refuse loudly (plan 58, Phase 7)

`src/ymir_runtime/config/` validates every config the runtime reads against a JSON
Schema in `config/*.schema.json` BEFORE a value is trusted. A shape fault is a
loud refusal naming the KEY and the FILE; a config with no registered kind is
refused, never returned unvalidated. `load_config(path)` is the one entry
(`load.py` · `schema.py`).

```
kinds[5]{kind,schema,readers}
  "agents.yaml","agents.schema.json","bin/fleet/agents-config.sh · bin/fleet/dispatch-profile.sh · bin/model/local-model-lock.sh · bin/agents/einherjar-spawn.sh"
  "cron.yaml","cron.schema.json","bin/time/nornir-cron-start.sh · systems/snotra/services/cron/hall-snapshot.sh"
  "fleet.json","fleet.schema.json","bin/fleet/topology.sh · bin/agents/eindri-route.sh · bin/bridge/mcp-gateway.sh · bin/model/model-placement.sh · bin/model/rail-resolve.sh"
  "eindri-dispatch.json","eindri-dispatch.schema.json","bin/fleet/dispatch-profile.sh"
  "grants.yaml","grants.schema.json","src/ymir_runtime/grants.py · bin/gates/checks/ymir-config-check.sh"
```

Three invariants JSON Schema cannot state are semantic checks in `load.py`: an agent
name must be a rostered figure (`.agents/agents/` is canonical), the fleet
`heart` must be a declared host — a registry naming a host that is not itself is
refused when the host is known — and every grant must obey the realm law (see
§7.4).

The door `bin/gates/checks/ymir-config-check.sh [examples|validate <file>…|kinds]` picks the
engine venv, prints TOON, and exits **0** every config valid · **1** a config
refused · **2** usage · **3** the validator is missing. The engine's own module CLI
is `python3 -m ymir_runtime.config`, so the four-verb interface is unbroken; the
lifecycle smoke test gains a `config` check over the shipped shapes.

**Unschematized, named not implied:** `config/model-catalog.yaml` and
`config/app-repos.yaml` are read by the runtime but carry no schema yet — they are
the next starting set, not an oversight.




### 7.4 The grants law — explicit, signed, cross-operator shares (plan 58)

Plan 42 federates ONE operator's machines; *Several Ymirs, one company* federates
**several operators' Ymirs**, each with its own private hoard, cooperating on a
company project. That crosses the realm law (Rule 05), so a shared company
namespace is an **explicit grant** between operators — never a blanket merge. The
registry shape is the config kind `grants`; the law is `src/ymir_runtime/grants.py`.

```
grants_law[4]{rule,enforced_by}
  "signed per Heimdall","a GRANT THAT CROSSES OPERATORS is refused without a signature from EACH party's Heimdall, named in the refusal"
  "a card that says signed is signed","a party whose card.signed is true must have its own Heimdall's signature (card claim and registry can never disagree)"
  "no foreign signer","a signature must come from one of the two parties; a Heimdall outside the grant may not sign"
  "no self-grant","a grant naming one Heimdall on both sides is refused"
```

The `card` block is deliberately the SAME shape as the shared A2A agent-card
contract (`packages/contracts` `AgentInterface`: protocol · endpoint · signed),
so the grants law and the typed card speak one contract, never a second. The data
lives in the hoard (`hodd/identity/grants.yaml`, `default_registry()`); the schema
and validator travel with the code. A machine with no registry has no grants.

The door is `python3 -m ymir_runtime.grants [check|signers|default]`; the config
door reaches the same check as
`bin/gates/checks/ymir-config-check.sh validate <grants.yaml>`. Proven offline by
`tests/e2e/several-ymirs-foundation-proof.sh`.

### 7.5 The namespace-scoped journal (plan 58, Several Ymirs)

Plan 51's outbox/reconcile/fold trio already carries offline writes to the heart.
This feature scopes an entry to a **company namespace**: `bin/records/journal-append.sh
--namespace <ns>` adds an `ns` field, and `bin/records/journal-receive.sh` folds an entry
with `ns` into `journal/folded/<ns>/<host>.jsonl` while an entry without one folds
into `journal/folded/<host>.jsonl` as before. A company project's entries are thus
scoped by **operator (host) + namespace** and never merged into a peer's lineage.
The format is extended, never mutated: an entry without `ns` is the operator's own
and reads exactly as it always did. The cross-operator well share and the Óðrerir
company view ride later errands; the foundation is the scoping itself.

### 7.6 The dispatch table — role → figure → model → seat (plan 58, Part 1)

Plan 58's language table puts the rule plainly: **Dispatch — role → figure →
model → seat: Python + YAML; a decision table belongs in data, not in a
1000-line script.** `src/ymir_runtime/dispatch/` is that decision, read as data:

```
dispatch[4]{module,owns}
  "table.py","`.agents/roles.yaml` (canonical, shipped by #223): role → figure · craft · tools · keywords · dispatch. Declares no role; an unrostered figure or a table claiming `model_from` other than `hoard` is a loud refusal"
  "registry.py","the hoard's model, read at runtime from `$YMIR_HOME/config/agents.yaml` (schema-validated by the config layer); a human model REQUEST is resolved by `bin/model/model-resolve.sh` and its TOON is read back — never re-implemented"
  "resolve.py","one errand → one `Resolution` (role · figure · craft · tools · model · harness · effort · seat · kind, with provenance)"
  "__main__.py","`python3 -m ymir_runtime.dispatch [resolve|roles|choose|request]` — the layer's own door face"
```

**The seat type is not re-decided.** `resolve()` reads the `Isolation: herdr|utgard`
declaration through `container.declared_from_brief` (the one owner of that parse),
so a brief cannot be read two ways; an explicit `--isolation` wins, exactly as the
engine's own flag does. The module launches nothing — `seat()` still owns the seat.

**The engine's CLI gains a `dispatch` verb** proving the resolution without adding
a fifth verb to the four-verb interface:

```bash
bin/engine/ymir-engine.sh dispatch developer --toon            # role → figure/model/seat
bin/engine/ymir-engine.sh dispatch --task "write the campaign" --kind ship
python3 -m ymir_runtime.dispatch roles                  # the table, TOON
python3 -m ymir_runtime.dispatch request "qwen 3.6 iq3" # the fleet registry's answer
```

**The two refusals, both naming the key (the config layer's voice):** an unknown
role/figure lists every name the table knows; an absent hoard config names
`agents.<figure>.model` and the exact path. A model value is never carried by the
tree — two hoard YAMLs resolve two different models with the tree untouched.

**What stays with the shell doors.** `bin/agents/eindri-role.sh` (the chooser) and
`bin/model/model-resolve.sh` (the model-request loop) remain the doors the shell
surface uses; the Python layer reads the same data and calls the same resolver,
so neither is forked. `bin/agents/eindri-role.sh` may become a thin adapter over this
layer in a later pass (the strangler), as the config layer's doors did not need to.

### 7.7 The state crafts — one implementation, thin shims (plan 58)

Plan 58's `state/` shape is real: `src/ymir_runtime/state/` holds the four
correctness-critical crafts as deep modules, and the shell that used to own them
is a thin shim. The Python owns the rule; the shell owns its name and its line.

```
state[4]{module,owns,shim}
  "lock.py","Gleipnir: state-dir · lock-path · owner · pid-alive · reap · acquire · release, with the harness-ancestry session pid and the /proc starttime that makes pid reuse read as death","bin/vault/gleipnir-lock-lib.sh"
  "runes.py","the append-only chained ledger: head · escape · fold (prev + \\n + base) · flock · append; never rewrites, never truncates","bin/records/runes-append.sh"
  "envelope.py","the durable wrapper state files travel in: kind · id · created · payload, encoded as key=value meta or one JSON object, written atomically (temp + os.replace)","—"
  "queue.py","the durable wake queue: the TSV <epoch>\\t<seq>\\t<kind>\\t<key>\\t<payload> line, cleaned fields, the seq file, one O_APPEND write","bin/time/brokk-wake-lib.sh (fm_wake_append · fm_wake_queued_keys_locked)"
```

The door is `bin/records/ymir-state.sh` (picks the interpreter, sets `PYTHONPATH` to the
tree, execs `python3 -m ymir_runtime.state`); exit codes are the module's own —
**0** ran/condition true · **1** condition false or IO failed · **2** usage. A shim
that cannot reach the door fails **loud** (`bin/vault/gleipnir-lock-lib.sh` refuses
non-zero), so a wake or a lock is never dropped silently. The npm `files` array
ships `src/`, so a packaged install carries the door and its module together.

**Parity is the proof, not the assertion.** `test_state.py` is the unit suite
(beside the modules) and `test_state_parity.py` runs the shim against the shell it
replaced (kept verbatim under `src/ymir_runtime/tests/fixtures/state/`): the lock
cycle, the rune append, and the queue append are byte-identical, the ledger still
chains, and the live readers resolve the same path, owner, and starttime.
### 7.8 The living rail resolver — where models come from, resolved once (plan 51 Parts 9a/9b/9c)

The rails are a LIVE set, not a single point: models come from whichever strong
box is CONNECTED at the moment (heimdall · whynot · omarchy), and a box that
drops out of the tailnet drops out of the lane — a lane reroute, never an outage.
The WHERE-MODELS-COME-FROM rule now lives ONCE in `src/ymir_runtime/fleet/rail.py`,
reached by the door `bin/model/rail-resolve.sh`; every surface that states a rail URL
calls it, and none restates one.

```
fleet_rail[5]{piece,owns}
  "rail.py","the private registry ($YMIR_HOME/hodd/data/fleet.json, never shipped): the strong boxes are its `rails` list, else its `ear` list, else its `forge` hosts — a box not declared is never invented"
  "liveness","`GET /health` first (keyless, cheap), then `GET /v1/models` with the shared key; a key refused still reads ALIVE — only the served set is unknown"
  "the answer","rank first-alive → the serving `http://<box>:8080/v1`; with an alias, the first live box that SERVES it. Every rail down, or no live box serving the name, is a DECLINED answer (exit 1) — never a fake URL"
  "the key","a REFERENCE — the env `LLAMA_SWAP_API_KEY` (env → the hoard vault → pi auth.json); the value is read only to ask a rail what it serves, and is never emitted"
  "the door","`bin/model/rail-resolve.sh resolve|status [--json]` → `python3 -m ymir_runtime.fleet`; TOON for a human, `--json` for callers"
```

**Who calls it.** `bin/model/model-placement.sh` (the ranked rails + reachability),
`bin/agents/eindri-route.sh` (a model errand follows the live set, first-alive at its
head), `bin/gates/checks/model-alias-check.sh` (an alias is verified against the RESOLVED
provider — a seat's name resolves against whichever box serves),
`systems/snotra/services/ear/snotra-transcribe.sh` (the ear's summaries ride the live rail),
`bin/bridge/mcp-gateway.sh` (a `rail` verb and a `rail` row in `status`; the rail is
never an MCP upstream — the upstream map is handed to the engine verbatim), and
`bin/bridge/mcp-config.sh` (the resolved rail under the config's `ymir` block, advisory
metadata a harness ignores). `config/fleet.json.example` and `fleet.schema.json`
carry `rails` and `ear`, so a registry names its strong boxes explicitly (Part
9c's own word: one set serves the models and the ear).

The unit suite is `test_rail.py` — a synthetic registry and a scripted probe: one
box up and one down → the up one serves; both down → declined — and
`.agents/tests/rail-resolve.test.sh` proves the door against a stub rail.

## 7.4 The first god-seams — the arm and the landed gate (plan 58, Phase 5, 2026-09-27)

Phase 5 is "split the gods, delete the twins", **one god per PR**. Two of the
three seams landed in this change; the third is named below.

**The watcher god — Sýn's behaviour is the engine's.** `bin/pi/syn-watch.sh` carried
the arm's whole judgement in 409 lines of bash, while the vendored watcher
(`.agents/backend/fm-watch.sh`, 1962 lines) carried a second, drifting copy of the
same questions over the same record. The judgement now lives ONCE in
`src/ymir_runtime/watch.py`: the lease (`pid`/`starttime`/`gen`/`mode`/`session`),
the heartbeat, the `up`·`idle`·`stale`·`down` verdict, the session-owner read
(asked of `bin/vault/gleipnir-lock-lib.sh`, never re-derived), the raise grammar
(`.wake-queue` with its content-hash flood brake, `*.signal`, `*.check`,
`.watcher-stop`), and the delivery slot + journal. `bin/pi/syn-watch.sh` is a thin
door into it (`exec bin/engine/ymir-engine.sh watch …`), keeping the exact CLI, the exact
TOON row, the exact stderr remedies, and the exact exit codes; the systemd unit is
unchanged (`ExecStart=/bin/bash <bin>/syn-watch.sh run`), because the door `exec`s
the interpreter and keeps the same pid.

```
arm[6]{verb,what,proven_by}
  "status [--detail]","lease/verdict/row from the engine","tests/e2e/arm-service-proof.sh proof"
  "start","unit first, else a detached daemon, then wait for a live lease","arm-service-proof.sh proof+systemd"
  "stop","unit stop plus the lease holder's TERM, then prove it let go","arm-service-proof.sh proof"
  "restart","stop then start","arm-service-proof.sh systemd"
  "run [--emit]","the one loop; --emit is the pre-service probe shape",".agents/tests/syn-watch-arm-silent-exit.test.sh"
  "session_owner","the lock law asked of bin/vault/gleipnir-lock-lib.sh","the arm tests' session cases"
```

**The teardown god's landed gate — `landed.py`.** The gate that decides whether a
worktree may be discarded (uncommitted changes, remote reachability, a merged PR
whose head contains the local work, the content-in-default fallback) is now
`src/ymir_runtime/landed.py`, reached by `python3 -m ymir_runtime landed <wt>` and
by `stop --remove-worktree --require-landed`, which REFUSES to remove a worktree
whose work has not landed, naming the proof that said so. Every uncertainty
(a gh error, an unresolvable default branch, a merge it cannot compute) is a
refusal, never a guess — the vendored gate's fail-safe posture, kept.

What the engine does NOT yet do with it, said plainly: the vendored
`fm-teardown.sh` still holds its own shell copy of the gate, because its suite
(`.agents/tests/fm-teardown.test.sh`) **cannot run on this tree at all** — it
drives `$ROOT/bin/backend/fm-teardown.sh`, and `.agents/bin/` was never vendored. Blind
repointing without that suite is the gamble the plan forbids, so the repoint rides
the next errand, with the suite made runnable first.

**The Utgard seat road — still unbuilt, and it says so.** `container.py` owns the
decision and the refusals (a declared `utgard` with no engine or no image is a
loud refusal, never a silent downgrade) but not the launch: `isolation=utgard`
still returns exit 4 and the old road (`bin/agents/einherjar-spawn.sh`) keeps it. This is
the plan's own Phase 5 honesty clause, and it rides its own PR.

## 8. Context sources

At stage 6 the digest injects, each delimited with an explicit `ABSENT` marker:

| Source | Purpose | Absent means |
|---|---|---|
| `data/realm.md` | active realm | digest defaults realm to `wayof` (when the tenant is seated) |
| `data/operator.md` | Allfather voice, working style, standing rules | use built-in defaults |
| `data/projects.md` | realm project registry | rebuild from realm `projects/` |
| `data/learnings.md` | curated operational facts | no curated facts yet |
| `svartalfaheim/<realm>/HOOD.md` | the holdings map (private hoard + realm seat) | `hood` printed ABSENT; seat not carved yet |
| `docs/masterplan.md` | open forge orders (counted, not dumped) | `open forge orders` omitted |

Absence is meaningful: **an absent file is never confused with an empty-but-present one.** The fleet digest additionally reads `state/*.meta` and the bounded `state/*.status` tail; the wake drain reads `state/.wake-queue` and `state/*.decision`.

## 9. Runes and Rödd

- **Runes** (`bin/records/runes-append.sh`): append-only chained JSONL under `hodd/memory/runes_audit.md`. Each entry folds the previous checksum into its own (`"prev"` field), so a line cannot be altered or removed without breaking every later line. CLI/library: `runes-append.sh <actor> <event> [--order Wxxxx] [--realm R] --message "…"`; exit 0 appended, 1 IO error, 2 usage. The chain is owned by `src/ymir_runtime/state/runes.py` through `bin/records/ymir-state.sh`, and `bin/records/runes-append.sh` is a **thin shim** over it — locked with `flock` on `state/runes.lock` so concurrent writers cannot fork the chain, and proven byte-identical to the shell it replaced. **Never rewrites, never truncates.**
- **Rödd** (`bin/agents/rodd-operational-input.sh`): the structured wire between the primary and workers. Form `U+2063 RODD_OP: v1 <kind>: <body>`; kinds `session-start watcher turn-end-guard away-supervisor launch-brief branch-outcome` plus the `from-brokk` carrier. CLI `encode|kind|classify|body`; the `.pi` and `.opencode` adapters call it rather than re-parsing the wire. This file is the **single owner** of the protocol; callers must never re-parse it.

## 10. Restart semantics

Restart is a non-event: **durable `data/` + `state/` + live backend inventory are authoritative.** No memory is carried in-process.

| On restart | Behavior |
|---|---|
| A new harness opens | Sága runs; Gleipnir reclaims a dead-pid lock; stages re-emit |
| Session process replaced (`/new`, `/resume`, `/fork`, reload) | Pi binds a new live generation so monitoring re-arms without restarting Pi; stale callbacks no-op |
| Cron loop died / host rebooted | Sága stage 7 restarts it; `state/.cron-fired` date guards prevent a double-run that day |
| Worker pane gone | `Vör` reports `unknown/none` with `backend target gone`; the meta/worktree persist |
| Supervision was armed and the watcher is stale | Turn-end guard exits 2 and re-prompts; recovery is to re-arm via the extension |
| Digest already taken this lock (`clear`/`compact`) | runner emits the context re-emit rather than re-running the full digest |

## 11. Environment reference

| Variable | Used by | Default / meaning |
|---|---|---|
| `BROKK_HOME` | all | private home; defaults to `BROKK_ROOT_OVERRIDE` |
| `BROKK_ROOT_OVERRIDE` | all | tracked code root |
| `BROKK_DATA_OVERRIDE` | Sága, Erindi, Einherjar, jobs | `$BROKK_HOME/data` |
| `BROKK_STATE_OVERRIDE` | all | `hoard_state_dir` (`$YMIR_STATE_DIR` → `$YMIR_HOME/state`) |
| `BROKK_CONFIG_OVERRIDE` | Hamr, Nornir, Einherjar | `$BROKK_HOME/config` |
| `BROKK_SESSION_PID` | Gleipnir, adapters | live harness pid bound into `state/.lock` |
| `BROKK_REALM` | Sága, jobs | realm; else `data/realm.md`; else `way-of` |
| `BROKK_PROC_ROOT_OVERRIDE` | Hamr | `/proc` override (tests) |
| `BROKK_PI_HARNESS` | Hamr | `pi-signed` distinguishes signed Pi |
| `BROKK_SESSIONSTART_INELIGIBLE` | runner | `1` ⇒ Pi prerequisite stand-down (exit 3) |
| `BROKK_BACKEND` | Einherjar | `tmux`/`herdr`; else `config/backend`, `TMUX`, `HERDR_ENV` |
| `BROKK_TMUX_SESSION` | Einherjar | tmux session name (default `brokk`) |
| `BROKK_PAUSED_VERB` | Erindi, Vör | status verb for deliberate idling (default `paused`) |
| `BROKK_WATCH_POLL_SECONDS` | Sýn | watcher poll interval (default 5) |
| `BROKK_WATCH_HEARTBEAT_STALE_SECONDS` | Sýn | staleness threshold (default 60) |
| `BROKK_WATCH_INLINE` | Sýn | `1` keeps the watch loop inside `bin/pi/syn-watch-arm.sh` (the pre-service shape; a probe) |
| `BROKK_WATCH_DAEMON_GRACE_SECONDS` | Sýn | seconds the client waits for a re-seated arm before crying `stale:` (default 15) |
| `SYN_WATCH_UNIT` | Sýn | the unit `bin/pi/syn-watch.sh` reports/starts (default `ymir-syn-watch.service`) |
| `BROKK_WATCH_PREDECESSOR_ARM_PID` | Sýn/Gná | watch generation identity |
| `BROKK_WATCH_ARM_SCRIPT` | Gná | arm script path override |
| `BROKK_PI_ARM_READY_TIMEOUT_MS`, `BROKK_OPENCODE_ARM_READY_TIMEOUT_MS` | adapters | arm readiness timeout |
| `BROKK_WATCH_ARM_RETIRE_TIMEOUT_MS`, `BROKK_WATCH_REARM_RETRY_{BASE,MAX}_MS`, `BROKK_WATCH_REARM_RETRY_LIMIT` | OpenCode Sýn | re-arm retry tuning |
| `BROKK_CRON_LOG_MAX_BYTES` | Nornir | log rotation (default 1048576) |
| `BROKK_RUNES_FILE` / `_DIR` / `_LOCK` | Runes | ledger/lock overrides |
| `BROKK_BRIEF_DIR`, `_MAX_ORDERS`, `_MAX_RUNES` | Sága briefing | output dir and bounds |
| `BROKK_GIT_SYNC_MODE` / `_REMOTE` / `_TARGETS` | Yggdrasil job | `fetch`/`push`, remote, repo list |
| `BROKK_BACKUP_DIR`, `BROKK_MEMORY_ROOTS`, `BROKK_MIMIR_DB`, `BROKK_MEMORY_PRUNE`, `BROKK_MEMORY_PRUNE_DAYS` | Muninn | backup and prune controls |
| `BROKK_YGGDRASIL_ROOT` | Huginn | external, read-only worktree root (`~/.Yggdrasil`) |
| `VORDR_SESSIONSTART_SUPERVISOR_PID` | Vörðr | supervisor identity passed to the child |

## 12. Production acceptance criteria

From plan 29 §8, restated as the runtime's testable contract:

1. Launching a verified harness in `BROKK_HOME` makes the agent respond **as Brokk** and address the operator as **Allfather**, before any tool call.
2. The digest is injected **before the model's first turn** on a run-tier harness, and a nudge appears on a nudge-tier harness.
3. The digest contains all eight stages; a truncated startup names exactly which stage never ran.
4. Context sources appear delimited, with explicit `ABSENT` markers.
5. **Cron jobs are running after session start**; `bin/time/nornir-cron-start.sh` is idempotent and reports why if it fails.
6. A lock-refused session is read-only: no spawn, steer, merge, drain, or repair.
7. Brokk can spawn an Eindri through `bin/agents/einherjar-spawn.sh` into a Yggdrasil worktree sealed by Utgard, supervise it, and deliver a PR/local merge through the Glitnir human gate.
8. Restart is a non-event: durable `data/` + `state/` + live backend inventory are authoritative.
9. No platform backend order was started before the frontend gate (plan 29 §4) went green.

Additional runtime invariants that must hold:

- Every script is `bash -n` clean and smoke-tested; every failure reports a plain reason, never a silent fallback.
- The lock binds to the live session pid via `BROKK_SESSION_PID`.
- The turn-end guard is inert until the first successful arm writes `state/.supervision-armed`.
- The arm is a standing service: `bin/pi/syn-watch.sh status` exits 0 (`up` or `idle`) while the lease is live and the heartbeat is fresh, and non-zero on a gap; a killed arm returns (systemd `Restart=always`, or the thin client re-seating it).
- `rodd-operational-input.sh` is the single owner of the wire; callers never re-parse it.
- `runes-append.sh` never rewrites or truncates; the chain stays unbroken.
- A scout spawn never carries `--mode`; a relaunch re-derives kind/mode from `state/<id>.meta`.
- Dispatch on an unverified adapter is fail-closed.
- **The install is role-selected.** `bin/engine/ymir-install.sh` resolves the role
  before its step chain and gates every role-owned step; a component the
  machine's roles do not own is a SKIP naming the owning role, and an unknown
  `--role` is refused. The same role picks the boot set
  (`bin/engine/ymir-autoboot.sh`), the cron gate (`config/cron.yaml` `@role`), and the
  MCP config (`bin/bridge/mcp-config.sh`).
- **No mocks, no examples, no placeholders** in the shipped runtime.

## 13. Operations cheat-sheet

```bash
# Seat Brokk (once per session; the harness usually injects this already)
bash bin/time/saga-session-start.sh

# Route/emit a digest for a specific open source
bash bin/time/saga-sessionstart-run.sh --source compact

# Harness detection
bash bin/fleet/hamr-harness.sh                 # own harness
bash bin/fleet/hamr-harness.sh eindri          # configured Eindri harness
bash bin/fleet/hamr-harness.sh eindri-model    # optional model token

# Cron spine
bash bin/time/nornir-cron-start.sh --status
bash bin/time/nornir-cron-start.sh
bash bin/time/nornir-cron-start.sh --stop

# Worker lifecycle
bash bin/agents/erindi-brief.sh T42 my-repo --mode direct-PR
# edit data/T42/brief.md, replace {TASK}
bash bin/agents/einherjar-spawn.sh T42 projects/my-repo --mode direct-PR --isolation auto
bash bin/records/vor-crew-state.sh T42

# Audit
bash bin/records/runes-append.sh brokk order.completed --order W0031 --realm way-of --message "…"
```

## Maintaining this

- **Owner:** Brokk. **Sources of truth:** the script headers under `bin/` (exact interfaces), `docs/plans/29-brokk-distro-runtime.md` (the plan), `AGENTS.md:6` (the mandate).
- **When a script's interface changes, update this doc in the same change.** The header is the interface; this doc is the map.
- **When the digest gains or loses a stage**, update §3 and the acceptance criteria count in §12, and reconcile plan 29 §6 (which lists a 9th `NETWORK CHECKS` stage not yet implemented).
- **When a new Nornir job ships**, add a row to §6 and to `config/cron.yaml`.
- **Verification loop:** `for f in bin/*.sh; do bash -n "$f" || echo "FAIL $f"; done` for syntax; `jq . config/eindri-dispatch.json` and `jq .` on each adapter JSON for parse; then a live session start to confirm stage 7 reports the cron running.
- **Cross-check:** `norse-naming.md` §3.2 must list exactly the runtime figures this doc describes.

**rename sweep (2026-09-12).** The `galdr` -> `galdr-ymirsystem` rename corrected a stale compliance path inside `bin/time/saga-session-start.sh`; behaviour unchanged.

### The rename sweep broke governed paths, not just prose (2026-09-12)

`bin/time/saga-session-start.sh` prints the governed-path map, and it carried
`smidja-factory-factory` — a rename artifact. The same wrong token sat in
`AGENTS.md`'s `governed[]` table and in the pretool guard's own `asset_for`
pattern, so the smidja rule stopped matching and protected nothing, silently.

Corrected here and in six other files. A `governed` check now resolves every
path in the table (`compliance-check.sh`), because a governed path that does not
exist fails open — the worst shape a guard can fail in.

### The realm default is `wayof` (2026-09-12)

`bin/time/saga-session-start.sh` derived the realm from `data/realm.md` and then fell
back to `way-of` — a retired multi-tenant name. It now falls back to `wayof`, the
company container this platform actually has, so the digest reads
`svartalfaheim/wayof/.env.realm` for the realm's environment rather than a
directory that no longer exists.

The digest reports the realm env as either present or `ABSENT`; it never prints
the values. Where those values come from and how to set them:
`svartalfaheim/wayof/SECRETS.md`.

## Where the runtime looks (after migration 0004)

The home is split in two, and every resolver follows it:

```
$YMIR_HOME/
├── hodd/            secrets · identity · docs · data · memory (the ledger) · AGENTS.md
└── svartalfaheim/   <realm>/{workspace/{personal,company/…},memory,runs}
```

- `bin/vault/hoard-lib.sh` → `hoard_root` = `$YMIR_HOARD`, else `$YMIR_HOME/hodd`.
- `bin/skuld/realm-lib.sh` → root `$YMIR_HOME`; the realm marker is read from
  `hodd/data/realm.md`, and the realms live under `svartalfaheim/`.
- **One resolver, every script** — `ymir_home_root` (env → the recorded choice in
  `~/.config/ymir/home` → the ONE documented default). A script must **not** carry
  its own default path: a literal `$HOME/Documents/…` both drifts from the recorded
  home and, in `bin/desktop/smidja-board.sh`'s case, *won over* the resolver because it set
  `YMIR_HOME` before the call, pinning the machine to a dead path. `bin/records/runes-append.sh`
  (the ledger), `bin/engine/ymir-validate.sh`, `bin/desktop/smidja-bootstrap.sh`, `bin/desktop/ymir-style.sh`,
  `bin/time/saga-session-start.sh`, `bin/bridge/mimir-bridge.py`, `bin/host/bootstrap-macos.sh` and
  `.agents/skills/lifecycle/smoke_test.sh` now resolve through the lib (2026-09-20).
- `bin/forge/gjallarhorn-expose.sh` — the tunnel **domain and suffix are the operator's**,
  read from `$YMIR_HOME/config/tunnel.env` (env wins); the public tree carries no
  operator domain as a default.
- The Sága digest reads the realm env and the realm's HOOD file from
  `$YMIR_HOME/svartalfaheim/<realm>/`, never from the checkout.
- The daily briefing writes into the realm's `workspace/memory/daily/`; memory
  housekeeping walks `.agents/memory`, the hoard's `memory`, and the realm's.

Why it matters: an installed runtime (npm) may live in a read-only package
directory, so **nothing private or writable may be resolved relative to the
scripts**. Both resolvers are home-based for exactly that reason.

---

## The seat, the process, and the helm — one runtime model (2026-09-28)

**A dated appendix (append-only), the doctrine the churn taught.** Three different
beings, named once so the machine never confuses them:

```
seat_model[4]{being,what_it_is,implications}:
  "session","a durable log identity — the seat's *.jsonl saga, resumable","one session may wear MANY pids across restarts; a restart = a NEW pid, and re-seating is required to regain the helm"
  "pid","a process at an instant; numbers are REUSED after death","a pid in a lock/marker is only trustworthy with a liveness+identity check (kill -0 /proc + the cmdline mark)"
  "helm","the machine lock — ONE pid at a time is the seated primary","per-pid claim, never per-session; a stale .seated marker (dead pid) is a lie the wards must catch; Phase 0c: no process takes the helm from a living owner; the seated primary re-asserts on restart"
  "the watch","the standing arm — a systemd pid with a lease, session-independent","cannot lose the helm because it never held one; the arm's continuity is lease-based, not lock-based"
```

Errands weave all three: task-id ↔ pane ↔ one live pid while seated, and always a
durable record (status · inbox · report) that outlives the pid — the inbox road
answers an errand whose body has already ended. `bin/agents/eindri-send.sh`'s pane
prompt may fail on an ended pane; the durable inbox is the always-true lane.

galdr-reread: the naming map's Sýn + the harness-integration arm section.

## 2026-11-04 — a worker loads ONE extension tree, named explicitly

Measured the hard way: four Eindri were written into Yggdrasil worktrees on herdr and every pane answered
with 43 load errors — `Tool "constellation_list" conflicts with …/.yggdrasil/<id>/.pi/extensions/…` — while
the dispatcher printed `spawned`. The seat's `~/.pi/agent/settings.json` names the **primary** checkout's
extensions tree absolutely; Pi also discovers the project tree under the working directory. Run from
`~/ymir` those are one canonical path and Pi dedupes; run from a worktree they are two, so every extension
registered twice and Pi refused all of them. RULES/13's law — one home per extension, two load paths seats
nobody — broken by the launch road itself, not by a stray file.

The mend lives in `bin/agents/einherjar-spawn.sh`:

```
pi_ext_args <cwd>     # every extension under <cwd>/.pi/extensions, one -e each (dirs by index.ts)
pi|pi-signed launch   # pi --model … -ne$(pi_ext_args "$LAUNCH_CWD") "…brief…"
```

- **Discovery is OFF** (`-ne`) and each extension is named once, from the **worker's own worktree** — so a
  worker can never run the primary checkout's tool code.
- **The npm packages are re-stated** (`-e npm:<pkg>` from the seat settings' `packages[]`), because
  `--no-extensions` also disables package discovery; a silent loss of `pi-mcp-adapter` would be a second
  false green.
- **A `spawned` line is not a running agent.** The same rule as the 2026-10-24 opencode seats: a dispatcher
  proves a pane exists; only a status line proves an Eindri is working. The launch of a Pi worker therefore
  must be read back from `state/<id>.status`, never trusted from the success line alone.

## 2026-11-05 — ONE launcher generator, and a spawn is not a seat until the agent list says so

The 2026-11-04 mend above fixed the **shell** road and left the **engine** road building its own pi line —
`src/ymir_runtime/harness.py::build_launch_command` composed `pi --model … "$(cat …)"` with no `-ne` and no
`-e` at all. Since the engine is the ordinary road (`state/<id>.meta` carries `engine=ymir_runtime/phase1`),
every engine-seated worker still inherited the primary checkout's extension tree through
`~/.pi/agent/settings.json` **and** discovered the worktree's own — the same duplicate-tool crash, the same
dead errand, one layer deeper. Two launchers for one shape is the fault; the shape now lives in exactly one
place:

```
bin/seat/pi-launcher.sh extensions <cwd>   # -e … lines, one per line
bin/seat/pi-launcher.sh print  <cwd> [--model M] [--thinking E] [--brief F]
bin/seat/pi-launcher.sh write  <cwd> <out-script> […]
```

- **Both roads call it**: `bin/agents/einherjar-spawn.sh` (shell) and
  `src/ymir_runtime/harness.py::build_launch_command(selection, brief_ref, launch_cwd)` (engine). The door
  refuses a cwd that holds no `.pi/extensions` tree — a pi seat with no doors open is not a seat.
- **`YMIR_PI_SETTINGS`** names the settings file whose `packages[]` are re-stated (default:
  `~/.pi/agent/settings.json`), so a seat whose packages live elsewhere — and a deterministic test — can say
  where they are instead of inheriting one machine's list.

**And the second half: the proof.** A `spawned … target=<pane>` line used to be printed for an errand whose
pane held a bare shell while the agent had come up in a different pane entirely (measured 2026-11-05: the
record said `wQ:p1`, the agent stood in `w3:pS`). The record is a claim; the agent list is the evidence, so
both roads now ask one door after the launch:

```
bin/seat/seat-prove.sh <pane> <cwd> [--backend herdr|tmux] [--settle N]   # "<pane>\t<state>"
```

It reads `herdr agent list` through `bin/seat/herdr-agents.py --find` (the one reader — a pane is not an
agent) and, on tmux, the pane's own foreground command. Three outcomes, and no fourth:

- **proven in the chosen pane** → `seat=yes`, `seat_state=<working|idle|…>`;
- **proven in another pane** → `seat=yes` and `window=<the pane the agent actually stands in>`, with
  `seat_note` saying the record followed the agent rather than the pane the spawn chose;
- **unproven** → the engine raises and the shell road exits 3: `state/<id>.status` gets
  `failed: the launch produced NO agent — pane <id> …`, the meta records `seat=no`, Gná carries the word
  (`bin/notify/send.sh`), and the dispatcher never prints `spawned`. A half-seat is worse than none.
