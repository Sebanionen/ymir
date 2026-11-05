# Eindri Orchestration — worker spawn, brief, state, isolation, and supervision

Purpose: the complete, production-grade reference for how Brokk gathers an **Eindri** worker
(Einherjar → Erindi → Vör → Yggdrasil → Utgard → Valhalla) from dispatch to delivery.

> **One worker, one brief, one worktree.** Every Eindri is gathered by
> `bin/agents/einherjar-spawn.sh`, reads exactly one brief at `data/<task-id>/brief.md`, and runs in
> exactly one Yggdrasil worktree at `.yggdrasil/<task-id>`. The brief and the recorded task
> cannot drift: both carry the same `Delivery contract: mode=<mode>` line.
>
> Provenance: the upstream agent-distro spawn/brief/state pattern
> (`$BROKK_UPSTREAM/bin/backend/fm-spawn.sh`, `fm-brief.sh`, `fm-crew-state.sh`) is the source
> of the pattern; Ymir's runtime is `bin/agents/einherjar-spawn.sh`, `bin/agents/erindi-brief.sh`, and
> `bin/records/vor-crew-state.sh`, retargeted for plan 29. Upstream nautical labels are provenance
> only — the Ymir names are Norse.

---

## 1. The orchestration chain

| Stage | Norse name | Owner artifact | Lives at |
|---|---|---|---|
| Dispatch decision | **Brokk** | `config/eindri-dispatch.json` (+ `bin/fleet/dispatch-profile.sh`) | repo config |
| Harness detection | **Hamr** | `bin/fleet/hamr-harness.sh` | repo bin |
| Worker gather | **Einherjar** | `bin/agents/einherjar-spawn.sh` | repo bin |
| Worker brief | **Erindi** | `bin/agents/erindi-brief.sh` → `data/<id>/brief.md` | private `data/` |
| Worktree isolation | **Yggdrasil** | `.yggdrasil/<id>` (git worktree) | private `.yggdrasil/` |
| Sandbox seal | **Utgard** | `.agents/sandbox/Dockerfile.utgard` | repo `.agents/` |
| State reconciliation | **Vör** | `bin/records/vor-crew-state.sh` | repo bin |
| Status event log | (Eindri writes) | `state/<id>.status` | private `state/` |
| Steering inbox | (Brokk writes) | `state/<id>.inbox/*.msg` | private `state/` |
| Record | (spawn writes) | `state/<id>.meta` | private `state/` |
| Heartbeat watch | **Valhalla** | `bin/agents/eindri-heartbeat.sh` + `bin/agents/eindri-acclaim-silent.sh` | repo bin |
| Supervision | **Valhalla** | tmux/herdr pane or supervision tree | backend |
| Human merge gate | **Glitnir** | PR review card in Hlidskjalf | portal |

`DATA`, `STATE`, and `CONFIG` default to `$BROKK_HOME/data`, `$BROKK_HOME/state`, and
`$BROKK_HOME/config`. They are gitignored (`.gitignore:59-63`) and are the only writable
surface outside the worktree.

---

## 2. Spawn interface — `bin/agents/einherjar-spawn.sh`

### 2.0 The rule (settled 2026-09-24)

- **herdr is the ordinary road.** A normal Eindri deploy runs in a herdr workspace in a Yggdrasil worktree, with no container at all.
- **Utgard is the exception**, chosen for **untrusted/malicious code** or an **outsized task** — never for routine work, and never merely because a Docker image is present.
- **Two decisions, implemented as stated:**
  - **Isolation is DECLARED in the brief** as a line `Isolation: herdr | utgard — <why>`; the spawn validates the declaration against reality and records the choice and its reason in `state/<id>.meta`. Isolation is never inferred from the task text.
  - **`worth-a-smith` REFUSES by default.** An errand that is not worktree-shaped is refused with the reason and the remedy; an explicit `--force` overrides and the override is recorded in the meta.

### 2.1 Usage forms

```
einherjar-spawn.sh <task-id> <project-dir> --mode <direct-PR|local-only|no-mistakes>
    [--yolo on|off] [--harness <name>] [--model <token|request>]
    [--effort <low|medium|high|xhigh|max>] [--backend tmux|herdr]
    [--isolation on|off|auto] [--force] [--dry-run]

einherjar-spawn.sh <task-id> <project-dir> --scout
    [--harness <name>] [--model <...>] [--effort <...>]
    [--backend <...>] [--isolation <...>] [--force] [--dry-run]

einherjar-spawn.sh <task-id> --relaunch
    [--harness <name>] [--model <...>] [--effort <...>] [--isolation <...>]
    [--force] [--dry-run]
```

