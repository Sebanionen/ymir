# The runtime is a pinned checkout — ten units were running whatever branch was checked out

**Date:** 2026-11-02 · **Component:** runtime · **At the Allfather's question:** *"what happends if one agent are
changing from one branch to another forr ymir systems? do we need to run some things in containers."*

## What was wrong

Ten systemd user units — `nornir` · `mimir` · `bifrost` · `mcp-gateway` · `housewatch` · `calendar-watch` ·
`garmr-brain` · `skirnir-telegram` · `skirnir-timer` · `ymir-syn-watch` — execute files from
`/home/heimdall/ymir`, the working tree every agent checks branches out in. A `git checkout` therefore changes the
code the house runs: a running script keeps its loaded text, but every subprocess it spawns reads the new branch from
disk.

Measured while writing this note: the tree stood on an **unmerged branch** (`rules/platforms-and-tiers`) — so the
scheduler, the well, the model bridge, the MCP face and the assistant were all executing unmerged code. Earlier the
same day another hand switched that tree to `feat/brokk-tool-calls` mid-session, and a `git pull --ff-only` failed
under a running agent.

## What changed

RULES/02 gains §7: *the runtime is a pinned checkout, never a working tree*, with five parts — a pinned checkout that
only stands on the default branch; one deploy verb that moves it and proves the running commit; agents always in
worktrees; **containers explicitly not the fix for this** (a container over the same mounted tree inherits the
drift); and a runtime that can report its own commit.

Plan 160 gains Phases 0a–0c: create the pinned checkout and re-point the ten units, one deploy verb (the shape
`bin/gimle/deploy.sh` already proves), and a ward that fails when a unit's `ExecStart` resolves inside a working tree.

## Why containers are the wrong reflex here

A container that bind-mounts the same tree drifts with it; a container built from an unknown commit is a slower copy
of the same mistake. Containers answer *isolation of untrusted code* (Utgard) and *a service with its own dependency
closure*. Version discipline is a checkout problem.

## Still owed

The pinned checkout itself, the ten re-pointed units, the deploy verb, and the ward. Until then the honest sentence
about this machine is: **it runs whatever branch the last agent left checked out.**
