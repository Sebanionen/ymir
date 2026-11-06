## smidja · unversioned · 2026-11-06 — a run that fails at phase three now continues at phase three

### Why
`--smidja-id` joined a session and each agent resumed its own context window, but the
**chain** always started at the top: a run that died at phase three paid for phase one
and two again on the next attempt, and its committed work was re-executed or lost. The
audit of the smithy named it (`no resume from the last green phase — an out-of-loop run
that dies at phase three costs the whole run`), and the operator's brief was to adopt
the checkpoint discipline a durable agent already proves.

- **The shape is taken from pi-durable** (`github.com/zerwiz/pi-durable-news-agent`,
  `apps/dna-server-api/src/news/sweep-task.ts`): a run is a sequence of named phases, every
  phase commits a checkpoint as it closes, and a restart re-enters **at the phase the
  checkpoint names** — never at the top, never past a phase that did not commit. There the
  checkpoint is `{ phase, ...that phase's work }` committed in one transaction with its
  effects; here the commit is the trace itself — the phase row, the envelope rows and the
  `ph.log()` payloads land together in `smidja.db`/JSONL as the phase closes.
- **New door:** `smidja resume <run-id> [--from-phase <name>]` (`apps/smidja/smidja_resume.py`,
  or `just resume <id>`). It reads the trace, takes the last phase that is green **and**
  whose gate passed as the checkpoint, and re-enters at the phase after it — the phase
  that failed.
- **Finished work is handed forward, not repurchased:** the stored envelopes become
  `{{previous_envelope}}`; a code phase's verdict (the suite's result, the committed sha,
  the change capture) is read back from its `log` event; each agent's coding-agent session
  id comes from `agent_map.json`, so its context window survives.
- **Replay is a phase flag, not a chain edit.** `runner.Run.phase()` returns a replayed
  handle for a committed phase (no phase row, no agent, `ph.call()` answers from the
  record); `quality.run_tests`/`run_quality`, `changes.capture` and
  `git_helper.commit_all` consult `run.replaying`, so every chain — including one already
  stamped into a user's repo — resumes without being rewritten. `git_helper` is bound to
  its run because a commit phase calls it with no run in hand.
- **Three refusals, and the vocabulary is the feature:** `no such run`,
  `nothing green to resume from`, `the roster changed since this run`. A phase that reports
  success while its gate failed is refused by the second — resuming past it hides the
  failure. A roster edit is refused by the third: `agent_map.json` records the model each
  session was created with, a changed model means a fresh session, and a bad resume is
  worse than none. A run whose recorded process is still alive is blocked separately
  (`ResumeBusy`) rather than answered from the record.

### Proved
`python3 -m unittest discover -s apps/smidja/tests` — 11 tests against a real `Tracer`
trace in a temp dir: resume after a passing phase continues at the next one; the failed
phase is where the run re-enters; a failed gate refuses; nothing green refuses;
`--from-phase` may not skip a red phase; a changed roster refuses; a replayed agent phase
hands its envelope forward and spawns nothing; a replayed test phase returns the recorded
verdict without writing an artifact; a replayed commit returns the recorded sha in a
directory that is not even a git repository.

End to end against a synthetic trace: `uv run apps/smidja/smidja_resume.py --config … --dry-run run0001`
printed `checkpoint plan (seq 2)` / `re-enter at build` / `handed forward request, plan`,
and the two refusal roads exited 2 with their reason.

### Files
- `apps/smidja/smidja_modules/resume.py` (new) — the policy: trace reader, checkpoint,
  replay set, the three refusals, `ResumeBusy`.
- `apps/smidja/smidja_resume.py` (new) — the door: prints the plan, launches the chain with
  `SMIDJA_RESUME_FROM`, launches nothing under `--dry-run`.
- `apps/smidja/smidja_modules/session.py` — `ensure()` arms the resume from
  `SMIDJA_RESUME_FROM` and exits 2 on a refusal before any agent spawns.
- `apps/smidja/smidja_modules/runner.py` — `phase()` splits into `_live`/`_replayed`,
  `arm_resume`, `replaying`, and a `PhaseHandle` that replays a committed phase.
- `apps/smidja/smidja_modules/{quality,changes,git_helper}.py` — replay-aware blocks.
- `apps/smidja/smidja_modules/data_types.py` — `ChangeSet.recorded_file_count`, so a
  replayed capture does not look empty.
- `apps/smidja/tests/test_resume.py` (new) — the suite above.
- `apps/smidja-factory/templates/smidja/**`, `apps/smidja-factory/templates/justfile`,
  `justfile` — the same runtime and the `resume` recipe for a stamped repo.
- `apps/smidja-factory/cookbooks/run_smidja.md` — the **Resume** section: the verb, the
  three refusals, and what is deliberately not resumed (a model switch).

## CHANGE LOG

- **2026-11-06** — changelog section added at the merge so RULES/46 can read it.
