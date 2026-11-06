# Create Config

Generate `smidja.config.yaml` — the agent roster for a target repo.

## Generate it

```bash
uv run .claude/skills/smidja/scripts/make_config.py
```

Writes `smidja/smidja_smidja_config/smidja.config.yaml` — creating the directory if needed — with the starter agents (planner, builder, scout, reviewer, documenter) wired to the prompt files `/smidja install` stamped into `smidja/smidja_data/prompt_engineering/`. That path is the default every smidja and the justfile look for; `--config` overrides it. `make_config.py` refuses to overwrite an existing config unless you pass `--force`, so retuning an existing roster is a hand edit — see `update_config.md`.

## The rule

**One agent, one prompt, one purpose.** An entry defines who an agent *is*: its coding agent, model, thinking level, and exactly one system prompt plus one user prompt. How it gets *used* — the output type, a per-call user prompt override — lives at the smidja call site, never here.

## Schema

```yaml
defaults:
  coding_agent: pi                 # v1: pi only (claude_code is specced, stubbed until v2)
  model: google/gemini-3.6-flash   # ALWAYS provider/model-id — a bare id is ambiguous
  thinking: medium                 # off | minimal | low | medium | high | xhigh | max
  harness_engineering: []          # pi extension names
  data_dir: smidja/smidja_data          # runtime home: {data_dir}/sessions/{smidja_id}/{agent_name}/

observability:
  db: smidja/smidja_data/smidja.db        # tracer writes here; the UI polls it
  poll_ms: 500                     # visualizer live-poll cadence

agents:
  - name: planner                  # smidja scripts name agents, never models
    coding_agent: pi
    model: google/gemini-3.6-flash
    thinking: high
    color: "#a78bfa"               # optional hex — this agent's lane color in the visualizer
    purpose: Turn a request into a plan the builder can implement without asking questions.
    prompt_engineering:
      system: smidja/smidja_data/prompt_engineering/planner/system.md
      user: smidja/smidja_data/prompt_engineering/planner/user.md

  - name: scout
    thinking: high                 # unset keys fall through to defaults
    purpose: Find and report where things live; change nothing.
    prompt_engineering:
      system: smidja/smidja_data/prompt_engineering/scout/system.md
      user: smidja/smidja_data/prompt_engineering/scout/user.md
    tools:                         # optional allowlist — omit the key entirely for all tools
      - read
      - bash
```

Every agent entry merges over `defaults`, so an entry only states what differs. Pi's builtin tools are `read`, `bash`, `edit`, `write` — a read-only recon agent gets `[read, bash]`; a builder omits `tools` altogether.

## After generating

1. Each agent needs its prompt pair to exist on disk: `smidja/smidja_data/prompt_engineering/{name}/system.md` and `user.md`. `agents.validate()` fails the run at startup if either is missing.
2. Write `purpose` as one sentence and make the system prompt say the same thing — the two should not drift.
3. Validate by running the smallest smidja that names your agents; a bad entry fails fast, before anything spawns.

Full field-by-field spec, thinking-level mapping, and model resolution: `references/config.md`. Retuning an existing roster: `update_config.md`.

## Triggers — who may start this smithy

A run normally starts because a person typed a command. It may also start because the clock says so, or because something else in the house raised its hand. All three are declared in **this file** — the config a run is launched with — under one `trigger:` block, and all three go through one door:

```bash
bin/time/event-trigger.sh <event-name> [--payload FILE]     # fire an event
bin/time/event-trigger.sh --run <config>                    # what a cron row calls
bin/time/event-trigger.sh --install-cron                    # write the cron rows
bin/time/event-trigger.sh --list                            # every smithy and what may start it
```

```yaml
trigger:
  mode: manual                 # manual | cron | event
  role: dev                    # cron only, REQUIRED — which seats may run the row
  cron: "0 6 * * *"            # cron only, daily or hourly
  timezone: Europe/Stockholm   # optional; the instant is moved to the running seat's clock
  event: nightly-audit         # event only
  chain: smidja/smidja_plan_build.py   # what the trigger launches
  prompt: requests/nightly.md          # a request file, or inline text
```

**A config with no `trigger:` block is `manual`.** That is not a fallback that happens to be safe — it is the law: nothing in this house arms itself, and a missing key is never read as "run it". Every config produced by `make_config.py` states `mode: manual` explicitly so nobody has to guess which of the two it is.

**`cron` needs `role:`.** The scheduler gates a row on the seats whose roles match (`@heart`, `@forge`, `@dev`, `@hand`). An ungated row runs on *every* seat of *every* machine, so `mode: cron` without a role is a **config fault** — `--install-cron` refuses it by name rather than installing a row that fires everywhere.

**`cron` accepts only what the scheduler can express:** `M H * * *` (once a day) and `M * * * *` (minute M of every hour). A monthly or weekly expression is refused by name — installing it would produce a declared-but-dead row, the failure this house has already paid for twice.

**The schedule row is generated, never hand-written.** `--install-cron` derives it from the configs themselves, writes it inside a managed block at the end of `$YMIR_HOME/config/cron.yaml`, and is idempotent: a second run changes nothing, a withdrawn trigger has its row withdrawn, and the operator's own rows are never touched.

**A trigger that names no `chain:` or no `prompt:` is refused**, at install and at launch. A row that launches nothing is worse than no row: it looks like a schedule.

### One shape, not two

`apps/smidja-factory/templates/smidja.config.yaml` is the ONE config template — `make_config.py` copies it, `install.py` stamps it, and the trigger block above is part of it. A `factory.yaml`, a `roster.yaml` or a wrapper that repeats `roster`, `chain` or `trigger` is a **second copy of the truth**, and the two will disagree the first time one is edited. A factory-level file may **reference** this config (a path, a name, a `--config` argument); it may not restate it. `bin/time/tests/test_event_trigger.sh` fails if a second shape appears in the tree.

