# A herdr pane is a view; a checkpoint is the record

**2026-11-06 · component: agents · `bin/agents/eindri-checkpoint.sh` · spawner + brief template**

His word: *"We also wanna have checkpoint for herdr agents"* · *"Durable agents"*.

## The fault

A herdr worker's durable facts were the branch, the worktree — and a `.status` line saying `working: launched …`.
Where the WORK stood lived only in the pane's scrollback, which dies with the pane. Measured tonight: two errands finished
with commits and no word; one died of a provider `429`; a relaunch failed because two doors disagree. In each case the
operator reconstructed the state by reading a pane.

## The door

```
eindri-checkpoint[4]{verb,what_it_does,refusal}:
  "save <id> --step … [--next …] [--state working|blocked|done]","appends one JSON line to `<state>/checkpoints/<id>.jsonl` — step, next, state, worktree, branch, commit count","a save without `--step` is refused: a checkpoint names what finished"
  "show <id>","prints the newest checkpoint (the truth is the last line, never a rewritten one)","an errand with no checkpoint says so, and names it as the fault"
  "list","every errand with its newest checkpoint","—"
  "resume <id>","prints the plan: the last step, the next step, the worktree, the commit count, and the exact re-seat command","three refusals, each named: the worktree is gone · the worktree is on a detached HEAD · no checkpoint at all"
```

**Written at birth and at every boundary.** The spawner now saves a first checkpoint (`seated: brief read, worktree cut`),
and the brief template tells the worker to save one before every phase change — so a restart reads the record, never the
scrollback.

**Append-only, like everything that remembers.** The file is JSON lines; the newest is the truth; nothing rewrites history.

## Proven

```
$ bin/agents/eindri-checkpoint.sh save smidja-checkpoint --step "resume door committed" --next "SIGKILL test"
{"id":"smidja-checkpoint","at":"2026-11-06T00:01:03Z","step":"resume door committed","next":"SIGKILL test","state":"working","worktree":"…/.yggdrasil/smidja-checkpoint","branch":"eindri/smidja-checkpoint","commits":1}
```

## Still owed

- The **SIGKILL test** for a herdr errand (the same four assertions the smithy resume errand is writing: re-enter at the last
  checkpoint, reuse committed work, prove nothing was recomputed, and refuse an `approval` step with no decision).
- The arm should read a checkpoint when it reports a silent seat, so the wake says *where the work stood*, not only that the
  seat went quiet.

## CHANGE LOG

- **2026-11-06** — the checkpoint door, the birth checkpoint, the brief rule and the fix note (Hœnir).
