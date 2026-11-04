## gate · 2026-11-04 — every CI run failed the features ward: a fresh clone has no merge driver

### Why
`features-guard.sh` refuses a tree whose woven catalogue is stale **or whose merge driver is not seated**:

```
driver="$(git -C "$ROOT" config --get merge.regenerate.driver)"
```

That driver lives in a clone's **git config**, and `bin/engine/ymir-install.sh` seats it on a real seat —
never in a fresh CI checkout. So `The gates` failed on **correct code** at every run, on main and on every
pull request, with `"the merge driver is not seated"` — a false red, and the third of its kind this night.

### Mend
`bin/gates/ci-verify.sh` seats the driver once, immediately before the wards, by running
`bin/records/weave-features.sh --install` (idempotent, and exactly what install does on a seat). If it cannot
seat it, the gate prints a `NOTE` naming that, rather than failing silently.

### Proven
- Reproduced the guard's own condition: in a fresh worktree `git config --get merge.regenerate.driver` is
  empty → the guard prints `"the merge driver is not seated"`.
- After the change, `bash -n bin/gates/ci-verify.sh` is clean and `bash bin/gates/guards/features-guard.sh`
  reports `every feature page is catalogued, and the woven catalogue is current`.
- The ward is unchanged: a genuinely stale catalogue still fails, and a page with no row still fails.
