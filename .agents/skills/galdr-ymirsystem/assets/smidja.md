# Smíðja — the smithy (agent factory)

Load this when working with the smithy: installing it, configuring its roster,
running a chain, reading its trace, or wiring it into Hlidskjalf.

- **Norse:** **Smíðja** = the smithy (the workshop). Its orchestrator seat is
  **Völundr**, the master smith — *Kaia's seat inside the factory* (Kaia decides
  *what* is forged; Völundr decides *how* the smithy runs). Its trace UI is
  **Smíðja's eye**.
- **Registry:** `.agents/assets/agents/naming.md`, `docs/lore.md` §XI/§XIII.
- **Skill (adopted upstream):** `.agents/skills/smidja-factory/` (internals + cookbooks +
  references + sibling skills `smidja-launcher`, `smidja-start`,
  `smidja-instructions`, `volundr`). The **visualizer's home is the smidja repo**
  (`apps/smidja-factory/apps/visualizer` in a clone; the skill tree carries no
  copy — dropped 2026-09-17).

**Two layouts, one smithy — do not confuse them.** A *target* repo the smithy is
installed into gets the stamped `smidja/` tree (what `install.py` writes). **In
Ymir itself the instance lives at `apps/smidja/`** — it moved out of the repo root
so the smithy sits with the other apps, and its runtime data
(`apps/smidja/smidja_data/`, gitignored) may also live at `$YMIR_HOME/smidja/`,
which the runtime prefers when it exists. Every path in *this* repo points at
`apps/smidja/`. The monorepo tracks neither the factory nor the engine: the
factory is cloned from `zerwiz/smidja` into `apps/smidja-factory` by the
installer's `apps` step, and the engine is stamped into `apps/smidja` from that
clone's `templates/smidja` — exactly as `install.py` does for a target repo.

## What it is

*Agents plus code*: deterministic Python scripts own sequencing, retries, and
acceptance; coding agents (Pi) work inside bounded **phases**; typed JSON
**envelopes** carry context between them; everything streams into **SQLite** so it
can be watched. *Agent proposes, code disposes.*

## Install into a repo (idempotent)

```bash
cd <repo-root>            # e.g. $YMIR_ROOT
uv run .agents/skills/smidja-factory/scripts/install.py
```

Stamps `smidja/` (the starter smithies + `smidja_modules/`), the prompt and harness
engineering dirs, `smidja/smidja_smidja_config/smidja.config.yaml`, `.env.sample`,
`justfile`, and `.gitignore` entries. Existing files are skipped unless `--force`.

Not writable, it fails plainly: a `PermissionError` never escapes as a traceback —
the script checks the target and returns exit 1 with the reason, so a failed
stamp is legible rather than a stack of Python.

There is **no separate CLI install**: the launcher `scripts/smidja` belongs to the
`~/command` provenance repo; in Ymir use the `justfile` recipes or `uv run
smidja/smidja_*.py` directly.

## Roster & models — through pi's `models.json`

- The roster: `smidja/smidja_smidja_config/smidja.config.yaml`. `defaults.model`
  and each agent's `model:` are **`provider/id`** resolved by **pi** from
  `~/.pi/agent/models.json`. List what resolves with `pi --list-models`.
- Models come from the **hoard** (`config/agents.yaml` + per-host overlay),
  resolved by `bin/fleet/agents-config.sh resolve` → `state/agents-resolved.json`.
  The shipped config carries **empty** env-expandable placeholders:
  `${SMIDJA_LOCAL_MODEL:-}` and per-role `${SMIDJA_<ROLE>_MODEL:-}`.
  `just` loads `.env` (`set dotenv-load`). Set `SMIDJA_LOCAL_MODEL` to pick
  the backend; omit it and the roster has no model.
- Keys: the roster names cloud providers (`google`, `fireworks`, `openai`)
  → `OPENROUTER_API_KEY` / `FIREWORKS_API_KEY` / `OPENAI_API_KEY` in `.env`. A local
  llama roster needs no key.

## Run

