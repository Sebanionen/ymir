## agents · unversioned · 2026-11-06 — the door asks the tree it did not empty

**Measured this night, immediately after the `TASK_ID` fix.** `bin/agents/einherjar-spawn.sh` does this on purpose, and it
is right to:

```bash
# a worktree is a copy of the project, so its .pi/extensions/ collides with the project's own
if [ -d "$WT/.pi/extensions" ]; then
  rm -rf "$WT/.pi/extensions"
  git -C "$WT" update-index --assume-unchanged .pi/extensions
fi
```

…and then it asked the launcher to **count the pins in that same now-empty worktree**:

```bash
"$PI_LAUNCHER" print "$LAUNCH_CWD" … --brief "$brief_ref"
```

`bin/seat/pi-launcher.sh` counts `$cwd/.pi/extensions/*`, finds none, and refuses with
`pi-launcher: … holds no .pi/extensions tree — a pi seat must name its extensions (RULES/13)`. So the spawn removed what
it then demanded, and **every pi dispatch died at line 855** — after the worktree, the meta and the prompt were written,
which is why it read as a half-seated errand and not as a contradiction.

**Why the worktree must lose them.** The comment at the top of the launcher block says it: pi walks up the tree and loads
the project's extensions *and* the worktree's, registering every tool twice — `Tool constellation_list conflicts with …/.yggdrasil/<id>/.pi/extensions/constellation/index.ts` — and workers were born dead while the dispatcher printed `spawned`.

**The fix separates the two jobs that were sharing one variable.** `LAUNCH_CWD` is where the worker runs, and it stays the
worktree (or `/sandbox/workspace` under Utgard). The pin list is read from the **project home** — `${PROJECT_DIR:-$ROOT}` —
which is what the seat's own settings name absolutely. One tree to stand in, one tree to name the doors.

**Proved:** the same errand that died at 855 twice now reaches its launcher, and the launcher prints the project's pins
rather than refusing. Recorded in the same branch as the `TASK_ID` fix, because a dispatcher that cannot seat a worker is
one fault with two faces.

## CHANGE LOG

- 2026-11-06 · the launcher is given `${PROJECT_DIR:-$ROOT}`; the worktree still supplies the working directory, the
  project home supplies the extensions, and the "holds no .pi/extensions tree" refusal no longer fires on a correct spawn.
