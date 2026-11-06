# Nornir Jobs — the scheduled-jobs and Runes-ledger reference

Purpose: the complete reference for Ymir's **Nornir** scheduler (the fates who govern time),
each scheduled job, the append-only **Runes** ledger, and the read-only observer law.

> Jobs are declared in `config/cron.yaml`, started idempotently at every session start by
> `bin/time/nornir-cron-start.sh`, and run statelessly: start → read inputs → write outputs →
> carve a Rune → exit. A job never owns mutable source trees.
>
> Nornir is a Ymir extension. Upstream Brokk has only a watcher
> (`bin/backend/fm-watch-arm.sh`); plan 29 §6 explicitly adds the scheduled spine on top of it.

---

## 1. The scheduler — `bin/time/nornir-cron-start.sh`

### 1.1 Interface

```
nornir-cron-start.sh            # start if stopped (idempotent); report otherwise
nornir-cron-start.sh --status   # cron: running pid=<pid> jobs=<n> | cron: stopped jobs=<n>
nornir-cron-start.sh --stop     # stop the loop, remove state/cron.pid
```

- Exactly **one** lightweight scheduler loop is kept alive, tracked by `state/cron.pid`.
- **Role gate (2026-09-23, plan 51 P4).** A job may carry a role prefix:
  `HH:MM @<role>[,<role>] <command>`. The scheduler reads THIS machine's roles
  from `bin/fleet/topology.sh` (default `dev`) and runs only the jobs whose gate
  includes one of them; no gate means any role. The record jobs belong to
  `@heart`, the model jobs to `@forge`, and a `dev` body runs neither — this is
  what stops a dev box from running a heart's work.
- **Session-scoped retirement (2026-09-23).** Nornir is started BY a session
  (`saga-session-start.sh`), never before one, so the loop retires the moment
  that session is gone: each cycle it reads the machine's session lock
  (`$BROKK_MACHINE_STATE_DIR/brokk.lock`, default `${XDG_STATE_HOME:-$HOME/.local/state}/ymir/brokk.lock`)
  and exits — logging `cron retired - no live session lock` — when the lock is
  absent or its holder is dead or a zombie. This ends the **8-orphan-loop leak**
  left by ended seats; a seat never leaves its scheduler behind. `--stop` still
  stops a loop by hand.
- Liveness is verified by PID **and** the command line carrying the identity mark
  `cron run:` (`/proc/<pid>/cmdline`), so PID reuse after reboot cannot fake a running loop.
- Log rotation: `state/cron.log` rotates to `state/cron.log.1` above
  `BROKK_CRON_LOG_MAX_BYTES` (default 1 MiB).