```bash
# via justfile (repo root)
just demo                       # two cheap read-only runs (scout), end to end
just prompt "summarize this repo"
just scout "where is auth handled"
just sdlc "add a /health endpoint"
just sessions                   # last 10 runs
just phases <smidja_id>         # phase status in sequence
just tail   <smidja_id>         # live event tail
just procs  <smidja_id>         # live pids

# raw
uv run apps/smidja/smidja_prompt.py --agent scout "…"
uv run apps/smidja/smidja_scout.py "…"
```

The watch recipes use **`python3 -c`** over the SQLite db (the `sqlite3` CLI is not
installed on this machine) — do not reintroduce `sqlite3`.

## The trace

- DB: **`$YMIR_HOME/smidja/smidja.db`** (WAL; read-only readers never block a run).
  `0003-private-data-separation` moved it out of the checkout; an in-repo
  `apps/smidja/smidja_data/smidja.db` is the fallback. Created at the first run
  (`bin/desktop/smidja-bootstrap.sh`); `scripts/start.sh` resolves the same pair.
- Tables: `sessions` (`smidja_id, smidja_name, request, status, engineer,
  started_at, ended_at, total_tokens, total_cost, archived`), `phases`
  (`phase_id, smidja_id, seq, name, kind, owner, description, status, attempt,
  retries, error, …`), `events` (`event_id, smidja_id, phase_id, parent_id, type,
  name, payload_json, tokens, …`), `gate_results`, `envelopes`, `agent_sessions`,
  `processes`.

## Smíðja's eye — the trace visualizer

- **Open at `http://127.0.0.1:8437/`.** One Bun server serves both the read-only
  API (`bun:sqlite` over the trace db) **and** the built Vue UI from
  `apps/smidja-factory/apps/visualizer/dist`. A Vite dev server on `:8438` is opt-in
  (`SMIDJA_VIZ_DEV=1`) and is not needed for use.
- **The carved cloth (2026-09-13).** The default theme is **fensalir** — the
  landing page's stone/bone/bronze/blood and its three faces (Cormorant display,
  Newsreader UI, IBM Plex Mono data), cut into `src/style.css` `:root` and into the
  components' role colours (`var(--accent)`, `var(--green)`, `color-mix(…)`). The
  titlebar toggle cycles **fensalir → classic → high-contrast**; `classic` (the
  preserved deep-space look) and `high-contrast` (WCAG AAA) are deliberate
  overrides and **win when chosen** — the cloth is the default, not a cage. A
  saved `neutral` from an older build resolves to fensalir. The categorical
  palettes (event dots, agent lanes in `src/lib/events.ts`) are data, not chrome,
  and were re-cut onto the cloth while staying mutually distinct.
- `scripts/start.sh` raises it (`CMD_DB=$YMIR_HOME/smidja/smidja.db`, else the
  in-repo fallback; `PORT=8437`); `scripts/stop.sh` lowers it. Port overrides:
  `SMIDJA_VIZ_API_PORT`.
- Served under Hlidskjalf's **Sessions** gate via **Open visualizer**
  (`VITE_VISUALIZER_URL`, default `http://127.0.0.1:8437`).
- **Shared login, verified live (added 2026-09-13).** The server exposes
  `GET /api/auth`, which forwards the browser's cookie to the gate's
  `/api/session` and returns `{authed, login}`; `App.vue` shows a "Sign in" link
  (to the gate) or "ᛉ <login>" from that live answer. It **never** reads a
  session file — a token on disk would let a user look logged in when they are not.
- **The Hall door (added 2026-09-13).** `App.vue`'s topbar carries a **To the
  Hall** pill (rune Othala ᛟ, `.hall-btn`) beside the theme toggle: a new tab to
  the Óðrerir Live Hall — `http://localhost:4322` when
  `window.location.host` starts with `localhost`/`127.0.0.1`, otherwise
  `https://hall.ymir.zerwiz.org`. It is a **plain anchor, not a `/api/desktop`**
  launcher: the Hall is the landing's live board, not one of the three apps the
  gate raises. Same door in Hlidskjalf's and Sessrúmnir's chrome.
- See `docs/lore.md` §XIII.

## In Hlidskjalf (the gate API)

`apps/hlidskjalf/server` exposes the trace read-only:
`/api/smidja/health · /api/smidja/sessions · /api/smidja/sessions/:id ·
/api/smidja/decisions · /api/smidja/stats`. Four gates render it: **Sessions**,
**Trace**, **Decisions**, **Stats**. Smíðja loads on its own track and is polled
every 5s, so a finished run appears without a reload.

