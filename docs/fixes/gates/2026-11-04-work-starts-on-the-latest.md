## gates · 2026-11-04 — two plans, one number: the ledger allocated from a tree that was behind

### Why

The Allfather: *"make a rule in ymir that before any updates on ymir starts to always pull and make sure
the work starts on latest codebase."* Then, after seeing it happen again: *"this is why the rule for
pulling must exist."*

`ymir_plan` (→ `bin/records/plan.sh new`) was asked for the next number on this seat while the home was
**seven commits behind** `origin/main`. It numbered from the directory listing it could see —
`ls | sort -n | tail -1 | awk '{print $1+1}'` — and answered **182**. The plan was written, the index row
appended, the commit made. Another machine had already taken 182 that afternoon (`182-the-nidavellir-bench…`,
pulled minutes later), so the number now named two plans and the second had to be renumbered by hand.

The same shape sat one line away in the errand door: `einherjar-spawn.sh` cut a Yggdrasil worktree from
`refs/remotes/origin/<default>` — a ref that only moves when somebody fetches — so a worker could be seated
on yesterday's tree and told it was the tip.

A **distributed allocation** was being decided from a local memory. Nothing failed loudly.

### Fix

- **`bin/records/plan.sh`** gained `ledger_state()` (`fresh` · `behind:<n>` · `unverified:<why>`) and
  `refuse_stale_ledger()`, called by `new` and **not** by `list`/`next`: reading is free, taking a number
  is an allocation. It fetches, compares against `origin/<default>`, and on `behind` refuses, names the
  count, and prints the one repair (`git -C <home> pull --ff-only`). `YMIR_ALLOW_STALE_LEDGER=1` is the
  loud override; a home with no remote (or offline) is a stated `unverified` note, never a silent pass.
- **`bin/gates/checks/fresh-base-check.sh`** — the same question for any tree: fetch, compare, name the
  distance, `--strict` exits 1 (the errand door). Not a git tree / no remote / offline are clean skips
  with the reason printed (Rule 25). It never rebases or pulls: the repair stays visible to a human.
- **`bin/agents/einherjar-spawn.sh`** fetches before it resolves the worktree base, and prints
  `warning: … base is UNVERIFIED` when the fetch fails instead of seating a worker on a stale tip.
- **`bin/agents/groa-update.sh`** opens by running the check, so an update states the base's state first.
- **`RULES/45-start-on-the-latest.md`** — the law, appended: a base is fetched not remembered; reading is
  free and taking is not; a stale base refuses with the repair; offline is a stated skip; never force,
  never someone else's branch; the update starts by pulling.

### Verified

- `.agents/tests/plan-ledger-fresh.test.sh` — **7 ok, 0 failed**: reading `next` while behind exits 0;
  `new` refuses with `REFUSED` and writes no file; the refusal names `pull --ff-only`; the loud override
  works and warns; after `--ff-only` the ledger takes the true next number; a home with no remote is a
  stated `unverified` skip.
- `bash -n` clean on `plan.sh`, `einherjar-spawn.sh`, `groa-update.sh`, `fresh-base-check.sh`.
- `fresh-base-check.sh` on this tree prints one line and exits 0 (FRESH, or a named SKIP).

### Files

- `bin/records/plan.sh` · `bin/gates/checks/fresh-base-check.sh` · `bin/agents/einherjar-spawn.sh` ·
  `bin/agents/groa-update.sh` · `RULES/45-start-on-the-latest.md` · `RULES/README.md` ·
  `.agents/tests/plan-ledger-fresh.test.sh` · `bin/README.md` (regenerated)
