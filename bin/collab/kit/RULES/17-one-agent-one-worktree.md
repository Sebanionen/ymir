# 17 — One agent, one worktree

**Added 2026-11-03** at the Allfather's word: *"use Yggdrasil for the development in the projects, so different agents will not collide
when working in the projects."*

## The rule

```
law[3]{rule,why}:
  "**an agent works in `.yggdrasil/<id>/`, never in the main tree**","two hands in one tree overwrite each other's edits, share one build directory and fight over one lock; the collision is invisible until a change vanishes"
  "**the worktree has its own branch** (`agent/<id>`), and it leaves by a pull request like every other change","isolation without a delivery is just a private copy"
  "**the worktree is removed when its pull request is merged**","a folder nobody removes is a second checkout of the same code, and the next hand will edit the wrong one"
```

## How it is used

```bash
bash scripts/worktree.sh new sebastian-c1        # .yggdrasil/sebastian-c1 on agent/sebastian-c1
cd .yggdrasil/sebastian-c1 && npm run check
# …work, commit, push, open the pull request…
bash scripts/worktree.sh done sebastian-c1       # after the merge
bash scripts/worktree.sh list
```

**What it gives you that a branch alone does not:** a separate working directory. Two agents can run `npm run check`, `npm test` and
`npm run build` at the same time without fighting over `dist/`, `node_modules/.cache` or a lock file — which is exactly the collision
that makes a parallel session look haunted.

**`node_modules` is symlinked from the main tree**, deliberately: dependencies are identical across worktrees and a second copy costs a
gigabyte for nothing. A build output is *not* shared, and must not be.

## What this does not answer

**Which agent is which.** A worktree named `sebastian-c1` is a name, not an identity; the branch's commits carry their own author. This
rule prevents collision, not confusion — and the baton is what prevents confusion.
