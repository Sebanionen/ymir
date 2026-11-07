## agents · unversioned · 2026-11-06 — a worker waiting on the lock is not an unseated errand

**Measured this night, third face of the same dispatcher fault.** The rail serves **one resident model**
(`--models-max 1`, enforced per process by `bin/model/local-model-lock.sh` with `concurrency=1`), so a second errand on
this box does not start: its launcher is `flock -w 1800 … bash -c pi …`, and it stands in its worktree waiting for the
first errand to release the lock.

`bin/seat/seat-prove.sh` looks for an **agent**, gives it 25 seconds, and finds none — because the process standing there
is `flock`, not `pi`. The spawn then printed:

```
seat-unproven: the launch produced NO agent … The errand is not seated; do not steer it.
error: <id> is NOT seated — do not steer pane …
exit 3
```

Measured at exactly that moment: `2086134` was alive, cwd `/home/heimdall/ymir/.yggdrasil/skuld-one-surface`, queued behind
`1305131` (a `pi` in `sindri-mw5ndywa` holding the lock). **A live worker was reported as a dead one**, and the operator
was told not to steer the errand that was about to begin — which is the worst possible advice, because the correct action
was to wait.

**The fix names the truth instead of guessing.** Before declaring UNPROVEN, the spawn asks the machine a cheap question:
*is any process standing in this worktree, waiting on the model lock?* If yes it reports

```
seat[1]{id,state,pane,pids,why}:  "<id>","QUEUED","<pane>","<pids>","waiting on the local-model lock — one resident model; it starts when the lock frees"
seat-queued: the worker is ALIVE and waiting for the model lock — do not treat it as dead, and do not relaunch it.
```

and exits **0**, because nothing is wrong. UNPROVEN keeps its meaning: nothing stands in that worktree at all.

**Why this is not a nicety.** With `concurrency=1` the second errand is the *ordinary* case on a working box — a counsellor
dispatching two errands at once will always hit it. A gate that calls the queue a failure teaches the operator to relaunch
what is already running, and two workers in one worktree is how a branch is corrupted.

**Proof to run when the lock is contended:** dispatch two errands; the second prints `QUEUED` with the waiting pid and
exits 0, and when the lock frees the same worker starts with no relaunch. With nothing standing in the worktree, the
spawn still prints `UNPROVEN` and still exits 3.

## CHANGE LOG

- 2026-11-06 · `lock_waiters` probe added; a queued worker reports `QUEUED` (exit 0) instead of `UNPROVEN` (exit 3);
  UNPROVEN now means what it says.

- 2026-11-06 · the probe's first cut searched the cmdline for `local-model-lock` (the *script's* name) and found nothing,
  because a waiting worker's cmdline carries the **lock's** name, `local-model.lock`. Corrected to
  `local-model[.-]lock` before the branch was offered; recorded here rather than edited away, because the first cut would
  have shipped a probe that could never see a queue.
