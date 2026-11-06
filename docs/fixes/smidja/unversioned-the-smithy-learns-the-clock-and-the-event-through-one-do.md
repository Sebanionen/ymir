## smidja · unversioned · 2026-11-06 — the smithy learns the clock and the event, through one door

### Why
A smithy could only be started by a person typing. Anything else that wanted to start one had nowhere to say so, and a cron row written by hand would have been a second place the schedule lived — the exact drift this house has paid for. The trigger is now declared in the smithy's own config, read by one resolver, and acted on by one door; the cron row is generated from the config and is idempotent.

### Files
- `bin/time/event-trigger.sh`
- `bin/time/event-trigger-resolve.py`
- `bin/time/tests/test_event_trigger.sh`
- `apps/smidja-factory/templates/smidja.config.yaml`
- `apps/smidja/smidja_smidja_config/smidja.config.yaml`
- `apps/smidja-factory/cookbooks/create_config.md`
- `apps/smidja-factory/cookbooks/run_smidja.md`
- `config/cron.yaml.example`
- `bin/gates/ci-verify.sh`
- `docs/features/smidja-triggers.md`
- `.agents/skills/galdr-ymirsystem/assets/smidja.md`
- `.agents/skills/galdr-ymirsystem/assets/nornir-jobs.md`
### What was built

```
trigger:{mode: manual|cron|event, role, cron, timezone, event, chain, prompt}
bin/time/event-trigger.sh <event> [--payload FILE] [--dry-run]   fire an event
bin/time/event-trigger.sh --run <config>                          what a cron row calls
bin/time/event-trigger.sh --install-cron [--cron-file PATH]       write the rows
bin/time/event-trigger.sh --list                                  who may start each smithy
```

- One reader (`event-trigger-resolve.py`) for the `trigger:` block, so the schedule and the
  launcher can never disagree.
- `absent` is `manual`; the shipped template states `mode: manual` explicitly so nobody has to
  guess which of the two a config is.
- `cron` requires `role:` — an ungated row runs on every seat of every machine.
- `cron` accepts only what the scheduler can express (`M H * * *`, `M * * * *`); a monthly or
  weekly expression is refused by name rather than installed dead.
- `timezone:` moves the INSTANT (asked for in both clocks via `date`), never the schedule — so
  a summer row does not fire an hour late, which an offset-at-epoch calculation would cause.
- `--install-cron` writes a managed block at the end of `$YMIR_HOME/config/cron.yaml`, is
  idempotent (a second run prints `unchanged` and writes nothing), withdraws the row of a
  trigger turned back to `manual`, and never touches the operator's own rows.
- The run is detached and leased: one run per smithy, and a second event names the pid that
  holds it.

### One shape, not two

`apps/smidja-factory/templates/smidja.config.yaml` is the only config template —
`make_config.py` copies it and `install.py` stamps it — and it now carries the `trigger:` block.
There is no second `factory.yaml`/`roster.yaml` copy of `roster`/`chain`/`trigger`; a
factory-level file references the smithy config. The test asserts it: any tracked `*.yaml`
carrying `^trigger:` outside a smithy config is a failure.

### Proof

`bin/time/tests/test_event_trigger.sh` — 39 assertions, wired as the `triggers` gate in
`bin/gates/ci-verify.sh`. The three laws, each with the refusals that give it teeth:

```
law[3]{assertion,proved_by}:
  "a config with no trigger: is manual","scanned as manual, listed as 'a person', and not started by an event"
  "an event no smithy claims is refused by name","exit 1, naming the event asked for and the events that ARE claimed"
  "--install-cron is idempotent","byte-identical after a second run, one row, printing 'unchanged'"
```

Plus: two claimants are two launches; a cron with no role is refused; a monthly expression is
refused; an unknown mode and an event with no name are named faults; a faulty config stops the
door rather than launching the healthy half; `06:00 UTC` is written as `07:00` on this seat.
