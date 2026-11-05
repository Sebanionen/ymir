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

## Trace

One row per phase, in sequence order, from the records the run already wrote — the
database, `raw_output.jsonl`, `envelope.json`, `prompts/`. There is no second store:

```bash
uv run apps/smidja/smidja_trace.py <smidja_id>
# or the recipe
just trace <smidja_id>
```

```
trace[3]{phase,owner,model,thinking,tools,tokens,window,percent,verdict}:
  "request","zerwiz","—","—","—","—","—","—","no usage recorded"
  "build","builder","llama-swap/qwen3.6-35b-a3b@q4_k_xl-mtp","medium","read,grep,bash,edit,write","41203","262144","15.7","room to work"
  "review","reviewer","llama-swap/qwen3.6-35b-a3b@q4_k_xl-mtp","high","read,grep","213000","262144","81.3","near the window — compact now"
```

What each column is, and where it came from:

| column | meaning |
|---|---|
| `phase` · `owner` | the phase name and the agent it ran as (`phases` table) |
| `model` | the model the phase ACTUALLY ran on — the fallback model when one was used (`agent_start` → `agent_end.context.model`) |
| `thinking` | the thinking level the phase ran at (`agent_start`) |
| `tools` | the phase's declared capability list; `all` when the roster allows every tool, `—` for an engineer or code phase that ran no agent |
| `tokens` | **occupancy**, not spend: what the last turn left in the window (input + cache read + output) |
| `window` | that model's ceiling, from the same doors the house uses — pi's model catalog, then `bin/model/catalog.sh`, then `bin/seat/core-four.sh` |
| `percent` | `tokens / window`, to one decimal |
| `verdict` | the phase's context verdict, below |

`--json` carries the parts the table has no room for: `input`, `cache_read`,
`output`, `window_source`, `last_finish`, `envelope_status`, `pressed`, and a
run-level `context_pressed`. A run whose database is not the default takes
`--db`; a sessions shelf that is not beside it takes `--data-dir`.

### The verdicts

Four words, and they are `bin/seat/context.sh`'s own — the smithy does not keep a
second vocabulary for the same fact:

| verdict | when | what to do |
|---|---|---|
| `room to work` | below 50% of the window | nothing |
| `past the auto threshold` | 50% or more, below 75% | expect a compaction; nothing yet |
| `near the window — compact now` | 75% or more (the **force** threshold) | the phase is `context-pressed` — see below |
| `TRUNCATED` | the last turn ended on the length limit | the work was cut off, not finished; re-run smaller |

Two honest empties, never greens (RULES/37 — a surface may not show what it did
not receive):

| verdict | when |
|---|---|
| `window unknown` | no door could say how large that model's window is — `tokens` is real, `percent` is `—` |
| `no usage recorded` | the phase recorded no usage at all (an engineer/code phase, or a run that died before its first turn) |

### `context-pressed`

A phase that ends at or above the force threshold is **not green**. It did its
work, but the window is what will kill the next phase — so the phase's status is
`context-pressed` in the database, the banner prints `◐ context-pressed`, the
session row says `context-pressed`, and the run exits non-zero. Never `success`:
a green that hides a full window is the false green this house has paid for twice.

## Report

Tell the engineer, in order: which chain and which roster you launched (name the config whenever it was not the default), which phase is running now (or which failed), phase statuses in sequence, and for a failure the gate violations or the error verbatim. Remember **every phase defaults to `fail`** — a phase showing `fail` may simply never have completed; `queued` means it never started. Don't dress up a partial run as a success.

**Say `context-pressed` when you see it.** A phase at or above the force threshold (75% of its window) shows as `context-pressed` in `just phases`, in the banner and in `just trace` — report it as its own outcome, with the percent and the window, never fold it into "passed". It is the single most useful line in the report: it explains the phase that fails next, and it is the reason to raise the model's window or split the work rather than blame the model.

For a visual live view, the visualizer app in the skill (`just obs`, or tmux sessions viz-api :4600 + viz-ui :4601) polls this same db — sessions as cards, runs as swim lanes, phases and tool calls drill-in. The sqlite queries above remain the headless equivalent.
