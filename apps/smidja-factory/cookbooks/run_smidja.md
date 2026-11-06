# Run smidja

Run a workflow and report on it. **You run and observe — you never step into the process or do the work yourself.**

## Step 0 — translate the request

**Read [how_to_prompt_for_the_eng.md](how_to_prompt_for_the_eng.md) before you launch anything.** The prompt you pass is read by every agent in the chain, so it gets written deliberately: same intent, sharper words, verified paths, and a stated "done means". That cookbook is the whole procedure; this one starts once you have the prompt.

## The orchestrator's posture

The smidja is the worker. Your job is to launch it, watch the trace, and tell the engineer what happened. Do not read the agent's target files and "help", do not fix the code an agent was supposed to fix, do not edit an envelope. If a run fails, report the failing phase and its violations — the fix is a config, prompt, or smidja change, made deliberately, and then a re-run.

## Launch

Which chain to launch is decided in `how_to_prompt_for_the_eng.md`, and the short version is: **the smidja the engineer named, or else the most complete composed chain the work justifies — never a single-agent one.** Read `ls smidja/smidja_*.py` and the `Phases:` line in each docstring to see what this repo has; the names below are shape, not a menu.

```bash
uv run smidja/<end-to-end-chain>.py "add a /health endpoint"
uv run smidja/<plan-build-verify-chain>.py requests/health.md
uv run smidja/<build-first-chain>.py "implement the plan" --smidja-id a1b2c3d4
uv run smidja/<recon-chain>.py "where is auth handled" --config path/to/other.config.yaml
```

The prompt is inline text or a file path. Launch in the background so you can poll while it works; the `smidja_id` is printed on startup — capture it, everything else keys off it.

**A manual run needs nothing declared.** With no `trigger:` block (or `trigger.mode: manual`) the only way this smithy starts is a person typing the command above — which is the default, on purpose. The clock and events reach the same chain through one door, `bin/time/event-trigger.sh`, which reads the config's `trigger:` block; see the Triggers section of [create_config.md](create_config.md). A run started that way is detached and logs to `state/event-trigger/<stamp>-<config>.log`, and its `smidja_id` appears in that log and in the trace like any other run.

### Listen for the roster

The chain says *what runs*; the config says *who runs it*. **If the engineer references a roster, a config, or a model tier, pass it — do not fall through to the default.**

```bash
just rosters                            # every roster on disk, and the model each agent runs
```

That prints the path to pass and who is in it, in one read:

```
smidja/smidja_smidja_config/smidja.config.yaml
    planner     fireworks/accounts/fireworks/models/kimi-k3
    builder     google/gemini-3.6-flash (inherited)
smidja/smidja_smidja_config/smidja.frontier.config.yaml
    planner     anthropic/claude-opus-5
```

Read those from disk every time. Rosters are the engineer's to add, rename, and retune, so a name you remember from a doc is a guess.

They will rarely say `--config`. Treat any of these as naming a roster, then resolve it to a file:

| What they say | What it means |
|---|---|
| "run it on the frontier config", "use the frontier roster" | the roster file whose name matches |
| "run this with the big models", "use the sota roster" | the non-default roster — confirm which if there is more than one. Each config's header comment lists the names it answers to, so `head -3` on the file settles it |
| "have opus plan this one" | a roster whose planner is that model; if none exists, say so rather than editing the config mid-request |
| nothing about models at all | the default, `smidja/smidja_smidja_config/smidja.config.yaml` |

`--config` takes the path directly; the justfile recipes read `SMIDJA_CONFIG` instead:

```bash
uv run smidja/<chain>.py "<prompt>" --config smidja/smidja_smidja_config/smidja.frontier.config.yaml
SMIDJA_CONFIG=smidja/smidja_smidja_config/smidja.frontier.config.yaml just <recipe> "<prompt>"
```

Two things that bite:

- **Never swap rosters on your own.** A different roster is a different cost and a different result. If the default's model looks wrong for the work, say so and let the engineer choose.
- **Switching rosters mid-session breaks resumption.** `agent_map.json` records the model each coding-agent session was created with, so a joined run (`--smidja-id`) whose config now names a different model starts that agent **fresh** instead of resuming its context window. That is deliberate — a bad resume is worse — but it means "plan on the frontier roster, then build on the default" costs the builder its accumulated context. Say so when you report it.

`--smidja-id` is optional on **every** smidja. Given one, the run joins that session if it exists or creates it pinned to exactly that id: same `sessions/{smidja_id}/` dirs, same `context_handoff/`, envelopes appended, and each agent resumes its existing coding-agent context window via `agent_map.json`. That is how you chain smidja — plan under one id, then build under the same id.

## Resume

A run that fails at phase three does not start again from the top — it continues at phase three. **Resume** reads the trace, finds the last phase that is green **and** whose gate passed (the checkpoint), and re-enters the chain at the phase after it.

