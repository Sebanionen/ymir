## agents · unversioned · 2026-11-05 — the sweep turns to the pane: a dead worker is no longer read as busy

### Why

`state/<id>.status` is a CLAIM. The pane is the EVIDENCE, and nothing compared them — so on 2026-11-05 three
errands read `working` for most of a day while their panes held a shell or a crash: `weaver-hook-and-ci` at
26 h on `Tool "ymir_index" conflicts with …`, `telegram-fleet-shape` and `catalogue-the-doors-review` on an
empty prompt. The fleet looked busy and was not. `bin/agents/eindri-heartbeat.sh` can say SILENT, but it never
looks at the pane, so it cannot tell a thinking worker from an agent that no longer exists.

### The fix

`bin/agents/eindri-liveness.sh` — the ear Gná was missing (her first job is not to carry words but to notice
that there are none):

```
check [<id> …]   judge every seat this machine launched; prints seat · verdict · pane · evidence
sweep [<id> …]   judge AND correct: append `failed: … pane <id> …`, then raise ONE wake (Gná's arm)
```

The judgement, in one place:

- **herdr** — `bin/seat/herdr-agents.py --find --pane <pane> --cwd <worktree>` (the one reader). No agent in
  the pane or in the worktree, an agent in a terminal state (`done`/`blocked`/`crashed`/`exited`) with no
  terminal status line, or a pane that holds only a shell: **DEAD**, with the pane named.
- **tmux** — the window's foreground command; a shell where a harness should be is DEAD.
- **UNKNOWN**, never a false green: a machine with no herdr and no tmux cannot read the pane, and says so.
- A seat whose status is already terminal is **SKIP**ped — a closed claim is not a claim of life.

The truth is recorded where the operator reads it: `failed: the pane held no agent — <evidence> (status
claimed: …)`, and the wake is exactly once per seat through the shared delivery ledger
(`bin/agents/eindri-wake-lib.sh`), so a second sweep never repeats it.

**The sweep runs it.** `bin/agents/eindri-handoff.sh sweep` (Nornir `@dev 06:45`, and every session start)
now asks the liveness question FIRST, before delivering the report shelf: a seat whose pane is gone has no
report to deliver and never will.

### Proof

```
# (b) a deliberately killed pane is reported DEAD within one sweep, with its pane named
$ kill -9 <the pi pid in wT:p1>            # the pane keeps its shell — the zombie shape
$ herdr pane list --workspace wT
wT:p1  zerwizomar@nidavellir:~/ymir/.yggdrasil/seal-proof-shell  unknown
$ bin/agents/eindri-handoff.sh sweep
  "seal-proof-shell","DEAD","wT:p1","the pane wT:p1 holds no agent — a shell, an exit or a crash where a worker should stand"
$ tail -1 state/seal-proof-shell.status
failed: the pane held no agent — the pane wT:p1 holds no agent — a shell, an exit or a crash where a worker should stand (status claimed: working: launched 2026-11-05T00:58:35Z (heartbeat baseline))
$ grep -c seal-proof-shell state/.wake-queue
1
```

### Files

- `bin/agents/eindri-liveness.sh` (new)
- `bin/agents/eindri-handoff.sh` (the liveness cross-check runs first in `sweep`)
- `bin/seat/herdr-agents.py` (`--find`)

galdr-reread: `brokk-distro-runtime.md` (the digest's failsafe sweeps), `nornir-jobs.md` (the 06:45 row).
