# The home is made, and explained, on a fresh install

**Date:** 2026-11-02 · **Component:** install · **At the Allfather's word:** *"if the users are missing ymir home it
hsoule make the folders and repo if the users wanna. rigtnow it seems like he done understands on a fresch install
what ymir home are."*

## What was wrong

The installer asked **where** the home should live and recorded the answer — and then handed a new operator an empty
directory they were expected to design. Nothing said what a home *is*, what goes in it, why it is not the repo, or
that it can follow them to another machine. On a non-interactive install nothing was said at all.

## What changed

`bin/engine/home-seed.sh` — one door that answers the three questions and then lays the shelves out:

- **what** the home is (identity, memory, plans, secrets, documents, workspaces — private, never inside the code
  tree, never deleted by an update), **where** it is, and **what goes in each directory**;
- creates the thirteen directories every door in the house reads (`hodd/{identity,data,memory/daily,plans,secrets,state,docs,workspaces,reference}`, `config`, `state`);
- writes **`README.md`** in the home — plain words for someone who has just arrived, including the two rules that
  matter: keep a home repository **private**, and move it rather than delete it;
- writes **`.gitignore`** — the small list that keeps a plaintext secret out of a commit;
- offers **`git init`** when the operator wants the home in a repository (`--repo`, or a plain question), with a
  first commit, and says plainly: *push it private*.

It never deletes and never overwrites: an existing file is left exactly as it is, and a second run reports
`complete`.

## Wired in

- `bin/engine/ymir-install.sh` — `step_home` seeds the home both on the interactive path (right after the choice)
  and on `--yes`, before anything else reads it.
- `bin/agents/groa-update.sh` — an update cannot assume the home exists: `--check` reports whether the shelves are
  complete, and a real update lays them out. It never guesses a path and never overwrites.

## Measured

```
YMIR_HOME=/tmp/freshhome bin/engine/home-seed.sh --yes     → created 13 directories; wrote README.md, .gitignore
YMIR_HOME=/tmp/freshhome bin/engine/home-seed.sh --repo --yes → "initialised" + first commit
repeat run                                                 → "complete, every directory is already here"
real home, --check                                         → "complete"
```
