## smidja · unversioned · 2026-11-05 — the phase records its context, and a pressed phase is never green

### Why

The audit found the smithy had a trace nobody could read in one place, and a
context number nobody recorded. Two facts, both load-bearing, both absent:

**A run could not be read in one row per phase.** `just phases` printed status and
nothing else; `just tail` printed events; the visualizer drew lanes. An operator
asking *"which agent ran on which model, and how full was its window when it
stopped"* had to join three sources by hand — and the model a phase actually ran
on (the fallback, not the roster's intent) was only in an event payload.

**A phase could fill its window and still report `success`.** The dispatcher knew
the occupancy (`agent_sessions.context_tokens`) and the ceiling
(`context_window`), the banner printed tokens and cost, and nothing anywhere said
"this phase ended at 81% of its window". A run that pressed its context was green
in the database, green in the banner and green in `$?`. That is the exact false
green `finish()` was built to prevent, one column over.

### The mends

| mend | where |
|---|---|
| one row per phase — model, thinking, tools, tokens, window, percent, verdict | `apps/smidja/smidja_trace.py` (`just trace <id>`) |
| a context receipt written onto every agent phase's `agent_end`: `input`, `cache_read`, `output`, `window`, `percent`, `verdict`, `pressed` | `smidja_modules/context.py`, `agents.py` |
| the window from the house's own doors — pi's catalog, then `bin/model/catalog.sh`, then `bin/seat/core-four.sh`, **never a table** | `smidja_modules/context.py::window_for` |
| >= 75% of the window (or a truncated turn) → phase status `context-pressed`, banner `◐`, session row `context-pressed`, exit non-zero | `runner.py::finish`, `console.py`, `tracer.py::session_finish` |
| the four verdict words are `bin/seat/context.sh`'s own, with two honest empties (`window unknown`, `no usage recorded`) | `smidja_modules/context.py`, asserted by a drift test that skips cleanly where the door is absent |
| new smidja files were silently gitignored — `apps/smidja/` was a blanket ignore while 34 smithy files are tracked | `.gitignore` (line 174 removed; `smidja_data/` + `smidja.db*` keep the runtime out) |

### Proof

Three tests, run where the smithy runs:

```bash
uv run --with pydantic --with pyyaml --with rich --with python-dotenv \
  python -m unittest tests.test_smidja_trace -v
```

- a trace prints the promised columns, from the records a run actually writes;
- a phase at 80% of a 100k window yields `near the window — compact now`, `pressed`,
  and `finish()` settles `context-pressed` in the session row and exits 1;
- a run with **no usage rows** prints the table with `—` in the empty cells and does
  not crash — and does not call it green.

Against the real ledger (`$YMIR_HOME/smidja/smidja.db`), the verb reads the two
surviving runs and answers honestly: `dae6d893`'s build carried no usage at all
(`no usage recorded`), `8f110045`'s ended at 105,181 of 262,144 (`40.1`, `room to
work`). Neither is dressed as a success it never was.

### Files
- `apps/smidja/smidja_modules/context.py` (new)
- `apps/smidja/smidja_trace.py` (new)
- `apps/smidja/smidja_modules/{agents,runner,console,tracer,data_types,agent_pi,agent_opencode}.py`
- `apps/smidja-factory/AGENTS.md` (hard rule 11)
- `apps/smidja-factory/cookbooks/run_smidja.md` (Trace section · `context-pressed` in Report)
- `apps/smidja-factory/skills/smidja-launcher/SKILL.md` (the `trace` verb, rule 5)
- `justfile` (`just trace <smidja_id>`)
- `tests/test_smidja_trace.py` (new)
- `.gitignore` (the blanket `apps/smidja/` ignore removed)
- `docs/features/smidja-and-volundr.md` + its catalogue fragment
- `docs/fixes/smidja/unversioned-2026-11-05-the-phase-records-its-context.md`

### Still owed
- **The launcher itself.** `scripts/smidja` is not in this repo — it belongs to the
  `~/command` provenance repo, where the `smidja-launcher` skill generates it. The
  verb is written into that skill's command list and shipped here as
  `apps/smidja/smidja_trace.py` + `just trace`; the launcher picks it up on its next
  regen. Saying "added to scripts/smidja" would be a claim about a file this tree
  does not hold.
- **A pressed run is visible in the visualizer.** The UI reads phase status from the
  `phases` table, so `context-pressed` renders as its own status word — but the
  colour scale has no entry for it yet; it falls back to the neutral status colour.
- **`input`/`cache_read`/`output` for runs recorded before this change**: the trace
  falls back to `raw_output.jsonl`'s last valid assistant turn, so the numbers are
  real, but they are the *file's* last turn rather than the phase's receipt.
