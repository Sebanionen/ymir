# Skírnir's whole shelf lost its root when it moved — twenty-four scripts, one line each

**Date:** 2026-11-02 · **Component:** skirnir · **Found by:** the stop-rule timer failing every thirty minutes

## What was wrong

`skirnir-timer.service` had failed every thirty minutes since the shelf moved (`bin/assistant/` →
`systems/skirnir/services/`, plan 149, 2026-10-31), with one line in the journal:

```
systems/skirnir/services/escalation-timer.sh: line 13: HOME_R: unbound variable
```

The line before it is the cause. Every script in that shelf computed the repository root by counting
directories:

```sh
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
```

Two levels up from `bin/assistant/` is the repo root. Two levels up from `systems/skirnir/services/` is
**`systems/`** — so `$ROOT/bin/vault/hoard-lib.sh` resolved to `systems/bin/vault/hoard-lib.sh`, which does not
exist. The `|| true` on the source line swallowed the failure, `ymir_home_root` was never defined, `HOME_R`
stayed unset, and `set -u` killed the script at the first use.

**Measured:** `ROOT resolves to /home/heimdall/ymir/systems · hoard-lib there? NO · notify door there? NO`.
Twenty-four scripts in the shelf carried the identical line — so every part of Skírnir that reaches the house
through `$ROOT/bin/...` (`notify/send.sh`, `vault/hoard-lib.sh`, the runes door, the well) was reaching into a
directory that does not exist. One of them failed loudly because `set -u` was watching; the rest failed
quietly, which is worse.

## What changed

Each of the twenty-four now finds the root the way the rest of the house does — by walking up to the tree that
holds `.pi` and `RULES`, never by counting `../`:

```sh
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)"
```

A counted root is a root that breaks the next time the shelf moves, and this shelf has now moved once. The walk
cannot be broken by a move.

`mouth.sh` was left alone: its `$SCRIPT_DIR/../../systems/snotra/...` resolves correctly (two levels up is the
repo root, then into `systems/`), which is a different expression that happens to look similar.

## Measured after

```
ROOT now: <repo root>   hoard-lib reachable
escalation-timer[1]{reminded,digest}:"0","1"
  "unanswered for a day: Skírnir is built and the walls hold — approve him to stay armed?"
asks0                                  # reads the ask shelf, exit 0
escalate.sh                            # exit 0, prints nothing when there is nothing to escalate
```

The timer's first honest output in two days is a real pending item: an approval for Skírnir to stay armed has
been unanswered for over a day.

## Still owed

The unit still calls `bin/assistant/escalation-timer.sh`, the retired shim, which execs the new door and prints
a "has MOVED" line to the journal on every run. It works, and the noise is a reminder: the unit's `ExecStart`
should be repointed at `systems/skirnir/services/escalation-timer.sh` and the other shims retired the same way.
