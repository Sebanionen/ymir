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

**Read a finished run, one row per phase:**

```bash
uv run apps/smidja/smidja_trace.py <smidja_id>     # or: just trace <smidja_id>
```

That prints the phase, the agent, the model it actually ran on, its thinking
level and tools, how many tokens stood in the window when it stopped, that
model's window, the percentage, and a verdict: `room to work`, `past the auto
threshold`, `near the window — compact now`, or `TRUNCATED`. Add `--json` for the
full receipt (`input`, `cache_read`, `output`, `window_source`).

**A full window is reported, not hidden.** A phase that ends at or above 75% of
its model's window is `context-pressed`: the banner, the session status and
`just phases` all say so, and the run exits non-zero. It is never counted as a
plain success.

The deep reference is the skill: `.agents/skills/smidja-factory/SKILL.md` — rosters,
phases, envelopes, the trace store, the visualizer.

## Notes and limits

- **Runs are traced.** Every phase leaves a record; a failure is visible, not a silent
  retry.
- **Bounded phases, typed envelopes.** A phase cannot wander — that is the point of the
  smithy.
- **The DB lives in the home**, never a tree; a packaged install and a clone share it.
- **The visualizer is `:8437`** — raised with the set (`scripts/start.sh`).

## If it does not work

| What you see | What to do |
|---|---|
| The board is empty | `bin/desktop/smidja-bootstrap.sh` creates the DB. |
| `:8437` refuses | `bin/desktop/smidja-board.sh build`, then `start`. |
| A run stalls | `bin/desktop/smidja-observe.sh` shows the phase it stuck on. |
