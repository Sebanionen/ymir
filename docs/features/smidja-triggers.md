# Smíðja triggers — starting a smithy without a person typing

## What it is

A **smithy** (Smíðja) normally starts because you type a command. It can also start
because **the clock** says so, or because **an event** the house raised says so.

All three are declared in the same place — the smithy's own config, under one
`trigger:` block — and all three go through **one door**: `bin/time/event-trigger.sh`.

The default is `manual`. A config with no `trigger:` block is manual too, so nothing
in this house arms itself, and a key nobody wrote is never read as "run it".

## What you need

- A smithy stamped in your repo (`smidja/smidja_smidja_config/smidja.config.yaml`,
  or `apps/<name>/smidja_smidja_config/` in Ymir itself).
- A chain to launch and a request to launch it with.
- For `cron`: an existing `$YMIR_HOME/config/cron.yaml` (the shipped example runs
  until you make your own — copy it first).

## Do it

**Look at what may start every smithy on this machine:**

```bash
bin/time/event-trigger.sh --list
```

**Declare the trigger** in the smithy config:

```yaml
trigger:
  mode: event                  # manual | cron | event
  event: nightly-audit         # mode: event — the name things fire
  role: dev                    # mode: cron  — REQUIRED
  cron: "0 6 * * *"            # mode: cron  — daily or hourly
  timezone: Europe/Stockholm   # optional
  chain: apps/smidja/smidja_plan_build.py
  prompt: requests/nightly-audit.md          # a file, or inline text
```

**Fire an event:**

```bash
bin/time/event-trigger.sh nightly-audit
bin/time/event-trigger.sh nightly-audit --payload state/what-changed.json
bin/time/event-trigger.sh nightly-audit --dry-run      # show the command, launch nothing
```

Every smithy whose config names that event starts one run. The runs are detached;
each writes `state/event-trigger/<stamp>-<config>.log`, where the `smidja_id`
appears like any other run.

**Install the clock:**

```bash
bin/time/event-trigger.sh --install-cron          # writes the rows
bin/time/nornir-cron-start.sh --stop && bin/time/nornir-cron-start.sh
```

The row is **generated from the config**, never hand-written, and lives in a managed
block at the end of `$YMIR_HOME/config/cron.yaml`. Running it twice changes nothing. A
trigger you turn back to `manual` has its row withdrawn on the next run; your own rows
are never touched.

## Limits

- **A cron row must name a role.** An ungated row runs on every seat of every machine.
  `mode: cron` without `role:` is refused by name.
- **Only two cron shapes** are expressible: `M H * * *` (once a day) and `M * * * *`
  (minute M of every hour). Monthly and weekly are refused by name rather than
  installed as rows that would never fire.
- **A trigger that names no `chain:` or no `prompt:`** is refused, at install and at
  launch.
- **A `prompt:` that looks like a path must exist.** A missing request file is a
  refusal, never a sentence sent to the model.
- **One run per smithy at a time.** A second event while one is running is refused with
  the pid that holds it.
- **`timezone:` moves the instant**, not the schedule. `0 6 * * *` with `timezone: UTC`
  on a Stockholm seat writes the row as `07:00`.

## If it does not work

- `no smithy claims this event` — nothing declares that event name; the refusal lists
  the events that *are* claimed.
- `refusing to start anything while a config is misread` — one config's `trigger:`
  block is a fault (an unknown mode, a cron with no role, an event with no name).
  `--list` prints the reason in its `error` column.
- `no schedule at …` — your home has no `config/cron.yaml`; the shipped example is
  running instead. Copy it, then install again.
- The row does not fire — restart the scheduler; it reads `cron.yaml` at start.

## CHANGE LOG

- **2026-11-06** — changelog section added at the merge so RULES/46 can read it.
