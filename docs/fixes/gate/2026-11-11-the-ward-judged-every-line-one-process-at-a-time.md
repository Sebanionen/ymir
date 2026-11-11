## gate · 0.2.0 · 2026-11-11 — the ward that judged every changed line one process at a time

### Why

`bin/gates/guards/pkill-guard.sh --check` judged the push range by running
`judge_line` once per changed line, and `judge_line` spawns four to five processes
(`printf`, `grep`, `sed`). A 600-line range therefore cost about twenty-five seconds.
Measured on 2026-11-11 while trying to push this branch: three worktrees ran the ward at
the same moment, each push sat with **no output at all**, and the gate looked hung rather
than slow. Two of those pushes had to be killed.

The second fault on the same path: `refs="$(cat 2>/dev/null || true)"` read inherited
stdin. Run inside `$( … )` from `bin/gates/guards.sh`, stdin is whatever the caller held
open — a hook pipe, a pane, a terminal — and `cat` waits for an EOF that never comes.

Neither fault could ever report a wrong verdict, so no finding was missed. What they cost
was the operator's trust in the gate: a push that prints nothing for three minutes reads
as a broken house, not a careful one.

### The fix

- **Filter before judging.** One `grep` for the blanket-kill pattern over the added lines,
  then `judge_line` only on what it found. Lines that name no `pkill`/`killall` cannot
  violate the rule, so they cost nothing. The range now judges in 0.7s.
- **Never wait on a terminal.** The refs are read only when stdin is not a tty, and the
  read is bounded at three seconds. A real pre-push writes the refs and closes the pipe,
  so it returns at once; a guard that inherits a pane returns instead of blocking it.

The verdicts are unchanged: `--scan` still reports `invocations: 0` on this tree and still
classifies a mention as a mention. The escape (`# pkill-allowed: <why>`) and the
`YMIR_ALLOW_PKILL=1` override are untouched.

### Files

- `bin/gates/guards/pkill-guard.sh` — the candidate filter and the bounded stdin read
