# Smíðja and Völundr — the agent factory

## What it is

**Smíðja** is the smithy: a repeatable **agent+code pipeline** — a roster of agents, a
sequence of bounded phases, typed envelopes between them, retries and acceptance, and a
full trace. **Völundr** is the master smith who runs it. It turns "an errand" into a
repeatable forge.

## What you need

- Ymir installed. The visualizer + database are provisioned on first use; the DB lives in
  the home (`$YMIR_HOME/smidja/smidja.db`), not a tree.

## Do it

**The board** (by one name, wherever the UI lives):

```bash
bin/desktop/smidja-board.sh build     # install deps and build the UI
bin/desktop/smidja-board.sh start     # raise the API + UI (:8437)
bin/desktop/smidja-board.sh status
bin/desktop/smidja-board.sh stop
```

**Bootstrap + observe:**

```bash
bin/desktop/smidja-bootstrap.sh       # create the DB from the tracer schema
bin/desktop/smidja-observe.sh         # watch a run
```

The deep reference is the skill: `.agents/skills/smidja-factory/SKILL.md` — rosters,
phases, envelopes, the trace store, the visualizer.

## Notes and limits

- **Runs are traced.** Every phase leaves a record; a failure is visible, not a silent
  retry.
- **Bounded phases, typed envelopes.** A phase cannot wander — that is the point of the
  smithy.
- **The DB lives in the home**, never a tree; a packaged install and a clone share it.
- **The visualizer is `:8437`** — raised with the set (`scripts/start.sh`).

## Continue a run, read a run, and say yes to a run

A run that dies does not start again from the top. It continues at the last phase that
finished green, and the work it already paid for — the agents' reports, the test verdicts,
the commit — is handed forward instead of being bought twice.

```bash
just resume <run-id>                       # continue at the phase after the checkpoint
just resume <run-id> --from-phase build    # re-enter at a named phase instead
just resume <run-id> --dry-run             # print the plan, launch nothing
just record <run-id>                       # the run as one record: phases · state · where it stopped
just record <run-id> --as-steps            # every step of every phase
just record <run-id> --json                # the same record, whole, for a UI or a script
```

`just record` is the honest answer to "where is this run?" — every phase with its steps in
order, the checkpoint it stands on, and one sentence on where it stopped. It says
`waiting` when a run is waiting for you, and `interrupted` when the process is gone, which
is what a hard crash leaves behind.

**A phase can be made to wait for your word.** A smithy author marks a phase
`contract="approval"`, and its work does not happen until you decide:

```bash
just decide <run-id> signoff approve
just decide <run-id> signoff decline --note "not this week"
```

While it waits the run exits with code 3 and tells you the command it needs; a decline
exits 4 and the phase's work never runs. Silence is never a yes, and restarting the run
does not sneak past it.

## If it does not work

| What you see | What to do |
|---|---|
| The board is empty | `bin/desktop/smidja-bootstrap.sh` creates the DB. |
| `:8437` refuses | `bin/desktop/smidja-board.sh build`, then `start`. |
| A run stalls | `bin/desktop/smidja-observe.sh` shows the phase it stuck on. |