- **Handoff failsafe sweep (2026-09-27, plan 58 Phase 3).** A row
  (`06:45 bin/agents/eindri-handoff.sh sweep`, any role) delivers every undelivered
  worker report or question into the wake queue — a worker whose terminal act wrote
  `$STATE/eindri-reports/<id>.md` surfaces at the next sweep, re-arm, or session
  start, whatever the live poller was doing. Delivery is idempotent across BOTH
  roads (the poller's `bin/agents/eindri-acclaim.sh` and this sweep) on the ONE shared
  ledger `$STATE/eindri-delivered/<id>.<kind>` (`bin/agents/eindri-wake-lib.sh`), so a
  second sweep — or an acclaim that already fired — never re-fires old news. The
  worker's own terminal act (`bin/agents/eindri-acclaim.sh <id> --terminal done --line …`)
  writes the durable wake itself, with no sweep and no arm running; the sweep is
  the backstop.
- **The sweep asks three questions now (2026-11-05, plan 190).** Before it delivers anything it
  cross-checks every live claim against its pane (`bin/agents/eindri-liveness.sh sweep`): a seat whose
  pane holds a shell, an exit or a crash is DEAD, its status is corrected to
  `failed: … pane <id> …`, and **Gná** carries one wake for it. Then it walks the arm's road
  (`bin/agents/pr-seal.sh watch --quiet`), so a PR of this seat that has turned green raises its seal
  wake without anyone remembering to ask. Delivery of the report shelf is unchanged and last.
- No jobs configured → `cron: no jobs configured (...)` and exit 0.

### 1.2 State files

| Path | Purpose |
|---|---|
| `state/cron.pid` | PID of the live scheduler loop. |
| `state/cron.log` | Timestamped run/skip/last-output log (rotated to `cron.log.1`). |
| `state/.cron-fired/<job-key>` | Once-per-day date guard; holds `YYYY-MM-DD`. |
| `state/.cron-locks/<job-key>.lock` | Per-job `flock` so a slow job never overlaps itself. |

`<job-key>` is the command string with every character outside `[A-Za-z0-9._-]` replaced by
`_` (`bin/time/nornir-cron-start.sh:88`).

### 1.3 Loop mechanics (`bin/time/nornir-cron-start.sh:69-106`)

1. Every 45 seconds, compute `now=HH:MM` and `today=YYYY-MM-DD`.
2. For each non-comment line: split `at=${line%% *}` / `cmd=${line#* }`.
3. Skip unless `at == now`.
4. Skip if the date guard stamp already equals `today`.
5. Write the stamp **before** dispatch, then log `cron run: <cmd>`.
6. Run under `flock -n`; if busy, log `cron skip (busy)`.
7. Run from `$BROKK_HOME` via `bash -lc "$cmd"`, output appended to `state/cron.log`.
8. Export `BROKK_HOME`, `BROKK_STATE_OVERRIDE`, `BROKK_CONFIG_OVERRIDE`,
   `BROKK_ROOT_OVERRIDE`, and `BROKK_REALM` to every job.

Because the stamp is written before the run, a job that crashes mid-run does **not** retry the
same day. That is deliberate: cron is idempotent-by-date, not retrying-by-failure.

### 1.4 Environment (`bin/time/nornir-cron-start.sh:18-20`)

| Variable | Default | Effect |
|---|---|---|
| `BROKK_ROOT_OVERRIDE` | script's parent | Root when `BROKK_HOME` unset. |
| `BROKK_HOME` | `$ROOT` | Home owning the jobs and state. |
| `BROKK_STATE_OVERRIDE` | `$YMIR_STATE_DIR` (`<home>/state`, via `bin/vault/hoard-lib.sh`) | Scheduler state directory — in the home the operator chose, never in the code tree. |
| `BROKK_CONFIG_OVERRIDE` | — (see §2) | Where `cron.yaml` lives — an explicit override always wins. |
| `BROKK_CRON_LOG_MAX_BYTES` | `1048576` | Rotation threshold. |
| `BROKK_REALM` | `""` | Realm exported to jobs (jobs also fall back to `data/realm.md`). |

**The cradle seats both overrides (2026-09-24):** `fleet-ensure` renders
`nornir.service` with `BROKK_STATE_OVERRIDE` and `BROKK_CONFIG_OVERRIDE` set to the
operator's home (`<home>/state` and `<home>/config`) — the scheduler and the smoke
read the same state.

**No job carries its own home default (2026-09-24).** The scheduler and every job
resolve the home through `bin/vault/hoard-lib.sh`; `bin/gates/guards/defaults-guard.sh` refuses a private
default, so a job cannot drift back to a path that is not this machine's. The ward also
refuses a script that uses the home without resolving it.

---

## 2. The schedule is the user's — `$YMIR_HOME/config/cron.yaml`

**The tracked tree ships a template, never the live job list.** The scheduler
resolves the schedule in this order:

1. `BROKK_CONFIG_OVERRIDE` (explicit, unmistakeable);
2. the **home's own** `$YMIR_HOME/config/cron.yaml` — where an operator edits
   their real jobs (`$YMIR_HOME` resolves through `bin/vault/hoard-lib.sh`, the one
   answer the whole runtime shares);
3. the repo's `config/cron.yaml.example` — a template a fresh install copies,
   **never** a live schedule. A tracked `config/cron.yaml` is not consulted.

To take charge of your schedule:

```bash
cp ~/ymir/config/cron.yaml.example ~/Documents/Ymir/config/cron.yaml
# edit ~/Documents/Ymir/config/cron.yaml, then:
bin/time/nornir-cron-start.sh --status   # jobs=<n> from YOUR schedule
bin/time/nornir-cron-start.sh            # resolve + start (idempotent)
```

### The format

```
# Nornir cron schedule — the user's own jobs
# Format: HH:MM <command>. Started idempotently by bin/time/nornir-cron-start.sh.
07:00 bin/time/nornir-job-daily-briefing.sh
06:00 bin/time/nornir-job-observer.sh
00:30 bin/time/nornir-job-memory-housekeeping.sh
00:00 bin/time/nornir-job-git-sync.sh
05:30 bin/time/nornir-job-bragi-scrape.sh
```

- One job per line: `HH:MM <command>` (24-hour, zero-padded).
- Blank lines and lines starting with `#` are ignored.
- Commands are run with `bash -lc` from `$BROKK_HOME`, so relative `bin/...` paths resolve.
- The example template lives at `config/cron.yaml.example` in the tracked tree;
  an operator's real schedule is private in their home (`$YMIR_HOME/config/`).

---

## 3. The jobs

### 3.0 Bragi — the scrape round (`bin/time/nornir-job-bragi-scrape.sh`, 05:30)

- **Reads**: the operator's source list — `$YMIR_HOME/config/scrape-sources.yaml`
  (beside `agents.yaml` and `cron.yaml`, NOT under `hodd/config/`, which does not
  exist). Each entry: `name`, `url`, `kind` (scrape | search), `note`.
- **Writes**: one markdown file per source, `YYYY-MM-DD-<name>.md`, into
  `$YMIR_HOME/hodd/life/marketing/scraped/`, plus a Rune
  (`bragi / scrape.round`).
- **The engine is Firecrawl, and it may be SELF-HOSTED.** A self-hosted engine
  needs a **URL**, not a key: `FIRECRAWL_API_URL` (env → the home's local env →
  the documented default `http://localhost:3002`). The fleet runs it on its own
  iron (heimdall and whynot), keyless (`USE_DB_AUTHENTICATION=false`). A cloud
  `FIRECRAWL_API_KEY` is still honoured, but it is no longer the only road.
- **No SDK.** The job calls the REST API with `curl` (`POST /v2/scrape` for a
  URL, `POST /v2/search` for a query — a query sent to `/scrape` is rejected
  with *Invalid URL*), so `firecrawl-py` is not a dependency.
- **Honest failure:** with no engine reachable it says so and scrapes nothing —
  it never invents a page.

### 3.1 Sága — daily briefing (`bin/time/nornir-job-daily-briefing.sh`, 07:00)

Deterministic, **no model call**. Reads four grounded inputs and writes one file.

| Reads | Writes |
|---|---|
| `docs/masterplan.md` (open forge orders + Active Queue) | `$YMIR_HOME/svartalfaheim/<realm>/workspace/memory/daily/YYYY-MM-DD.md` (atomic `mv`) |
| `state/` (cron status, `.lock`, `*.meta`, `*.status`) | Rune `nornir / briefing.written` |
| `docs/plans/*.md` (active plan status) | |
| `$YMIR_HOME/hodd/memory/runes_audit.md` (today's tail) | |

- Realm resolution: `BROKK_REALM` → first line of `data/realm.md` → `way-of`.
- Safe to re-run within a day: the file is rebuilt atomically from the same inputs.
- Bounds: `BROKK_BRIEF_MAX_ORDERS` (default 15), `BROKK_BRIEF_MAX_RUNES` (default 12).
- `docs/masterplan.md` status parsing strips the trailing period (`[.[:space:]]`), so
  `- Status: ADDED.` is counted as `ADDED`.
- Output override: `BROKK_BRIEF_DIR`.

```bash
BROKK_REALM=way-of bin/time/nornir-job-daily-briefing.sh
```

### 3.2 Huginn — observer (`bin/time/nornir-job-observer.sh`, 06:00)

The raven of observation. Read-only, and **self-contained**: every source lives inside Ymir
(the only external read is the worktree root).

| Source | Signals read |
|---|---|
| `docs/masterplan.md` | open / working forge orders |
| `.agents/agents/*.md` | the agent roster |
| `.agents/memory/well/` | the well (episodes) |
| `$YMIR_HOME/hodd/memory/runes_audit.md` | the ledger — it lives with the hoard, never beside the scripts |
| `apps/smidja/smidja_data/smidja.db` (or `$YMIR_HOME/smidja/smidja.db`) | Smíðja runs (read-only SQLite URI) |
| `~/.treehouse` | worktree dirs + `treehouse-state.json` |

- Writes `state/observer.log` (timestamped lines), `state/observer.last`, and one Rune per
  observation (`huginn / observer.<source>`).
- An absent source carves an explicit `ABSENT` line — silence is never mistaken for health.
- SQLite is opened `file:<db>?mode=ro` with a 3s timeout; the observer never mutates it.
- Overrides: `BROKK_YGGDRASIL_ROOT`.

### 3.3 Muninn — memory housekeeping (`bin/time/nornir-job-memory-housekeeping.sh`, 00:30)

**Appended 2026-10-26 (plan 136): the job now runs the well's grading pass.** After the
night's backup (and only after it succeeds — `--apply` is withheld otherwise, so nothing
is annotated or moved without a snapshot) it runs `bin/records/mimir.sh grade --apply`:
decay by recency and access frequency, exact duplicates annotated void against the copy
that stands, retention-expired episodes archived, and a document moved to
`hodd/reference/` only when it declares `superseded_by:`. The episode count is checked
and a run that lowers it is a FAILURE (Rule 20). `BROKK_WELL_GRADE=0` disables it. This
is what makes forgetting CONTINUOUS rather than a quarterly intention — Eir's `memory`
surface goes red when the last grading run is more than 45 days old.

The raven of memory. Reports, snapshots, then (only if enabled) prunes.

1. Report the engram/vector store state; if no engine is wired, say so — never fake decay.
2. **Backup first**: `state/backups/memory-YYYY-MM-DD.tar.gz` (atomic `mv` from `.tmp.$$`),
   archiving home-relative paths so a restore is home-relative.
3. Prune **only** when `BROKK_MEMORY_PRUNE=1` **and** the backup succeeded; only ephemeral
   `state/` temp files older than `BROKK_MEMORY_PRUNE_DAYS` (default 7).
4. Rune `muninn / memory.housekeeping`.

Safety law: never destructive without a backup; if the backup cannot be written, nothing is
removed and the failure is reported plainly.

| Variable | Default |
|---|---|
| `BROKK_BACKUP_DIR` | `$BROKK_HOME/state/backups` |
| `BROKK_MEMORY_ROOTS` | `.agents/memory:workspace/memory:svartalfaheim/<realm>/workspace/memory` |
| `BROKK_MIMIR_DB` | `.agents/memory/mimirsbrunn.db` |
| `BROKK_MEMORY_PRUNE` | `0` (disabled) |
| `BROKK_MEMORY_PRUNE_DAYS` | `7` |

### 3.5 Óðrerir — Live Hall snapshot (`bin/time/nornir-job-hall-snapshot.sh`, 08:00)

The Live Hall is a glass: it reads `/livehall.json` (same-origin,
`cache: no-store`). This job writes that snapshot from real state via
`systems/snotra/services/cron/hall-snapshot.sh` — runes, the project registry, the cron gauge, the wake
queue, standing smiths, armed `when-` sources, and the landed errands — then
carves Rune `odrerir / hall.snapshot`. The snapshot is written for BOTH install
shapes: `apps/odrerir/public/livehall.json` (a clone, served at request time by
the app's `ymir-livehall-feed` plugin) and, when the app carries a `dist/`, the
same file beside it at `apps/odrerir/dist/livehall.json` (a packaged seat has no
`vite.config.ts`, so `vite preview` serves `dist/` statically — the job's write
lands where the seat reads). Scheduled at 08:00 so it follows the 06:00 observer
and the 07:00 briefing: the morning board carries the day's fresh runes.

| Reads | Writes |
|---|---|
| runes ledger · `hodd/identity/projects.yaml` · `config/cron.yaml` · `state/.wake-queue` · herdr agent list · armed when-sources · `state/eindri-reports/archive/` | `apps/odrerir/public/livehall.json` (gitignored runtime) · `apps/odrerir/dist/livehall.json` when `dist/` exists · Rune `odrerir / hall.snapshot` |

- The snapshot is **runtime, never repo**: `apps/odrerir/{public,dist}/livehall.json`
  are gitignored, so the job never dirties a branch.
- Absent `livehall.json` on the Hall is *not* a build failure — the page paints
  the saga's own count and says so. This job is what makes the board true.
- Idempotent by nature: each run rewrites the same snapshot from the same
  inputs; the cron date-guard suppresses repeat dispatch within a day.

### 3.6 Tyr — NSR compliance round (`bin/time/nornir-job-nsr-compliance.sh`, 02:30)

The NorthStar deterministic gate, run nightly in the quiet hours so sunrise
finds the doors mended or the Rune already says which broke. Runs every
`.compliance/gates/check_*.sh` (danger · env · paths · platform · wiring)
and carves one Rune with the verdict — `nornir / nsr.compliance` on a clean
round, `nornir / nsr.compliance.failed` (exit 1) naming the failed gates.

| Reads | Writes |
|---|---|
| `.compliance/gates/check_*.sh` (deterministic, no network) | Rune `nornir / nsr.compliance[.failed]` · `state/last` line |

- The morning briefing reads the ledger, so a FAIL is seen at 07:00, not
  found by accident.

### 3.7 Forgejo — the local git round (`bin/time/nornir-job-forgejo-git.sh`, 02:45)

The issue-to-PR loop, read each night: lists the local forge's open issues and
carves one Rune with the tally, so a growing queue (or a dead tunnel) is seen
at sunrise. The forge address is the user's, from the home — never the tree:
`$YMIR_HOME/config/forge.env` (`FORGEJO_URL`, optional `FORGEJO_TOKEN`).

| Reads | Writes |
|---|---|
| `$YMIR_HOME/config/forge.env` · `GET {forge}/api/v1/repos/issues/search?state=open` | digest `$_HOME/memory/daily/forgejo-YYYY-MM-DD.md` · Rune `forgejo / git.issues` |

- No `FORGEJO_URL` configured → clean exit (the loop is not armed); a closed
  door (tunnel down) → exit 1 and Rune `forgejo / git.door-down`.
- The forge may be the server's (`forgejo.zerwiz.org` → :3030) or a locally
  provisioned one (`bin/desktop/ymir-marketing-stack.sh --with-forgejo`).

### 3.8 The marketing stack (`bin/desktop/ymir-marketing-stack.sh`)

### 3.8b Gná — the mail desk round (`bin/time/nornir-job-gna-mail.sh`, added 2026-10-23, plan 116)

Four rows a day (`07:20 · 11:20 · 15:20 · 19:20`, any role that owns a mailbox)
keep the desk's store current and prove the desk answers. The job imports every
account declared in the home's `hodd/memory/mail/accounts.yaml` through
`bin/mail/gna_import.py` (read-only, one account, `google` or `imap` — it cannot
send), then probes `http://127.0.0.1:8490/health` with the desk's own token.

Since 2026-10-24 each round also asks `bin/mail/addresses.sh --check` (plan 116
§15.3.1) and prints a **WARN** line, plus a `gna-mail.log` row, for any address
the house uses that cannot receive — measured that evening: `zerwiz.org` publishes
no MX, so `gimle@`, `snotra@`, `reply+*` and `bounce+*` there are undeliverable.
The WARN never fails the import: an address that cannot receive is a DNS or
console fault, and the mail that DOES arrive must still be read.

Its law is the one the plan was born from: **absence is a failure, not an empty
list.** A missing scope file, an unreadable registry, a failed import or a desk
that does not answer writes a `FAIL` line to `state/gna-mail.log` and carves a
Rune — the gate then shows 503 with the command that raises the desk, never an
empty inbox. `--check` probes health alone; `--dry-run` reads and writes nothing.

The desk itself is a systemd **user** unit (`gna-desk.service`, `Restart=always`),
seated once by `bin/mail/install.sh`; a reboot raises it again. Port `8490`
(`GNA_DESK_PORT`), loopback only. The store and the scope live in the home, and
the message spine is git-ignored.

### 3.9 Eir — the daily doctor round (`bin/time/nornir-job-doctor.sh`, 08:15, added 2026-09-24)

Every surface is checked daily so a desktop that cannot open is REPORTED, never
silently dead: `bin/agents/eir-doctor.sh check` (floors, herdr, a2abridge, hermes,
sessrumnir, **shells**, **graphics**, well, mcp, harness, lock, migrations,
hoard). The `shells` surface uses the runtime resolver (`bin/desktop/electron-lib.sh`) —
absence for an installed app is a FAILURE, and the `graphics` surface reports the
DRM truth and the effective GPU policy (`bin/host/graphics-lib.sh`). A broken surface
appends a `doctor.broken` rune and exits 1 so the cron log carries it. Eir is
also reached after every update (`bin/agents/groa-update.sh`).

### 3.10 The role gate parses BOTH orders (added 2026-09-24, plan 54)

The loop's line grammar accepts the `@role[,role]` gate **before** the time
(`@heart 06:00 bin/time/nornir-job-observer.sh` — the shape the home's `cron.yaml`
writes) **or after** it (`06:00 @heart bin/x`). The 2026-09-24 fault: only the
after-time order parsed, so every role-first line was silently DEAD while the
loop still counted it declared — on every seat, the heart's record jobs never
fired. `.agents/tests/cron-role-gate.test.sh` covers both orders. `--status` and
the Hlidskjalf board (`/api/cron`) parse with the same grammar, so the declared
set, the running set, and the shown set are one reality.

- **A loop embeds its parse at spawn.** `nornir-cron-start.sh` hands the body to
  a background `bash -c`; the RUNNING process keeps the grammar of the moment it
  was started. Deploying a parser fix therefore needs the seat's tree pulled AND
  a fresh session (or a `--stop` + start) — a long-lived loop keeps the old body
  until then.

Not a cron job — a **provisioner**: stands Mautic + Postiz + Activepieces
(+ optional Forgejo) on ANY computer, the same OSS engines the server runs.
Env-driven (ports virtualized), secrets generated once into the home, never
inline. Agents (Bragi for marketing, Sindri for git) run it for any user.

```
bin/desktop/ymir-marketing-stack.sh up|status|down|doors
# doors: Mautic :8001 · Postiz :8003 · Activepieces :8005 · Forgejo :8007 (defaults)
```

- Rune `marketing / stack.<action>` carved on each provision action.
- The Allfather's live stack is the server's (`zerwizserver`); its public
  doors are tunnel-driven (`cloudflared`) — see the registry's
  `marketing_doors[]` table.
- Idempotent: gates are pure checks; the cron date-guard suppresses repeat
  dispatch within a day; safe to invoke by hand (`bash bin/time/nornir-job-nsr-compliance.sh`).

### 3.4 Yggdrasil — git sync (`bin/time/nornir-job-git-sync.sh`, 00:00)

The world-tree kept in order. Two modes, both non-destructive:

| Mode | Behavior |
|---|---|
| `fetch` (default, safe) | `fetch --prune`, then `merge --ff-only` only. No upstream → fetched, no merge. Diverged → refused, left untouched. |
| `push` (opt-in) | Commit a dirty tree (never stash/discard), then `push` (never force). |

- Target discovery: `BROKK_GIT_SYNC_TARGETS` (colon-separated) or auto-discovery of
  `$BROKK_HOME`, `workspace/`, `midgard/`, each `svartalfaheim/*`, its `workspace/`, and
  `projects/*`.
- Laws: never `--force`, never `reset`, never `checkout`, never `clean`; a non-repo, no-remote,
  or diverged target is reported and skipped.
- Prints a summary `targets=<n> ok=<n> skipped=<n> failed=<n> mode=<m>` and carves one Rune
  `yggdrasil / git.sync` (plus per-target Runes on skip/failure).

| Variable | Default |
|---|---|
| `BROKK_GIT_SYNC_MODE` | `fetch` |
| `BROKK_GIT_SYNC_REMOTE` | `origin` |
| `BROKK_GIT_SYNC_TARGETS` | auto-discover |

> In this checkout, `git-sync` reports `no git targets found under $YMIR_ROOT` because
> the platform root is not itself a git repository. That is a correct, reported outcome.

---

## 4. Runes — the append-only audit ledger

`bin/records/runes-append.sh` is both a CLI and a **source-safe shell library**. It never rewrites or
truncates existing entries.

### 4.1 Ledger

- Default: `workspace/memory/runes_audit.md` — JSONL lines appended under a Markdown head.
- Each entry chains to the previous by folding the previous `checksum` into its own:
  `checksum = sha256(prev + "\n" + base)`, where `base` contains `timestamp, actor, order,
  realm, event, message, prev`. Altering or removing a line breaks every later line.
- Append is done under **one** exclusive `flock` (`state/runes.lock`) so concurrent writers
  can never fork the chain.

### 4.2 CLI

```
runes-append.sh <actor> <event> [--order Wxxxx] [--realm R] --message "..."
```

Prints:

```
runes: appended actor=<actor> event=<event> order=<order|none> checksum=<hex>
```

### 4.3 Library

```bash
. bin/records/runes-append.sh
runes_append "nornir" "briefing.written" --realm way-of --message "daily briefing written"
# RUNES_LAST_CHECKSUM holds the new checksum
```

### 4.4 Environment

| Variable | Default | Effect |
|---|---|---|
| `BROKK_HOME` | repo root | Home owning the ledger. |
| `BROKK_RUNES_FILE` | `${BROKK_RUNES_DIR:-$BROKK_HOME/workspace/memory}/runes_audit.md` | Explicit ledger path. |
| `BROKK_RUNES_DIR` | `$BROKK_HOME/workspace/memory` | Ledger directory. |
| `BROKK_RUNES_LOCK` | `$BROKK_HOME/state/runes.lock` | Append lock. |

### 4.5 Entry shape

```json
{"timestamp":"2026-09-11T13:47:00Z","actor":"yggdrasil","order":"","realm":"way-of","event":"git.sync","message":"no git targets found under $YMIR_ROOT (mode=fetch)","prev":"","checksum":"3fe78c…"}
```

Every significant runtime action is carved: job runs, spawns, observer observations, git sync,
memory housekeeping, briefings. The canonical stub `.agents/memory/runes_audit.md` carries only
the Markdown head; the live ledger is `workspace/memory/runes_audit.md`.

### 4.6 Verify the chain

```bash
# Recompute the chain from the ledger and compare.
python3 - <<'PY'
import json, re, hashlib
lines = [l for l in open("workspace/memory/runes_audit.md") if l.startswith("{")]
prev = ""
for l in lines:
    e = json.loads(l)
    base = ('{"timestamp":"%s","actor":"%s","order":"%s","realm":"%s","event":"%s","message":"%s","prev":"%s"'
            % (e["timestamp"], e["actor"], e["order"], e["realm"], e["event"], e["message"], e["prev"]))
    calc = hashlib.sha256((prev + "\n" + base).encode()).hexdigest()
    ok = (e["prev"] == prev and e["checksum"] == calc)
    print(("OK   " if ok else "BAD  "), e["event"], e["checksum"][:12])
    prev = e["checksum"]
PY
```

> **Whitespace exactness.** The checksum folds the raw `base` string produced by the shell,
> which JSON-escapes message characters (e.g. `\n` → `\\n`). Recompute using the decoded JSON
> field values exactly as the script wrote them; a naive re-serialization with different key
> ordering or spacing will not match.

---

## 5. The read-only observer law

Plan 23 is a hard contract:

- **Never write outside `state/` and the Runes ledger.** The observer only reads manifests and
  SQLite in read-only mode; Ymir is self-observing.
- Every observation is carved as a Rune line (`huginn / observer.<source>`); the well is
  watered by the memory jobs, not here.
- Realm boundaries are sacred; the external worktree root stays read-only and Ymir owns only
  its own tree.

Violations are a runtime-compliance failure (see `runtime-compliance.md`).

---

## 6. Add a new job

1. **Write the runner** at `bin/time/nornir-job-<name>.sh`:
   - `#!/usr/bin/env bash` + `set -u`, header comment naming the Norse figure and purpose.
   - Source the ledger: `. "$SCRIPT_DIR/runes-append.sh"`.
   - Resolve `ROOT`, `BROKK_HOME`, `STATE`, `DATA` from `BROKK_*_OVERRIDE`.
   - Read only inputs; write outputs atomically (`.tmp.$$` then `mv`).
   - End with one `runes_append "<actor>" "<event>" [--realm R] --message "..."`.
   - `bash -n` clean; fail loudly with `error:` + `help:` on stdout.
2. **Register it** in `config/cron.yaml` as `HH:MM bin/time/nornir-job-<name>.sh`.
3. **(Re)start** the scheduler: `bin/time/nornir-cron-start.sh`.
4. **Prove idempotence**: run the job twice; the date guard must suppress a second dispatch the
   same day, and the job itself must be safe to re-run.

```bash
chmod +x bin/time/nornir-job-example.sh
bash -n bin/time/nornir-job-example.sh
printf '05:00 bin/time/nornir-job-example.sh\n' >> config/cron.yaml
bin/time/nornir-cron-start.sh --status
bin/time/nornir-cron-start.sh
```

---

## 7. Verification and smoke commands

```bash
# 1. Scheduler is running with the expected job count
bin/time/nornir-cron-start.sh --status          # cron: running pid=… jobs=4

# 2. All job scripts and the ledger parse
for f in bin/time/nornir-job-*.sh bin/time/nornir-cron-start.sh bin/records/runes-append.sh; do
  bash -n "$f" && echo "OK $f"
done

# 3. Idempotent start: a second start must not spawn a second loop
bin/time/nornir-cron-start.sh; bin/time/nornir-cron-start.sh --status

# 4. Each job runs standalone (fresh processes, exit 0)
bin/time/nornir-job-daily-briefing.sh
bin/time/nornir-job-observer.sh
bin/time/nornir-job-memory-housekeeping.sh
bin/time/nornir-job-git-sync.sh

# 5. Ledger append + chain
bin/records/runes-append.sh smoke ledger.append --realm way-of --message "nornir smoke"
tail -n 3 workspace/memory/runes_audit.md

# 6. Cron log carries run records
tail -n 20 state/cron.log

# 7. Observer left no writes in the external trees (read-only proof)
git -C $BROKK_UPSTREAM status --porcelain    # must not contain observer edits
```

---

## 8. Gotchas

- **Stamps are written before the run.** A job that fails mid-run will not retry until the next
  day. Make jobs safe to invoke by hand (`bash bin/time/nornir-job-*.sh`) for recovery.
- **PID reuse guard.** A stale `state/cron.pid` whose process is alive but whose cmdline lacks
  `cron run:` is treated as stopped; `--stop` removes it.
- **`bash -lc` means login shell.** A job that depends on a non-login shell environment
  (PATH, aliases) may differ from interactive runs; put explicit env in the script.
- **Two ledgers exist.** The live one is `workspace/memory/runes_audit.md`; the stub under
  `.agents/memory/` is not written by the default path.
- **The chain is order-dependent.** Never hand-edit, reorder, or delete ledger lines; append
  only through `runes-append.sh`.
- **Observer never writes outward.** The observer is self-contained: it reads only Ymir's own
  tree (plus the read-only external worktree root) and writes only `state/` and Runes.
- **`git-sync` is safe by default.** It will not force, reset, or discard; a diverged branch is
  reported, not fixed.
- **Prune is opt-in and backup-gated.** `BROKK_MEMORY_PRUNE=0` is the default; a failed backup
  skips pruning entirely.

## 9. Maintaining this

- Add or change a job → update §3, `config/cron.yaml`, and the four-inputs table in §3.1 if the
  briefing's sources change.
- Change the ledger format or chaining → update §4 and the verify snippet in §4.6 in lockstep;
  the chain must remain reproducible.
- Change scheduler state file names → update §1.2 and the smoke commands in §7.
- Keep the observer's source list in §3.2 aligned with `bin/time/nornir-job-observer.sh`; the plan-23
  read-only law is non-negotiable.

### The realm default is `wayof` again, and the realm's secrets live with it (2026-09-12)

The stale multi-tenant name `way-of` was still the hardcoded fallback in the
Nornir jobs (`REALM="${REALM:-way-of}"`), so a job whose realm was not supplied
looked in a directory the platform had already retired — and the operator's real
`svartalfaheim/way-of/.env.realm` lived there, so it worked by accident while the
directory was the wrong one. Both now say `wayof`, the company container named in
`svartalfaheim/README.md`.

Realm secrets are read from `svartalfaheim/<realm>/.env.realm` (active realm, or
`BROKK_REALM`). The tracked file is `.env.realm.example`; the real one is ignored
(`.gitignore`: `svartalfaheim/*/.env*`, with `!*.example` so templates stay
tracked). The full how-to for a company's secrets — realm-level and per-venture —
is `svartalfaheim/wayof/SECRETS.md`.

### 3.11 The rollover backstop (`bin/time/nornir-job-asken-handoff.sh`, 04:00, added 2026-09-27)

The handoff (`asken trigger`) is automatic at the moment a surface calls it (the
OpenCode plugin, the Zed task); this job is the **backstop**, so a session that
died without a reporter still leaves a fresh `HANDOFF.md` behind. It is
best-effort and always exits 0 — a missing `asken` on PATH is a `skip`, never a
failure.

| Reads | Writes |
|---|---|
| `$ASKEN_REPOS` (colon- or space-separated, default `$BROKK_HOME`) · each repo's `.asken/` state | each repo's `HANDOFF.md` + `.asken/handoff.json` · Rune `nornir / asken.handoff` |

- Only a repository that carries a `.asken/` state is handed off (or **every**
  listed repository when `ASKEN_INIT_ALL` is set); `ASKEN_BIN` overrides the
  executable, else `command -v asken`.
- Runs `asken trigger --force --repo <repo> --quiet`, so the refresh is
  unconditional; the Anchor sync is time-bounded inside `asken` and skipped when
  Anchor is down, so the job never blocks and the roll still mirrors when it can.
- Emits one TOON row per repository (`repo,head,acted`), then carves the Rune.

---

## 1.2 The schedule shapes (2026-10-28, plan 140)

A row's first token is a **shape**, and the shape decides BOTH what fires and which stamp it writes. The
stamp is what stops a 45 s loop from firing the same row twice, so a shape without its own stamp key is a row
that either never fires or fires every tick.

| shape | fires | stamp key | since |
|---|---|---|---|
| `HH:MM` | once a day, at that minute | `<date>` | always |
| `@daily` | 00:00, once a day | `<date>` | 2026-10-28 |
| `@hourly` | the top of every hour | `<date>T<HH>` | 2026-10-28 |
| `@hourly:MM` | minute `MM` of every hour | `<date>T<HH>` | 2026-10-28 |

- **The role gate parses before or after a shape** (`@heart @hourly:00 …`, `@hourly:00 @heart …`), because
  the token is identified by what it IS (`is_role`), never by its position. The 2026-09-24 fault was a
  position guess; this is the same lesson applied to shapes.
- **One parser, two callers.** `parse_line` · `is_role` · `at_valid` live in the script and are `export -f`'d,
  so the loop and the **start-time warning** agree. Two parsers is how a row goes declared-but-dead.
- **An unreadable shape is named, not skipped.** At start: `cron: WARNING — N line(s) carry a schedule shape
  Nornir does not understand, and will NOT fire:` with the lines under it. During the run it is recorded in
  `state/.cron-invalid`, which `--status` reports as `invalid=<n>`.
- **Fields are taken by expansion** (`${p%%"$TAB"*}`), never by `IFS=<tab> read`: on this seat `read` put a
  whole line in the first field, and a parser that can eat a row without saying so cannot be trusted.
- **Two test hooks** exist for exactly one reason — proving the schedule without waiting an hour:
  `BROKK_CRON_TICK` (loop sleep, default 45) and `BROKK_CRON_ONCE=1` (one pass, then exit). The proof is
  `.agents/tests/nornir-schedule-shapes.test.sh` (16 assertions, fake `date`).

**Deliberately not added:** `*/N`, ranges, calendars. Nornir's value is that the whole schedule is legible in
a minute; a general cron grammar costs that and buys an hour-shaped need nothing here has.

## Appended 2026-11-06 — a smithy's row is generated, never typed

Nornir's schedule is still one file, `$YMIR_HOME/config/cron.yaml`, read at start by one
parser. What changed is **who writes one class of row**.

A Smíðja started by the clock declares it in its own config (`trigger: mode: cron`), and
`bin/time/event-trigger.sh --install-cron` derives the row from that config into a **managed
block at the end of `cron.yaml`**, between `# >>> event-trigger` and `# <<< event-trigger`.

```
nornir_smithy_rows[4]{rule,why}:
  "the block is rewritten, nothing else is touched","the operator's own rows are never reordered, and a second run is byte-identical (idempotent)"
  "a withdrawn trigger withdraws its row","a schedule that keeps firing after it was turned off is the failure this exists to prevent"
  "the shape is HH:MM or @hourly:MM only","a monthly expression is refused by name rather than installed as a row that never fires"
  "no role, no row","an ungated row runs on every seat of every machine — `trigger.role` is required for `mode: cron`"
```
The scheduler is unchanged: same parser, same stamps, same role gate. Restart it after an
install (`bin/time/nornir-cron-start.sh --stop` then again) — it reads the file at start.