```bash
just resume <smidja_id>                        # continue at the phase after the checkpoint
just resume <smidja_id> --from-phase build     # re-enter at a named phase instead
just resume <smidja_id> --dry-run              # print the plan and launch nothing
uv run smidja/smidja_resume.py <smidja_id>     # the script the recipe runs
```

The shape is a checkpoint discipline, the one pi-durable names (`github.com/zerwiz/pi-durable-news-agent`, `news/sweep-task.ts`): every phase commits as it closes, a restart re-enters at the phase the checkpoint names, and **finished work is never paid for twice**. Here the commit is the trace itself — the phase row, the envelope rows and the `ph.log()` payloads land together — so a phase that reads green in `smidja.db` is a phase whose work is on record.

Three things are handed forward, never recomputed:

- **the envelopes** of the committed phases (`envelopes.payload_json`, else `sessions/<id>/<agent>/envelope.json`), so the next agent receives `{{previous_envelope}}` exactly as it was;
- **the verdicts** of committed code phases — the suite's result, the committed sha, the change capture — read back from their `log` events instead of being run again;
- **each agent's session id** from `agent_map.json`, so its context window survives the restart.

A replayed phase writes no new phase row. The console and the trace say `already committed — handed forward, not re-run`, because it did not run.

### It refuses rather than guesses

The refusal vocabulary is the feature — each one is a way a resume would lie:

| Refusal | When |
|---|---|
| `no such run` | there is no session under that id (or `--from-phase` names a phase this run never recorded) |
| `nothing green to resume from` | no phase is both green and gate-passed — or the record contradicts itself: a phase that reports success while its gate failed. Resuming past that hides the failure |
| `the roster changed since this run` | an agent's model is not the model this run was started with |

**What is deliberately NOT resumed: a model switch.** `agent_map.json` records the model each session was created with. A roster edit means a different session, and a bad resume is worse than none — so the run refuses, and names the agent, the model it used and the model the roster now names. Put the old model back to continue, or accept that a changed model starts cold and run afresh.

A run whose processes are still alive is also refused, and that one is not in the table because it is not a fault in the record: stop it with `just kill <smidja_id>` first.

### `--from-phase`

`--from-phase <name>` re-enters at a named phase **of this run** — to redo a phase that passed, or to retry the broken one once its input changed. It may not jump over a phase that did not commit: a phase that is `fail`, or that never started, is never skipped. That is the same `nothing green to resume from` refusal, naming the phase it would have skipped.

## The phase contract

A phase has two different kinds of "kind", and they answer different questions.

`kind` says **who runs the block**: `engineer`, `agent` (a coding agent, typed envelope) or `code` (Python, a known command).

`contract` says **what the phase owes before it may close**. It is optional, it defaults to `ordinary`, and it is pi-durable's phase kind translated to the smithy (`github.com/zerwiz/durable-pi`, `apps/dpi-sdk/src/jobs.ts`):

| `contract` | what it does |
|---|---|
| `ordinary` (default) | the block runs and closes, exactly as before |
| `approval` | **waits for a person's decision.** No decision is not a yes: the block is never entered until `approved`, and a restart re-enters the phase and waits again |
| `repeat` | a loop that saves **one checkpoint per iteration**, so a restart re-enters at the first iteration that never committed |

```python
with run.phase(PhaseParams(name="signoff", kind="code", owner=run.engineer,
                           contract="approval",
                           description="Wait for the operator's yes before the run closes")) as ph:
    ph.log(approved_by="the operator")

with run.phase(PhaseParams(name="watch", kind="code", owner=run.engineer,
                           contract="repeat",
                           description="Poll the change feed, one checkpoint a turn")) as ph:
    for turn in ph.iterations(4):
        do_work(turn.index)
        turn.checkpoint(seen=turn.index)
```

**Deciding.** The decision is a row in the trace (`decisions`), not a side file, so the record, the resume and the visualizer read the same answer:

```bash
just decide <smidja_id> signoff approve            # or decline / cancel
just decide <smidja_id> signoff decline --note "not this week" --by "Josef"
```

A run that stops at an approval phase **exits 3** and prints the door; a run a person declined **exits 4**. Neither is the run failing at its work, which is why neither is `1`. After a decision, `just resume <smidja_id>` re-enters the phase and runs the block — once.

**Repeats.** `ph.iterations(total)` declares the loop's size and yields only the turns still owed. Each `checkpoint()` is a commit; a restart counts the committed ones and announces them (`iteration 2/4 already committed — handed forward, not re-run`). The record carries the count (`progress: {done, total}`), so `2/4` is a fact rather than an impression.