## The observer (Huginn) — self-contained

`bin/time/nornir-job-observer.sh` runs on the Nornir schedule (06:00). It reads **only
Ymir's own runtime** — `docs/masterplan.md`, `.agents/agents`, `.agents/memory/well`,
`workspace/memory/runes_audit.md`, **`$YMIR_HOME/smidja/smidja.db`**, and the
read-only external worktree root — and writes only `state/observer.log` + Runes.
There is **no `~/command` connection** anywhere in Ymir. Rune sources:
`ymir.orders · ymir.agents · ymir.well · ymir.runes · smidja.runs ·
yggdrasil.worktrees`. See `assets/nornir-jobs.md`.

## Smoke test

```bash
SMIDJA_LOCAL_MODEL=llama-cpp/<your-model-id> \
  uv run apps/smidja/smidja_prompt.py --agent scout \
  "Reply with a single line: which top-level directories exist in this repo. Change nothing."
```

Expected: `2/2 phases passed`, a `smidja_id`, and the DB written. Then
`just sessions` and `just phases <id>` read it, and
`curl -s localhost:8437/api/health` reports `"sessions": N`.

## Gotchas

0. **`bun` lives at `~/.bun/bin` and is often off a non-login PATH.** `scripts/start.sh`
   and `bin/desktop/smidja-board.sh` adopt it once (2026-09-23) before checking, so the gate
   API and the visualizer are not skipped on a machine that HAS bun.

1. **`sqlite3` CLI is absent** — use `python3 -c` (the justfile already does).
2. **Local models are served by the llama.cpp router `:8080`**, addressed as
   `llama-cpp/<id>`; LM Studio `:1234` may be down. Confirm with `pi --list-models`.
3. **The visualizer's local `node_modules` may be a partial bun install** — the API
   still serves the prebuilt `dist/`, so open `:8437`, not `:8438`.
4. **Never edit `apps/smidja/smidja_data/sessions/`** — it is the run record.
5. **Protected files** (`apps/smidja/smidja_modules/`, `apps/smidja/smidja_*.py`, the config)
   are enforced by `smidja_modules/permissions.py`; agents roll back unauthorized
   changes. The smithy moved from the repo root `smidja/` to `apps/smidja/`
   (Amendment C); `bin/desktop/smidja-bootstrap.sh` searches both so a stale layout cannot
   break the DB seed again.
6. New skills synthesized for the smithy are validated in Utgard (Gungnir, W0007)
   before production.

---

## Appended 2026-10-23 — what the smithy owes the surface it ships (Rule 37)

**A smith does not ship a surface that lies.** Rule 37 (this day) makes it law, and this section is Smíðja's part of
it, because every panel, export, letter and prototype the factory produces is a *surface*:

- **figures come from a receipt** — a stat, a count or a card that the factory renders must trace to a response it
  actually received; a refused or failed read renders `—` and says which read refused, never `0`;
- **diagnoses come from proof** — "down", "stopped", "empty", "none" are conclusions. A failed probe says *"could
  not read"* and names the probe (measured 2026-10-23: the Well said "bridge down" while `GET :4602/health`
  answered **200** with 167 episodes; Nornir said **STOPPED** while the runner was alive with 29 jobs);
- **a generated artefact is verified before it is called done** — a card is read back from the board, an audio file
  is decoded and heard, a letter cites its record's ids, a panel's figure is compared with the response that
  produced it. Measured the same evening: `snotra-harvest.sh speakers` wrote three WAV files of static and exited
  **0**, because nothing in it checked that the bytes were speech;
- **a fallback carries its warning on the same line as the value**, marked `cached` · `stale` · `unverified` — not
  in a footnote;
- **a clean skip is a pass** (Rule 25) — *"not tested, because X"* is the honest output; a zero is not.