`--dry-run` resolves and PRINTS the whole plan before anything is created — engine, isolation (+ reason), backend (+ why), harness, model (+ provenance), worktree, brief, mode, yolo, worth-a-smith verdict, and the launch shape — and creates nothing. `--model <request>` (no `/`) is resolved by `bin/model/model-resolve.sh`; a concrete `provider/model` token is used as-is.

Every spawn prints exactly one record line to stdout:

```
spawned <id> harness=<h> kind=<kind> mode=<m> yolo=<y> backend=<b> target=<t> worktree=<wt> isolation=<on|off>
```

(`--scout` omits `mode=`/`yolo=`; the output shape is defined at
`bin/agents/einherjar-spawn.sh:550-554`.)

### 2.2 Flag reference

| Flag | Values | Default | Meaning / failure mode |
|---|---|---|---|
| `<task-id>` (positional 1) | `[A-Za-z0-9._-]+` | required | No `/`, no leading `.`, no spaces; else exit 2. |
| `<project-dir>` (positional 2) | path | required for fresh spawn | Must be a git working tree; else error. Resolved absolute. |
| `--mode` | `direct-PR`, `local-only`, `no-mistakes` | — | **Required for ship spawns.** Refused with `--scout` and `--relaunch`. |
| `--scout` | flag | off | Deliverable is `data/<id>/report.md`; no branch, no push, no PR. |
| `--relaunch` | flag | off | Reuse recorded worktree/kind/mode from `state/<id>.meta`; only harness/model/effort/isolation may change. |
| `--yolo` | `on`, `off` | `off` | Merge posture recorded in the meta for a ship task; not a brief input. |
| `--harness` | name **or** raw command | machine-resolved | Verified: `opencode pi pi-signed`. A value containing whitespace is a raw launch escape hatch. |
| `--model` | token **or** request | machine-resolved | `provider/model[@quant]` passed through; a request (no `/`) resolves via `bin/model/model-resolve.sh`. |
| `--effort` | `low`, `medium`, `high`, `xhigh`, `max` | harness default | Passed to `pi` as `--thinking`; opencode ignores it. |
| `--backend` | `tmux`, `herdr` | herdr when the server answers | See §2.5 — the server's existence, never `herdr-run.sh available`. |
| `--isolation` | `on`, `off`, `auto` | `auto` | `auto` HONOURS the brief's `Isolation:` declaration (see §2.6). `auto` never downgrades a declared utgard. |
| `--force` | flag | off | Overrides a `worth-a-smith` refusal; `force=1` is recorded in the meta. |
| `--dry-run` | flag | off | Resolves and prints the whole plan; creates nothing. |

### 2.3 Environment overrides

| Variable | Effect |
|---|---|
| `BROKK_ROOT_OVERRIDE` | Root used when `BROKK_HOME` is unset. |
| `BROKK_HOME` | Home owning `data/ state/ config/`; defaults to repo root. |
| `BROKK_STATE_OVERRIDE` | Override `state/` (metas, status, launch scripts). |
| `BROKK_DATA_OVERRIDE` | Override `data/` (briefs, reports). |
| `BROKK_CONFIG_OVERRIDE` | Override `config/` (dispatch, harness, backend). |
| `BROKK_BACKEND` | Force `tmux` or `herdr` when `--backend` is absent. |
| `BROKK_TMUX_SESSION` | tmux session name when not already inside tmux (default `brokk`). |
| `TMUX` / `HERDR_ENV` | Runtime detection of the active multiplexer. |
| `BROKK_PI_HARNESS` | `pi-signed` selects the signed pi adapter in Hamr. |

### 2.4 Harness and model resolve FROM THE MACHINE, in a fixed order

`bin/agents/einherjar-spawn.sh` resolves harness + model together (D3, 2026-09-24).
The provenance of every choice is printed and recorded (`harness_provenance=`,
`model_provenance=` in the meta). Never from a repo template:

1. **Explicit `--harness <name>` / `--model provider/model`** — used as-is; a bare
   token's harness follows locality (local provider → fleet law -> pi, hosted -> opencode).
2. **`--model <request>`** (a name/family/quant without `/`) → `bin/model/model-resolve.sh resolve "<request>"`;
   the resolved harness is adopted only when no explicit `--harness` was given; an unresolved
   request is a refusal (ask the Allfather).
