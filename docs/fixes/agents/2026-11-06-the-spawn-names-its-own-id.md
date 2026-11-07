## agents · unversioned · 2026-11-06 — the spawn names its own id, so every dispatch can start again

**Measured this night, twice.** `bin/agents/einherjar-spawn.sh` line 809 read:

```bash
bash "$SCRIPT_DIR/eindri-checkpoint.sh" save "$TASK_ID" --step "seated: brief read, worktree cut" …
```

`TASK_ID` is **never assigned anywhere in the file** — it appears on that one line and nowhere else. The rest of the door
calls the errand `$ID`. Under `set -u` the expansion aborts the whole script with
`line 809: TASK_ID: unbound variable`, *after* the worktree, the meta and the launcher have already been written, so the
failure looks like a half-seated errand rather than a broken door.

**How it surfaced.** An errand was scaffolded and dispatched (`skuld-one-surface`, plan 210). The first spawn failed at
seat-prove ("no agent in pane"), the second was refused with `engine-cannot-own: a seat record already stands` — and the
road the refusal offers, *"running the existing road"*, is the road that dies on line 809. Every dispatch on every seat
takes that line, because `eindri-checkpoint.sh` arrived with the checkpoint work (28ec62bd) and is executable.

**Why the `|| true` did not save it.** It guards the *command*, not the *expansion*. `set -u` kills the shell before
`eindri-checkpoint.sh` is ever called, so the checkpoint-at-birth failed silently as an error about a variable name
instead of a note about a checkpoint.

**The fix is one word:** `$TASK_ID` → `$ID`, matching every other reference in the door. Nothing else changes: the
checkpoint still fires at birth, and the `|| true` still means a failed checkpoint never stops a spawn.

**Recorded honestly:** the same one-line change was applied to this seat's checkout so the errand could be dispatched
before this PR landed; that copy is reverted when the merge brings the fix. The PR is the delivery, not that edit.

## CHANGE LOG

- 2026-11-06 · `$TASK_ID` → `$ID` on the checkpoint-at-birth line; the door runs to its launcher again, and the unbound
  variable can no longer masquerade as a half-seated errand.
