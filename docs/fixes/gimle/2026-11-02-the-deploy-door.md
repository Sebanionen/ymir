# The deploy door — a deployment is a version, not a copy

**Date:** 2026-11-02 · **Component:** gimle · **Found by:** watching the desk on the heart outrun the tree

## What was wrong

The Gimlé suite on the heart was deployed by **copying files**. `/home/zerwizserver/gimle` was not a git
checkout, so the newest desk logic — the membership gate, the board section, a Plane reader — existed in one
place with `.bak-` files for history. Two consequences, both real:

- the tree could be behind the running code and nothing said so;
- the running code could be behind the tree and nothing said so either.

The first was measured on 2026-11-02: `bin/gimle/desk.py` in the tree lacked everything the deployed copy had.
The second is what this change closes.

## What changed

`bin/gimle/deploy.sh` — one verb, three actions.

- **default** — move the checkout to `origin/<branch>`, link the four code files into the run directory,
  refuse to restart if any of them will not parse, restart the three units, then **prove each door by what it
  answers** (`:8487 /`, `:8489 /health`, `:8490 /health`) and by the unit's own state. A door that does not
  answer fails the deploy even when systemd says `active`.
- **`--check`** — prints `deployed <running> <merged>` or `STALE` with both commits, and exits nonzero when
  they differ. Read-only: it fetches and compares, and changes nothing.
- **`--help`**

Agnostic by construction (RULES/25): the same command acts locally where the units run, and over
`GIMLE_DESK_SSH` otherwise; a seat with neither says SKIP with the reason instead of guessing. The paths are
resolved **on the machine that runs the units**, so `$HOME` means that machine's home.

The private material is never touched: `etc/` (tokens) and `data/` (records) live in the run directory, and
the deploy only *links* code into it, so it cannot overwrite a token or a record. That is what makes the
checkout able to be a clean clone sitting beside the data.

## Why a symlink and not a copy

A copy has to be re-made correctly every time, by whoever remembers the list of files. A link makes
`git -C <checkout> reset --hard origin/main` *be* the deploy, and makes `git rev-parse HEAD` the answer to
"what is running" — from either end.

## Measured

```
check before deploy:  deployed  1476cf57  1476cf57
deploy:               deployed  1476cf57  /home/zerwizserver/gimle/src/ymir
                      gimle-desk  :8487 http=200 unit=active
                      gimle-mcp   :8489 http=200 unit=active
                      gimle-share :8490 http=200 unit=active
```

The desk renders the Book tile and the board section ("card(s) assigned") through the same deploy, so the
whole desk — record, board, places — is proved by one command.

## The fault this fixed in itself

The first draft resolved the run directory from `GIMLE_DESK_DIR` in `gimle-desktop.env`, which names the
desk's **data** shelf, not its run directory — so it looked for the checkout at
`.../gimle/desk/src/ymir` and reported "no merged-tree checkout" on a host that had one. The paths are now
resolved on the target, and the variable's meaning is written down where it is read.

## Still owed

`~/ymir` on the heart is a stale checkout (PR 218, with local modifications) — a second, older copy of the
same tree on the same machine. It is not this door's business, but it is the next drift to retire.