3. **This machine's agent default** → `config/agents.yaml` via `bin/fleet/agents-config.sh get brokk model|harness`
   (the PRIVATE home — the Allfather's own combination, per-machine overlay included).
4. **The fleet law** → local model -> `pi`, hosted -> opencode. With no configured model,
   a live pi catalog (`pi --list-models`) means the local road exists -> `pi` + first served model.

Fail-closed rules:

- A resolved model the chosen harness cannot SERVE is refused: `pi` requires the pair in the
  live pi catalog; opencode requires a real `provider/model` token (a local provider's model
  must be in the catalog too).
- An unverified harness is refused with a plain reason, never silently downgraded.
- A verified harness whose executable is not on `PATH` is refused.
- `--relaunch` re-verifies the recorded harness (or recorded raw command) the same way.
- The dispatch backstop (below) applies ONLY when an ACTIVE profile exists.

### 2.5 Backend default: herdr when the server answers

`--backend` / `BROKK_BACKEND` / `config/backend` win when set; otherwise the default is
**herdr when the herdr SERVER answers** (`pgrep -f 'herdr server'` or `herdr status --json`
running=true) and tmux when it does not. The reason is printed (`backend_reason=` recorded).
The gate is the server's existence, NEVER `bin/seat/herdr-run.sh available` — that verb answers
for a SESSION's `HERDR_ENV` ("is this shell inside herdr?"), not for whether a server can
host a worker. A herdr server hosts a worker even when the dispatcher sits outside herdr;
conflating the two left the backend on tmux while `herdr server` ran (2026-09-24).

### 2.6 Isolation: declared in the brief, validated by the spawn

`--isolation auto` (the default) HONOURS the brief's declaration line — it never infers
isolation from the task text:

- `Isolation: herdr — <why>` (or absent) → the worktree, no container (the ordinary road).
- `Isolation: utgard — <why>` → verify the `utgard-runner:latest` image; an absent image
  (or no engine) is a LOUD refusal with the remedy, never a silent downgrade.
- `--isolation on` forces Utgard (image required, else refused); `--isolation off` forces the
  worktree but is REFUSED when the brief declares `utgard` (a declared isolation is never
  silently downgraded).
- The choice, the declaration, and the reason are recorded: `isolation=`, `isolation_declared=`,
  `isolation_reason=` in the meta.

### 2.7 The local-model lock

The rail is `--models-max 1` (one resident model, a request evicts; two local workers — or a
worker plus Brokk — thrash the rail). For a LOCAL model the spawn pre-checks
`bin/model/local-model-lock.sh check` and REFUSES with the holder named when the host is at
capacity, then wraps the launched command in the lock so the flock is held from before the
worker starts until after it exits (`locked=yes` in the meta; the launch script's first
`exec` is the lock). The flock is HOST-side: for a sealed run it wraps the `docker run`
itself, not a command inside the container.

### 2.8 worth-a-smith refuses by default

The first law — a SHORT ERRAND IS DONE IN HAND — is enforced here, not only in
`bin/seat/herdr-run.sh`'s help. The errand is the brief's `# Task` text; a refusal is LOUD with
the reason and the remedy. `--force` overrides and records `force=1` / `worth_a_smith=no` in
the meta. A brief still carrying the unfilled `{TASK}` text is refused as not an errand yet.

---

## 3. Erindi — the worker brief

`bin/agents/erindi-brief.sh` scaffolds `data/<id>/brief.md`. It **refuses to overwrite** an existing
brief unless `--relaunch` is given.

### 3.1 Usage

```
erindi-brief.sh <task-id> <repo-name> --mode <no-mistakes|direct-PR|local-only>
erindi-brief.sh <task-id> <repo-name> --scout
erindi-brief.sh <task-id> --relaunch
```

`--relaunch` regenerates from `state/<id>.meta` so a replacement Eindri receives the **same**
delivery contract; it re-derives the mode and refuses `--mode`. `--yolo` is rejected here — it
belongs to spawn (`bin/agents/erindi-brief.sh:70`).

### 3.2 Brief structure (ship)

| Section | Content |
|---|---|
| Role line | "You are an Eindri: an autonomous worker agent managed by Brokk. Work on your own; do not wait for the Allfather." |
| `# Task` | `{TASK}` placeholder Brokk replaces at dispatch. |
| `# Delivery contract` | The fixed machine-readable line `Delivery contract: mode=<mode>`. |
| `# Setup` | Disposable worktree at `.yggdrasil/<id>`, detached HEAD. **herdr is the ordinary road** — the workspace is created in the worktree, no container; Utgard is named as the EXCEPTION (untrusted code / outsized load). The brief DECLARES isolation on its own line: `Isolation: herdr | utgard — <why>` (scaffolded as herdr; a writer who needs Utgard edits it and says why). Isolation assertion first: `pwd -P` + `git rev-parse --show-toplevel` must resolve to the worktree. |
| Branch step | `git checkout -b eindri/<id>` (plus `no-mistakes doctor`/`init` for `no-mistakes`). |
| `# Rules` | Never push default branch / never merge; stay inside the worktree; status protocol; block after two failures; escalate product decisions. |
| Brokk instruction inbox | Read `state/<id>.inbox/*.msg` in numeric order; acknowledge by moving to `handled/`. |
| `# Definition of done` | **machine-checkable**: every gate is a COMMAND the worker runs and records (mode-specific); where a gate cannot be a command it says why. |

### 3.3 The `Delivery contract:` line

- Written only for ship briefs, as `Delivery contract: mode=<mode>`
  (`bin/agents/erindi-brief.sh:245`).
- Read by `bin/agents/einherjar-spawn.sh:327-335`: if present and it disagrees with the explicit
  `--mode`, the launch is **refused**. A missing line warns but launches on `--mode`.
- Scout briefs carry `Delivery contract: mode=scout` (`bin/agents/erindi-brief.sh:183`) and are not
  mode-checked at launch.

### 3.4 Delivery modes

| Mode | Branch/push | Pipeline | Terminal status | Merge owner |
|---|---|---|---|---|
| `no-mistakes` | push `eindri/<id>`, open the pipeline PR | `no-mistakes` | `done: <PR url> (pipeline <status>)` | Glitnir human gate |
| `direct-PR` | push `eindri/<id>`, open PR via `gh` | none | `done: opened PR <url>` | the seat's own agent seals it (`bin/agents/pr-seal.sh`) when green and conflict-free — RULES/08, 2026-11-05 |
| `local-only` | `eindri/<id>` only, no push/PR | none | `done: ready in branch eindri/<id>` | Brokk merges local `main` after Allfather approval |
| `scout` | none | none | `done: {conclusion}` with report at `data/<id>/report.md` | n/a (report only) |

### 3.5 Status protocol (the event log)

The brief instructs the worker to append one line to `state/<id>.status`:

```
echo "{state}: {one short line}" >> 'state/<id>.status'
```

| State | Meaning |
|---|---|
| `working` | Non-terminal phase change; do not end the turn on it. |
| `needs-decision` | A choice belongs to the Allfather; Brokk replies. |
| `blocked` | The worker is stuck and needs Brokk to act. |
| `paused` | Deliberately idling on a known external wait expected to clear (differs from `blocked`). |
| `done` | A Definition-of-done gate is met. |
| `failed` | The task cannot complete. |
| `resolved` | Closes a decision/blocker by exact key; **not** a state. |

A decision/blocker stays open until a `resolved` line carrying its exact key lands; a later
`done:`/`working:` never closes it.

### 3.6 Steering inbox

`state/<id>.inbox/*.msg` is Brokk's durable channel into a running worker. The worker lists
`*.msg`, reads in numeric order, acts, then moves each handled message to
`state/<id>.inbox/handled/`. **The move is the acknowledgement** — without it Brokk rings
again and eventually treats the worker as stuck.

---

## 4. Vör — deterministic state reconciliation

`bin/records/vor-crew-state.sh <task-id>` reads the current state without a model and without trusting
a `tail -1` of the append-only log. Output is one stable line:

```
state: <working|parked|done|blocked|paused|failed|unknown> · source: <backend|status-log|none> · <detail>
```

The separator is a middle dot surrounded by spaces (` · `). Exit code is **0** on any
successful read regardless of state; **2** on a usage error (no id).

### 4.1 Reconciliation order (`bin/records/vor-crew-state.sh:40-124`)

1. Read `worktree`, `kind`, `backend`, `window` from `state/<id>.meta`.
2. Missing/gone worktree → `state: unknown · source: none · worktree gone (torn down?)`.
3. No recorded backend target:
   - a log verb mapping to a recognized run-state → `source: status-log`;
   - otherwise → `state: unknown · source: none · no backend target recorded`.
4. Backend target **alive** (`tmux display-message -p -t <t> '#{pane_id}'` / `herdr pane get <t>`):
   - terminal log verdict (`done`/`failed`) → `source: status-log`;
   - working/parked/blocked/paused → `source: status-log`;
   - otherwise → `state: working · source: backend · endpoint alive: <t>`.
5. Backend target **gone**: a terminal log verdict is durable truth; otherwise
   `state: unknown · source: none · backend target gone: <t>`.

### 4.2 Verb → state map (`bin/records/vor-crew-state.sh:71-81`)

| Log verb | Canonical state |
|---|---|
| `working` | `working` |
| `needs-decision` | `parked` |
| `blocked` | `blocked` |
| `done` | `done` |
| `failed` | `failed` |
| `paused` (configurable verb) | `paused` |
| anything else, incl. `resolved` | `unknown` (never emitted as state) |

`BROKK_PAUSED_VERB` (default `paused`) retargets the paused verb consistently across brief,
state, and reconciliation.

---

## 5. Dispatch profiles and harness override

### 5.1 `config/eindri-dispatch.json`

Brokk reads the dispatch rules **before** dispatching and passes concrete flags. Schema:
`version`, `platform`, `notes`, `rules[]` (`when`, `use[]`, `why`), `default[]`.

**Activation (D4, 2026-09-24) — decided by `bin/fleet/dispatch-profile.sh`, never by file existence:**

1. `$YMIR_HOME/hodd/config/eindri-dispatch.json` (the private override) wins when present and coherent.
2. The repo `config/eindri-dispatch.json` counts as ACTIVE only when it parses, carries no unfilled
   `<...>` model tokens, and every rule's model is servable by its harness on THIS machine.
3. No active profile → machine resolution governs (see §2.4). The shipped template is INACTIVE:
   its `<your-model-id>` tokens would silently steer an opencode worker the fleet never chose.

The install (`bin/engine/ymir-install.sh` step host) DERIVES a real profile from the machine —
`config/agents.yaml` + the live pi catalog — into `$YMIR_HOME/hodd/config/eindri-dispatch.json`
(`bin/fleet/dispatch-profile.sh derive`), so a fresh host never runs on the template.

```bash
bin/fleet/dispatch-profile.sh active        # the ACTIVE profile path, or none
bin/fleet/dispatch-profile.sh validate      # a profile is coherent + servable here
bin/fleet/dispatch-profile.sh derive --out $YMIR_HOME/hodd/config/eindri-dispatch.json
```

The consultation backstop still holds for an ACTIVE profile: with a real profile governing
the machine, a fresh spawn without an explicit `--harness`/`--model` is refused — Brokk must
read the rules and pass concrete flags, so the profiles are never silently skipped.

### 5.2 `config/eindri-harness` (query surface only)

Single first non-empty, non-comment line: `<harness> [<model>] [<effort>]`
(`bin/fleet/hamr-harness.sh:21-24`). Today's file is just `opencode` (harness-only).

```bash
bin/fleet/hamr-harness.sh eindri          # effective Eindri harness
bin/fleet/hamr-harness.sh eindri-model    # optional model token (empty when absent)
bin/fleet/hamr-harness.sh eindri-effort   # optional effort token (empty when absent)
```

> **D3 (2026-09-24): this file is a query surface, NOT the spawn's resolution
> authority.** `bin/agents/einherjar-spawn.sh` resolves harness/model from the machine in the
> §2.4 order (explicit flags → model-resolve → `config/agents.yaml` → fleet law). It no
> longer falls through to `config/eindri-harness` or process ancestry for the default, so a
> repo file can never steer dispatch (`opencode` here versus the Allfather's pi-only law).

---

## 6. Yggdrasil — worktree isolation

`bin/agents/einherjar-spawn.sh` creates or reuses the worktree at `$BROKK_HOME/.yggdrasil/<id>`:

- Base ref: `origin/HEAD` when resolvable, else `HEAD`; created `--detach` so the worker's
  branch is its own (`bin/agents/einherjar-spawn.sh:373-386`).
- A pre-existing directory that is not a worktree root is refused (no silent reuse).
- A relaunch reuses the exact recorded `worktree` and **refuses if it is gone**.
- The linked worktree's `.git` file points at the project's common git dir; that dir's path is
  recorded (`GIT_COMMON`) so Utgard can mount it at the same path.

Manual equivalents (for inspection/repair):

```bash
git -C <project-dir> worktree add --detach .yggdrasil/<id> HEAD
git -C .yggdrasil/<id> rev-parse --show-toplevel
git -C <project-dir> worktree list
git -C <project-dir> worktree remove .yggdrasil/<id>    # teardown
```

> **Isolation assertion is authoritative.** The brief makes the worker prove
> `pwd -P` and `git rev-parse --show-toplevel` are the worktree, not the primary checkout. If
> they are not, the worker must append `blocked: launched in primary checkout, not an isolated
> worktree` and stop.

---

## 7. Utgard — Docker sealing

`--isolation auto` HONOURS the brief's `Isolation:` declaration (see §2.6): the worktree is the
ordinary road, Utgard runs only when the brief declares it — and a declared utgard with no
image is a LOUD refusal, never a silent downgrade. `--isolation on` fails closed if the engine
or image is missing; `--isolation off` is refused against a declared utgard. The old `auto`
behavior (seal "only when the image is present") decided isolation by the presence of a file,
not by a judgement about the code or the task — 2026-09-24 made the decision explicit.

Build the image:

```bash
docker build -f .agents/sandbox/Dockerfile.utgard -t utgard-runner:latest .agents/sandbox
```

The exact launch line emitted by `bin/agents/einherjar-spawn.sh:471` (real flags):

```bash
docker run --rm -it --network none --cpus 1.0 --memory 512m \
  --security-opt no-new-privileges --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "<worktree>:/sandbox/workspace" \
  [-v "<git-common-dir>:<git-common-dir>"] \
  -v "<STATE>:<STATE>" -v "<DATA>:<DATA>" \
  -w /sandbox/workspace utgard-runner:latest bash "<state>/<id>.launch.sh"
```

| Flag | Why it is there |
|---|---|
| `--rm` | No residue; a failed run never accumulates containers. |
| `--network none` | No network by law (`.agents/sandbox/README.md`). |
| `--cpus 1.0 --memory 512m` | Hard CPU/RAM caps mirroring `sandcastle.config.json`. |
| `--security-opt no-new-privileges` | No privilege escalation. |
| `--user "$(id -u):$(id -g)"` | **The host UID/GID fix.** Without it the worker writes files owned by `agentuser`/root and the host cannot manage them. |
| `-e HOME=/tmp` | The image's `HOME` is read-only/absent for the mounted user; `/tmp` keeps tool caches writable. |
| `-v <worktree>:/sandbox/workspace` | The worktree is the only working surface. |
| `-v <git-common-dir>:<same path>` | **The `.git` fix.** A linked worktree's `.git` is a file pointing at the common git dir; mounting it at the identical path lets git resolve inside the container. Without it every git command fails with "not a git repository". |
| `-v <STATE>:<STATE>` / `-v <DATA>:<DATA>` | The brief's status, inbox, meta, and report paths resolve identically inside and outside. |
| `-w /sandbox/workspace` | Working directory matches the brief's under-Utgard path. |

The sidecar `state/<id>.utgard` records the effective seal:

```
image=utgard-runner:latest
network=none
cpus=1.0
memory=512m
security_opt=no-new-privileges
user=<uid>:<gid>
worktree_mount=<wt>:/sandbox/workspace
git_common_mount=<path>:<path>|none
state_mount=<STATE>:<STATE>
data_mount=<DATA>:<DATA>
launch=<state>/<id>.launch.sh
```

`--isolation off` removes `state/<id>.utgard` and launches `bash <state>/<id>.launch.sh` in
the worktree.

---

## 8. Valhalla — supervision

- **tmux**: creates/detaches window `eindri-<id>` in the current or `brokk` session, disables
  auto-rename, sends the launch command. A duplicate window name is refused.
- **herdr**: creates workspace `eindri-<id>` with `--cwd <worktree> --no-focus`, then sends
  the launch command to its pane.
- **Skill assets**: `assets/pi-boot/supervision-tree.yml` defines the Valhalla supervision
  branch (brokk-primary, three Eindri workers, herdr, Mimirsbrunn, Ratatoskr) and
  `assets/pi-boot/herdr-profile.toml` the pane layout. These are reference configurations;
  apply them through the process supervisor, do not hand-run panes.

### 8.1 The silence bridge — a dead worker does not look like a thinking one

`bin/agents/einherjar-spawn.sh` records `launched=`/`launch_iso=` in the meta and appends a heartbeat
baseline to `state/<id>.status` before the worker writes anything. The supervisor treats a
worker with NO status append within a configurable window as SUSPECT and wakes Brokk with the
worker's id, elapsed time, and last line:

- `bin/agents/eindri-heartbeat.sh check <agent> [--window N]` — the condition (exit 0 = SILENT).
  Verdicts: `silent | fresh | terminal | absent`; terminal (`done`/`failed` line or a filed
  report) never wakes.
- `bin/agents/eindri-acclaim-silent.sh <agent>` — the action: an idempotent wake (`state/eindri-silent/`
  markers, size-tracked so a re-silence after new activity wakes again).
- `bin/agents/eindri-watch.sh arm-silence <agent> [--window N]` arms the pair as `when-<agent>-silent`;
  `bin/agents/eindri-watch.sh arm` arms BOTH the report bridge and the silence bridge (best effort),
  and the spawn arms the silence bridge automatically after a successful launch.
- The window: `EINDRI_SILENT_WINDOW` (seconds, default 1800) or `--window`.

Inspect a worker:

```bash
bin/records/vor-crew-state.sh <id>
bin/agents/eindri-heartbeat.sh check <id>
tmux list-windows -t brokk -F '#{window_name}'
tmux capture-pane -pt brokk:eindri-<id> | tail -40
herdr pane list --workspace <ws>
```

---

## 9. Worked examples

### 9.1 Ship a direct PR

```bash
# 1. Brief (mode resolved at intake; the Isolation: declaration scaffolds as herdr)
bin/agents/erindi-brief.sh W0123 my-repo --mode direct-PR
# 2. Brokk replaces {TASK} in data/W0123/brief.md
# 3. Dry-run first — the whole plan, nothing created
bin/agents/einherjar-spawn.sh W0123 /home/<user>/repos/my-repo \
    --mode direct-PR --dry-run
# 4. Spawn (harness/model resolve FROM THIS MACHINE — provenance printed)
bin/agents/einherjar-spawn.sh W0123 /home/<user>/repos/my-repo --mode direct-PR
# 5. Watch state + heartbeat
bin/records/vor-crew-state.sh W0123
bin/agents/eindri-heartbeat.sh check W0123
```

### 9.2 Scout a codebase (report only)

```bash
bin/agents/erindi-brief.sh W0124 my-repo --scout
bin/agents/einherjar-spawn.sh W0124 /home/<user>/repos/my-repo --scout
```

Report lands at `data/W0124/report.md`; the worktree is scratch.

### 9.3 Relaunch after a crash

```bash
bin/agents/erindi-brief.sh W0123 --relaunch          # same delivery contract
bin/agents/einherjar-spawn.sh W0123 --relaunch --harness pi --effort high
```

Worktree, kind, and mode come from `state/W0123.meta`; only harness/model/effort/isolation may
change. If the worktree is gone, the relaunch is refused — recover it first.

### 9.4 Sealed run (Utgard — the exception)

```bash
# The brief MUST declare it (never inferred from the task text):
#   Isolation: utgard — the errand runs untrusted third-party scripts
# Then the spawn verifies the image; a missing image is a LOUD refusal.
docker build -f .agents/sandbox/Dockerfile.utgard -t utgard-runner:latest .agents/sandbox
bin/agents/einherjar-spawn.sh W0125 my-repo --mode local-only --harness opencode
cat state/W0125.utgard
```

### 9.5 Steer a running worker

```bash
mkdir -p state/W0123.inbox
printf 'Use the v2 API; the v1 endpoint is deprecated.\n' > state/W0123.inbox/001.msg
# worker reads, acts, then acknowledges:
#   mv state/W0123.inbox/001.msg state/W0123.inbox/handled/
```

### 9.6 The silence bridge

```bash
bin/agents/eindri-watch.sh arm-silence W0123 --window 1800   # or herdr-run's arm arms both
# a worker that stops appending inside the window fires the wake with:
#   eindri W0123 SILENT: no status append for a while (elapsed 2710s) ...
```

---

## 10. The record — `state/<id>.meta`

Line-oriented `key=value` written atomically by spawn:

| Key | Meaning |
|---|---|
| `id`, `kind` | Task id; `ship` or `scout`. |
| `mode`, `yolo` | Ship only: the delivery mode and merge posture. |
| `harness`, `raw_launch` | Adapter name; raw command when the escape hatch was used. |
| `harness_provenance`, `model_provenance` | WHERE the choice came from (flag / model-resolve / agents.yaml / fleet law). |
| `model`, `effort`, `model_local` | Resolved model/effort and whether the model is LOCAL. |
| `backend`, `backend_reason`, `window` | `tmux`/`herdr`, WHY, and the target id. |
| `worktree`, `project` | The isolated worktree and its source repo. |
| `brief`, `launch` | Paths to `brief.md` and the generated `.launch.sh`. |
| `isolation`, `isolation_declared`, `isolation_reason` | Effective seal, the brief's declaration, and WHY. |
| `worth_a_smith`, `worth_why`, `force` | The worth-a-smith verdict, its reason, and whether `--force` overrode a refusal. |
| `locked` | `yes` = a LOCAL model, so the launch runs under `bin/model/local-model-lock.sh`. |
| `launched`, `launch_iso` | The heartbeat baseline (epoch + ISO) for the silence bridge. |
| `spawn_gen` | Unique spawn generation (`s<epoch>.<pid>.<rand>`). |

`meta_value` reads the **last** matching key (`grep ... | tail -1`), so a torn write can never
shadow a completed record once the atomic `mv` lands.

---

## 11. Verification

```bash
# 1. Scripts parse
for f in bin/agents/einherjar-spawn.sh bin/agents/erindi-brief.sh bin/records/vor-crew-state.sh bin/fleet/ymir-platform.sh \
         bin/fleet/dispatch-profile.sh bin/agents/eindri-heartbeat.sh bin/agents/eindri-acclaim-silent.sh; do bash -n "$f" && echo "OK $f"; done

# 2. The shipped dispatch profile is INACTIVE (it carries unfilled tokens)
bin/fleet/dispatch-profile.sh active; echo "exit=$?"   # no -> machine resolution governs
bin/fleet/dispatch-profile.sh validate config/eindri-dispatch.json; echo "exit=$?"  # fail, named

# 3. A derived profile IS active (on a machine with config/agents.yaml + pi)
bin/fleet/dispatch-profile.sh derive --out /tmp/dispatch.json && bin/fleet/dispatch-profile.sh active

# 4. Help/usage renders (exit 0)
bin/agents/einherjar-spawn.sh --help >/dev/null && echo "spawn help OK"
bin/agents/erindi-brief.sh --help   >/dev/null && echo "brief help OK"

# 5. Dry-run prints the whole plan and creates nothing (a scratch state dir)
BROKK_DATA_OVERRIDE=/tmp/d BROKK_STATE_OVERRIDE=/tmp/s BROKK_CONFIG_OVERRIDE=/tmp/c \
  bin/agents/einherjar-spawn.sh demo /repo --mode direct-PR --dry-run
[ -z "$(ls -A /tmp/s)" ] && echo "dry-run created nothing"

# 6. Fail-closed on a fresh spawn without an explicit harness
bin/agents/einherjar-spawn.sh demo /tmp/not-a-repo --mode local-only; echo "exit=$?"

# 7. Silence bridge: a fake status with an old timestamp is reported
old=$(( $(date +%s) - 3600 )); printf 'launched=%s\n' "$old" > /tmp/s/agent.meta
printf 'working: baseline\n' > /tmp/s/agent.status; touch -d '1 hour ago' /tmp/s/agent.status
BROKK_STATE_OVERRIDE=/tmp/s bin/agents/eindri-heartbeat.sh check agent   # verdict=silent
BROKK_STATE_OVERRIDE=/tmp/s bin/agents/eindri-acclaim-silent.sh agent    # wakes with id/elapsed/last line
```

---

## 12. Gotchas

- **Ymir itself is not a git repo.** `git -C $YMIR_ROOT rev-parse` fails; a spawn's
  `<project-dir>` must be a real git working tree or Yggdrasil cannot create the worktree.
- **The shipped dispatch profile is INACTIVE (unfilled tokens), and that is the point.**
  Activation is decided by `bin/fleet/dispatch-profile.sh`, never by file existence; only a real
  profile (the `$YMIR_HOME/hodd/config` override, or a machine-derived repo profile) triggers
  the "consult the rules" backstop. Omitting `--harness` under an ACTIVE profile is a hard
  error, not a fallback.
- **Verified set is small.** `opencode pi pi-signed` only. `claude`/`codex`/`cursor` are
  **detected** but not launch-verified; pass a raw `--harness` command to trial one.
- **Brief must exist before spawn.** Spawn refuses with the exact regeneration command in the
  error.
- **Mode drift is refused.** If `Delivery contract: mode=` ≠ `--mode`, spawn exits 1.
- **tmux window collision.** `brokk:eindri-<id>` already existing aborts the spawn; tear it
  down or relaunch.
- **`--relaunch` refuses a vanished worktree.** Recover or recreate it; do not delete the meta.
- **Isolation is never inferred.** It is the brief's `Isolation:` declaration; `auto` honours
  it, and a declared `utgard` with no image is a refusal (never a silent downgrade).
- **`herdr-run.sh available` ≠ the backend gate.** `available` answers for a session's
  `HERDR_ENV`; the backend default asks whether the herdr SERVER runs (`pgrep`/status API).
- **A local model is serialized.** `bin/model/local-model-lock.sh` pre-checks (refuse with the
  holder named when busy) and wraps the launch; two local workers — or a worker + Brokk —
  thrash the rail (`--models-max 1`) without it.
- **`worth-a-smith` refuses by default.** Not-worktree-shaped errands are refused with the
  reason and remedy; `--force` overrides and records `force=1`.
- **Docker UID/GID and `.git` mount are mandatory** for a sealed run; see §7.
- **`resolved` is never a state.** Vör explicitly maps it to `unknown`/non-state so a closed
  decision cannot masquerade as current work.
- **`paused` ≠ `blocked`.** Paused = known external wait expected to clear; blocked = Brokk
  must act.
- **Status is an event log, not state.** Always reconcile with `vor-crew-state.sh`, not `tail`.
- **A silent worker is reported, not assumed thinking.** `bin/agents/eindri-heartbeat.sh` treats no
  status append inside the window as SUSPECT and wakes Brokk with id, elapsed, and last line.

## 13. Maintaining this

- When a spawn flag or the printed `spawned` line changes, update §2 and the compiled example
  in the plan (`docs/plans/29-brokk-distro-runtime.md`).
- When a delivery mode is added, update the brief (`bin/agents/erindi-brief.sh`), the dispatch rules,
  and the tables in §3.4 in the same change.
- When the Utgard `docker run` line changes, re-run §11 and update §7 verbatim.
- When the harness/model ORDER changes, update §2.4 AND the meta keys in §10 in the same pass —
  provenance is part of the record.
- When the isolation rule changes, update §2.6, §3.2, and the brief scaffold
  (`bin/agents/erindi-brief.sh`'s `Isolation:` line) in the same change.
- When the silence window or the heartbeat files change, update §8.1 and §11 in the same pass.
- Keep `VERIFIED_HARNESSES`, the dispatch profiles, and `bin/fleet/hamr-harness.sh`'s adapter set in
  agreement; a mismatch is a compliance failure (see `runtime-compliance.md`).