Concretely for the factory's own output: a Smíðja chain that produces an app, a spec or a visualiser ends with a
**surface check** (does every number it shows come from a read?), and a run that cannot answer says so in the
trace rather than reporting success. Rule, ward and evidence: `RULES/37-a-surface-may-not-show-what-it-did-not-receive.md`.
## 2026-10-23 — the night the panel showed nothing, and the five reasons why
Measured on this seat between 19:30 and 20:30, while three agents ran and the Smíðja displayed "no agent
activity yet". Each line is a way this subsystem can be honest in its parts and useless as a whole.
Law: `RULES/36-the-run-is-visible.md`.
faults[5]{fault,measured,remedy}:
  "the smithy is not in git",".gitignore:174 `apps/smidja/`; the roster names prompt_engineering/{planner,builder}/{system,user}.md and harness_engineering/subagents.ts — NONE in git, none in the template","track it (git add -f) or the factory cannot run on any other seat; validation refuses before the first phase"
  "the teams have three names",".agents/agents/*.md (23 figures) · config/agents.yaml (figure→model) · roster.yaml (what the picker reads — absent)","one resolver, stated fallback to config/agents.yaml, `cause:` in the payload when it is empty"
  "a repo derived from a DB path","server/roster-api.ts:34 `repoRoot(dbPath)` while the DB lives in the home → /api/rosters []","SMIDJA_REPO_ROOT (default: the checkout); never derive a repo from a database"
  "two database paths","config `db: apps/smidja/smidja_data/smidja.db` vs the visualizer's $YMIR_HOME/smidja/smidja.db → a real run invisible, observe says 'absent'","the shipped config names the home's DB; every reader resolves it the same way"
  "pi refuses in a worktree","`Tool ymir_find conflicts with …/.yggdrasil/…/.pi/extensions/ymirhome.ts` — killed every builder turn (dae6d893: fail in 8.1s) and every errand","agent_pi.py starts pi with `-ne`; the run's declared extensions are added with `-e`"
**The invocation, stated once, because it is the thing people get wrong:**
# from the REPO ROOT — the config's prompt and data paths are root-relative
uv run apps/smidja/smidja_build.py <prompt.md> \
  --config apps/smidja/smidja_smidja_config/smidja.config.yaml
From `apps/` the same command resolves `apps/apps/…` and validation refuses with "prompt not found" —
which looks like a missing file and is a wrong working directory.
**Proof that it works when the three things are right** (config · cwd · `-ne`):
run 8f110045   01 request  success   0.0s
               02 build    RUNNING   builder · llama-swap/qwen3.6-35b-a3b@q4_k_xl-mtp
               35 events in $YMIR_HOME/smidja/smidja.db
### Correction, appended 2026-10-23 — the smithy is tracked; what is missing is the roster
My earlier line in this asset said the smithy is not in git. **It is:** `git ls-files apps/smidja` → 34
files, and `apps/smidja-factory` → 229. What `.gitignore:100-101` excludes is **runtime data** —
`apps/smidja/smidja_data/` and `apps/smidja.db*` — which is why the agent prompts live there: they are
run data, not repo content.
**What this seat does not have, and the docs say it must:**
docs say                          this seat
roster.yaml = THE ONE config      apps/smidja/smidja_smidja_config/ holds ONLY smidja.config.yaml
  stacks: teams                   — no `stacks:` block at all → no teams to pick → empty picker
  role_defaults: roles
  tiers: model catalog
just rosters / sdlc / sessions    `just` is NOT installed
START_SMIDJA.md (playbook)        absent
**Read before you claim:** `apps/smidja-factory/cookbooks/{run_smidja,create_config,create_smidja,
how_to_prompt_for_the_eng}.md` and `apps/smidja-factory/skills/{create-new-teams,create-new-agent,
add-or-edit-ai-models,how-to-run-agent-teams,smidja-start,smidja-launcher,smidja-instructions}/SKILL.md`.
A team is a `stacks:` block, created by interviewing the operator — never guessed, never generated as a
throwaway config.
### The books — `apps/smidja-factory/cookbooks/` and `apps/smidja-factory/skills/` (critical)
Read the matching book **before** changing the smithy: a chain, a roster, a prompt, a module, or the
invocation. They are the specification; a disagreement between a book and the tree is a ticket.
cookbooks[9]{book,what it settles}:
  "smidja_overview.md","what the smithy is: phases, envelopes, gates, the trace"
  "run_smidja.md","how to launch a run and report it — the orchestrator observes, never implements"
  "create_smidja.md","compose a new chain (the Phases: line is the contract)"
  "create_config.md","the roster/config file: agents, prompts, tools, writes, protected files"
  "update_config.md","change a roster without breaking a run"
  "update_smidja.md","change a chain safely"
  "update_modules.md","change a module (tracer, runner, gates, agents)"
  "install.md","what a fresh install needs, and what is runtime data rather than repo content"
  "how_to_prompt_for_the_eng.md","write the prompt the whole chain will read — same intent, sharper words, verified paths, a stated 'done means'"
