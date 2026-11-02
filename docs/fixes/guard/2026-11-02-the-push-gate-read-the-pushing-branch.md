## guard · unversioned · 2026-11-02 — the pinned-runtime ward read the pushing branch, and refused every worktree push

### Why
`bin/gates/guards/runtime-pinned-guard.sh` landed the same day (Rule 02 §7, PR #470) to stop a unit running
a checkout an agent switches branches in. It asks git two questions about *other* trees:
`git -C <unit target> rev-parse --show-toplevel` and `git -C <pinned runtime> rev-parse --abbrev-ref HEAD`.

The ward runs inside the pre-push hook, and git exports `GIT_DIR` to a hook. With `GIT_DIR` set, `git -C`
no longer answers about the tree it was pointed at — it answers about the repository being pushed. Measured
this evening on the first push from a worktree after that ward landed:

```
clean shell : "every unit names /home/<seat>/ymir-runtime, and it stands on main"
under the hook: "the pinned runtime is off its branch — /home/<seat>/ymir-runtime stands on yggdrasil/<branch>, not main"
```

The runtime was standing on main throughout. The ward had read the pushing branch and blamed the operator's
runtime for it, with a help line telling him to `git checkout main` in a checkout that was already there.

**Every push this house makes comes from a worktree (Rule 08), so the gate refused all of them** — and the
refusal's remedy points at the wrong machine, which is how a real fault gets "fixed" by moving something that
was never broken.

### Files
- `bin/gates/guards/runtime-pinned-guard.sh` — a `gother()` helper unsets `GIT_DIR · GIT_WORK_TREE ·
  GIT_COMMON_DIR · GIT_INDEX_FILE` for the two questions the ward asks about another checkout, and a comment
  records why (a guard that is wrong only under a hook is wrong on every push).

### Proof
Both modes now agree: clean shell and `GIT_DIR=<the worktree's git dir>` both answer
`"none","every unit names … and it stands on main"`. The pushed branch went through the gate afterwards.
