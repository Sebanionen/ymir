# The file Windows could not check out — a stray timestamp in the repo root

**Date:** 2026-11-03 · **Component:** platforms · **Found while:** rebuilding the operator's WSL seat

## What was wrong

The repo root carried a zero-byte file named

```
Wed 2026-09-30 20:29:43 (1h 22min ago)
```

— the debris of a shell redirect whose target was a command line rather than a filename. Git
holds it without complaint. Windows cannot: the name carries a `:`, so a checkout on Windows
stops at the first file with `error: invalid path 'Wed 2026-09-30 20:29:43 (1h 22min ago)'`
and no tree is written at all.

Measured: `git clone https://github.com/zerwiz/ymir.git` on Windows (PowerShell, Git 2.55)
fetches the objects, then fails the checkout on that path. The same clone inside WSL2 succeeds,
which is why a Linux seat never saw it — and why it survived a month.

This matters because Windows is a *supported host* by the RULES/05 answer ("Windows hosts Linux
through WSL2"): an operator following `bin/host/bootstrap-windows.ps1` clones inside the distro,
but anyone reading the tree, opening a worktree, or using a Windows-side editor hits the wall
before the bootstrapper is ever reached.

## What changed

The file is removed. It was empty — 0 bytes — so no content is lost, and no code referenced it.

## Still owed

Nothing here. The lesson is the ward: a tree-wide check that every tracked path is legal on the
three hosts RULES/05 names would have caught this on the day it landed.
