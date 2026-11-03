# Runbook — the runtime: a pinned checkout, one deploy verb, a ward

The services Ymir keeps running must execute **a commit**, never a working tree. A checkout that agents switch
branches in is not a runtime: a `git checkout` changes the code your scheduler, your memory bridge and your
watchers are running, with no approval and no restart.

## The shape

```
runtime[4]{piece,what}
  "the checkout","a clone (default ~/ymir-runtime) that only ever stands on your default branch"
  "the units","the long-running services point at that clone — never at the tree you work in"
  "the door","bin/engine/runtime-deploy.sh moves it, installs its dependencies, restarts and proves"
  "the ward","bin/gates/guards/runtime-pinned-guard.sh fails when a unit names a working tree"
```

## Commands

```bash
bin/engine/runtime-deploy.sh --check    # what the units run, against origin/main — changes nothing
bin/engine/runtime-deploy.sh            # move · install deps · restart · prove · print the commit
bin/gates/guards/runtime-pinned-guard.sh check
```

`--check` prints `deployed <running> <merged>` or `STALE`, and exits non-zero when they differ. A deploy proves
each unit **by its own state**: a long-running service must be `active/running`, and a `oneshot` that exits 0 is
`inactive/dead` — correct, not a failure.

## Configuration

`$YMIR_HOME/config/runtime.env`:

```
YMIR_RUNTIME_DIR="$HOME/ymir-runtime"
YMIR_RUNTIME_BRANCH="main"
```

Read by the deploy door, the ward, and the harness installers, so the extensions an agent loads and the commit a
deploy proved are the same one.

## What goes wrong

- **A fresh clone has no `node_modules`.** Node-based tools die with `Cannot find package '…'`. The deploy installs
  the closure (`npm ci --omit=dev`); if that fails, run it in the checkout by hand.
- **A unit drifts back to the working tree.** Something re-rendered it. Run the ward, then the deploy; if it
  recurs, find the renderer rather than editing the unit twice.
- **A unit runs a shell script with the wrong interpreter** (`python3` on a `bash` file). Compare `ExecStart=` with
  the file's shebang.

## Why not containers

A container bind-mounting the same working tree inherits the same drift. Containers answer *isolation of
untrusted code*; version discipline is a checkout problem. See `RULES/02` §7 and `RULES/05`.