**One thing a chain author must know:** on replay the `with run.phase(...)` **block still executes**. What is answered from the record are the machinery's own doors — `ph.call()`, `ph.log()`, `quality.run_tests`, `changes.capture`, `git_helper.commit_all`, and an iteration's `checkpoint()`. So a block's own side effects (a file written by hand, an external POST) are the chain's responsibility: put them behind `ph.call()` or a `checkpoint()` if they must not happen twice.

## The run as a record

`just record <smidja_id>` prints the run the way every client should see it — **phases · steps · state · where it stopped** — from one reader (`smidja_modules/runrecord.py`). `resume` reads the same shape, so a plan and a door and a UI cannot disagree about what the run was.

```bash
just record <smidja_id>             # the run · phases · the steps that stopped it
just record <smidja_id> --as-steps  # every step of every phase
just record <smidja_id> --json      # the whole record, for a UI or a test
```

The default shows the phases that did **not** finish, with the last twenty steps of each
and an honest count of what it left out — a failed agent phase carries 167 events on the
oldest trace on this machine, and the finished ones are not why the door is open.

The statuses are honest, not decorative: `running` only while a process is alive, `interrupted` when the record says `running` and nothing is (`interrupted` is the word a SIGKILL leaves behind), `waiting` for an approval phase that owes a decision, `completed`, `failed`, `declined`. Where the trace is silent the record prints the absence rather than a guess.

Proof that it holds under a real kill: `apps/smidja-factory/tests/test_recovery.py` SIGKILLs a running chain mid-phase, restarts it with **no client attached**, and asserts it re-enters at the checkpoint, hands the committed envelope forward from the trace (the envelope file is deleted first), never re-runs a committed phase's work — counted by a marker line per execution — and refuses to let an unsigned approval phase pass.

## Observe

The trace db is `smidja/smidja_data/smidja.db`. It is WAL, so reads never block the running writers — poll it as often as you like.

```bash
# where the run stands
sqlite3 smidja/smidja_data/smidja.db \
  "select seq, name, kind, owner, status, attempt from phases where smidja_id='a1b2c3d4' order by seq;"

# the live tail — cursor on rowid, same query the visualizer polls
sqlite3 smidja/smidja_data/smidja.db \
  "select rowid, type, name, started_at from events where smidja_id='a1b2c3d4' and rowid > 0 order by rowid limit 50;"

# why a phase failed
sqlite3 smidja/smidja_data/smidja.db \
  "select attempt, gate, passed, checks_json from gate_results where smidja_id='a1b2c3d4';"

# session-level status
sqlite3 smidja/smidja_data/smidja.db \
  "select smidja_id, request, status, total_tokens from sessions order by started_at desc limit 5;"

# what an agent actually did, slowest tool calls first
sqlite3 smidja/smidja_data/smidja.db \
  "select name, tokens, started_at, ended_at from events
   where smidja_id='a1b2c3d4' and type='tool_call' order by ended_at desc limit 20;"
```

Poll on a cursor: keep the highest `rowid` you have seen and query `where rowid > ?`. Don't re-read the whole table each pass.

`tool_call` rows carry a real span, so durations come off the columns — see `references/observability.md` for which fields each event type populates.

The smidja also narrates to stdout, and every line it prints is written to the db as a `log` event — terminal and swim lane tell the same story by construction, so tailing the background process is a valid second view rather than a competing source of truth.

Files are the raw record if you need more than the db shows: `smidja/smidja_data/sessions/{smidja_id}/{agent}/raw_output.jsonl` (full coding-agent stream), `envelope.json` (the parsed final response), `prompts/` (exactly what was sent), and `context_handoff/` (what agents wrote for each other).

## When a run is stuck

A hung coding agent produces no events at all, so the trace goes quiet rather than red. Read it in this order:

```bash
just phases <smidja_id>     # which phase is still `running`
just procs <smidja_id>      # what that phase is actually running, with pids
just kill <smidja_id>       # stop it — children first, then the workflow
```

`processes` rows with `ended_at IS NULL` are the live ones. If `procs` shows a pi child but the phase has produced no `tool_call` events and its `raw_output.jsonl` is empty, the agent never got started properly — check the model resolves and that nothing is blocking the subprocess, rather than waiting it out. `just kill` verifies each pid still matches the command that was recorded before signalling, because pids get recycled.

A killed run marks itself `fail` and closes its process rows, so the trace never claims work is in flight that is already dead.

## Report

Tell the engineer, in order: which chain and which roster you launched (name the config whenever it was not the default), which phase is running now (or which failed), phase statuses in sequence, and for a failure the gate violations or the error verbatim. Remember **every phase defaults to `fail`** — a phase showing `fail` may simply never have completed; `queued` means it never started. Don't dress up a partial run as a success.

For a visual live view, the visualizer app in the skill (`just obs`, or tmux sessions viz-api :4600 + viz-ui :4601) polls this same db — sessions as cards, runs as swim lanes, phases and tool calls drill-in. The sqlite queries above remain the headless equivalent.
