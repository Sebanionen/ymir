## smidja · unversioned · 2026-11-06 — the phase contract, one run record, and a SIGKILL proof

### Why
`eindri/smidja-resume` gave the smithy a checkpoint: a run continues at its last green
phase instead of starting from the top. Three things were still missing, and they are the
same three that a durable-job runtime has to answer: **what a phase owes before it may
close**, **one record every client can render**, and **proof that a hard kill is not a
loss**. The reference is `github.com/zerwiz/durable-pi` (MIT): `apps/dpi-sdk/src/jobs.ts`
for the contract and the run document, `apps/dpi-backend/tests/recovery.test.ts` for the
kill.

- **The phase contract.** `PhaseParams.kind` already answered *who runs the block*
  (`engineer` · `agent` · `code`). A second, optional field answers *what the phase owes*:
  `contract = "ordinary" | "approval" | "repeat"`, defaulting to `ordinary`. It is
  pi-durable's phase `kind`, translated and named for the promise rather than the lane.
  - `approval` **waits for a person's decision.** The decision is a row in the trace
    (`decisions`), written by the new door `smidja decide <run-id> <phase> approve|decline`
    (`just decide`). No decision is *not* a yes: the block is never entered on silence, the
    run settles as `waiting` and exits **3** printing the door, and a decline exits **4**
    with the phase failed. A restart re-enters the phase and waits again rather than
    passing quietly — that is the whole contract.
  - `repeat` is a loop that saves **one checkpoint per iteration**:
    `for turn in ph.iterations(total)`, each `turn.checkpoint(**payload)` writing a
    `checkpoint` event. A restart counts the committed turns and yields only the ones still
    owed, so the loop is never re-run from its first turn.
- **The run as one record.** `apps/smidja/smidja_modules/runrecord.py` is now the ONLY
  reader of the trace: `load()` returns `RunRecord` — `phases` (each with its ordered
  `steps`, `gates`, `approval`, `progress`, committed `envelope` and logged verdict),
  `status`, `checkpoint`, `resume_at`, `where_stopped`, `resumed`. `resume` plans on top of
  it; `just record <id> [--json]` (`apps/smidja/smidja_record.py`) prints it; a UI renders
  it. Three clients, one shape.
- **`interrupted` is a new word, and it is the honest one.** A SIGKILL leaves
  `sessions.status = 'running'` with no process alive. The record asks the kernel (the
  `processes` rows) and reports `interrupted`; a record that kept saying `running` would
  have a resume believe in work that is already dead.
- **A phase is one row, not one row per attempt.** A resumed run re-enters the phase it
  stopped in and reopens that row (`runner._reopen_target`), so a `waiting` approval that is
  later approved shows one phase whose steps tell the whole story instead of a stale
  `waiting` row that would then be the "last phase" forever.

### Proved
`uv run --with pydantic --with pyyaml --with rich --with python-dotenv python -m unittest
discover -s apps/smidja-factory/tests` — 30 tests, all green:

- **`tests/test_recovery.py`** — the SIGKILL test, the reason this change exists. A real
  chain in a real subprocess (`tests/fixtures/recovery_chain.py`) with a real tracer db is
  killed with `SIGKILL` inside its `build` phase, then restarted **with no client
  attached**; the record is read only after the process exits. It asserts:
  (a) the restart re-enters at `build` — the checkpoint is `plan` and `build` is where it
  stopped, never after it;
  (b) the committed envelope is handed forward — the test **deletes `envelope.json`**
  before the restart, so the summary the next phase receives can only have come from the
  trace row;
  (c) no committed phase's work is recomputed — a marker line per execution, so the count
  is fact not status: the stand-in agent ran once, `build` twice (killed + re-entry), and
  the ask was logged once;
  (d) an `approval` phase with no decision does not pass — exit 3, the record says
  `waiting`, and the phase's marker file does not exist, so its block never ran. Declining
  it exits 4 and the block still never runs; approving it runs the block exactly once and
  the run completes.
- **`tests/test_runrecord.py`** — the record shape (phases, steps, state, `where_stopped`,
  the envelope, the repeat count), `interrupted` for a dead `running` run, and the approval
  contract: success with no decision is a contradiction a resume refuses
  (`nothing green to resume from — … a signature nobody gave …`), a decline is not green,
  and a decision alone is not work — the block still has to run.
- **`tests/test_resume.py`** — the 13 existing tests still pass, now reading through
  `runrecord`; `ShippedCopyTest` keeps the template and the running instance identical.

### Found on the way — the ignore rule that ate the new files
`.gitignore` carried a blanket `apps/smidja/`, written when the smithy was thought to live
in its own repo. It does not: 34 smidja files are tracked. The rule meant `runrecord.py`,
`smidja_record.py` and `smidja_decide.py` were written to the tree, invisible to
`git status`, and would have been absent from every clone — a change that "lands" and
ships nothing. Corrected in place with the reason beside it, and only the runtime data
stays ignored (`apps/smidja/smidja_data/`, `apps/smidja/smidja.db*`).

### Files
- `apps/smidja/smidja_modules/data_types.py` — `PhaseContract`, `PhaseParams.contract`,
  `ApprovalDecision`, `DecisionRecord`, `"waiting"` in `PhaseStatus`.
- `apps/smidja/smidja_modules/tracer.py` — the `decisions` table, `phases.contract` (with
  an additive migration), `decision_record`, `decision_latest`, `session_status`,
  `phase_by_name`.
- `apps/smidja/smidja_modules/runrecord.py` (new) — the one record reader.
- `apps/smidja/smidja_modules/resume.py` — replanned on `runrecord`; the approval
  contradiction refusal; `from_contract` / `approval` on the plan.
- `apps/smidja/smidja_modules/runner.py` — the approval gate (`ApprovalWaiting` exit 3,
  `ApprovalDeclined` exit 4), `Iteration`/`iterations()`/`declare_iterations`, the
  `_reopen_target` row, and a `resume` event so the record can count continuations.
- `apps/smidja/smidja_record.py`, `apps/smidja/smidja_decide.py` (new) — the two doors.
- `apps/smidja-factory/tests/{test_recovery,test_runrecord}.py`,
  `apps/smidja-factory/tests/fixtures/recovery_chain.py` (new).
- `apps/smidja-factory/templates/smidja/**`, both `justfile`s — the same runtime and the
  `record` / `decide` recipes for a stamped repo.
- `.gitignore` — the blanket `apps/smidja/` rule corrected (above).
- Books: `apps/smidja-factory/cookbooks/run_smidja.md` (§The phase contract, §The run as a
  record), `apps/smidja-factory/AGENTS.md` (hard rules 11–12), the Galdr asset
  `.agents/skills/galdr-ymirsystem/assets/smidja.md`, and the launcher/start skills.