skills[9]{skill,what it settles}:
  "smidja-start","the single exact way to put agents to work (chain · roster · models · orchestrator)"
  "smidja-launcher","raise and watch a run"
  "smidja-instructions","the operating instructions for the smithy"
  "how-to-run-agent-teams","teams in practice"
  "create-new-teams","a team IS a `stacks:` block in roster.yaml — interview the operator, never guess"
  "create-new-agent","one new role, added to role_defaults"
  "add-or-edit-ai-models","models, prompts and injection for an existing team"
  "git-ops","branch/commit/push discipline for work the smithy produces"
  "volundr","the master craftsman's own practice"
**What this seat is missing against those books** (measured 2026-10-23): no `roster.yaml` (so no
`stacks:` → no teams), `just` not installed (so no `just rosters/sdlc/sessions`), `START_SMIDJA.md`
absent. Each is a ticket; none is a reason to improvise a team.

## Appended 2026-11-06 — the smithy can be started by the clock or by an event, and it is still one door

A smithy was started by a person or not at all. It now has three ways in, and all three are
the SAME two facts: **who may start it** — `trigger:` in its own config — and **what is
launched** — its `chain:` and its `prompt:`. One door acts on both.

```
bin/time/event-trigger.sh <event-name> [--payload FILE] [--dry-run]   fire an event
bin/time/event-trigger.sh --run <config>                              what a cron row calls
bin/time/event-trigger.sh --install-cron                              write the rows
bin/time/event-trigger.sh --list                                      who may start each smithy
```

```
trigger:
  mode: manual                 # manual | cron | event — ABSENT MEANS MANUAL
  role: dev                    # cron only, REQUIRED: an ungated row runs on every seat
  cron: "0 6 * * *"            # cron only, daily (M H * * *) or hourly (M * * * *)
  timezone: Europe/Stockholm   # optional; the instant moves to the running seat's clock
  event: nightly-audit         # event only
  chain: apps/smidja/smidja_plan_build.py
  prompt: requests/nightly.md              # a file, or inline text
trigger_duties[5]{duty,why}:
  "the block lives in the smithy config, nowhere else","that is the file a run is launched with, so a trigger cannot describe a different smithy than the one that runs"
  "one reader: bin/time/event-trigger-resolve.py","two parsers of one block is how a schedule and a launcher disagree"
  "absent is manual, and the template STATES manual","a missing key read as a default is a smithy that starts by surprise"
  "cron without a role is refused","an ungated row runs on every seat of every machine (RULES/36, the 5-seat cron leak)"
  "the row is GENERATED, never hand-written","`--install-cron` writes a managed block from the configs and is idempotent; a withdrawn trigger withdraws its row"
```
**Refusals, all by name:** a mode that is not one of the three; `cron` with no expression or no
role; `event` with no event; a cron expression the scheduler cannot express (monthly/weekly);
a trigger naming no `chain:` or `prompt:`; a `prompt:` that names a path that is not there; a
second run of a smithy whose lease is still held; an event no smithy claims (the refusal lists
the events that ARE claimed).

**One shape, not two.** `apps/smidja-factory/templates/smidja.config.yaml` is the ONE config
template — `make_config.py` copies it, `install.py` stamps it, and the trigger block is part of
it. A `factory.yaml` / `roster.yaml` / wrapper that restates `roster`, `chain` or `trigger` is a
second copy of the truth; a factory-level file **references** the smithy config, it never
restates it. Proof: `bin/time/tests/test_event_trigger.sh` (42 assertions, wired as the `triggers`
gate in `bin/gates/ci-verify.sh`) — 42 because the last three prove the lease: a second run of
one smithy is refused with the pid that holds it, a dry run still answers while it is busy, and
a stale lease self-heals because the pid is the truth and the file is not.
