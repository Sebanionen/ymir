## gate · unversioned · 2026-11-04 — the weaver was seated and nothing called it

### Why

Plan 175 §3 gives a woven document three layers with three different jobs, and none of them
substitutes for another: the merge driver **resolves** a conflict, the pre-commit hook is
**convenience**, and a ward is **the law**. The dispatcher `bin/records/weave.sh` landed with
`--check` answering `indexes: agree` — and **no ward, no hook and no CI row called it**. Measured
on the foundation commit, in a clean worktree: `bin/gates/guards.sh` named 23 wards and none of
them was a weaver; `.git/hooks/pre-commit` ran five wards, `no-delete-guard` and the secret scan
and never wove; `bin/gates/ci-verify.sh` had rows for the registers and the capability shelf and
none for the indexes. So `RULES/README.md`, the plan ledger's `README.md` and the feature
catalogue could drift by hand and **every gate in the house stayed green**. A capability that no
door reaches is a capability silently absent — this time the absent capability was the gate over
the indexes themselves.

Two faults were found *inside* the dispatcher while wiring it, and both are the same species —
a check that cannot see what it claims to judge:

1. **The default mode was dead code.** `weave.sh` matched `-h|--help|"")` for the empty argument,
   so the arm that "weaves what can be woven" (the mode the hook calls first) was unreachable:
   `weave.sh` printed its own usage and wove nothing. Nothing said so, because its exit was 0.
2. **A commented-out row counted as a row.** The index check asked `grep -qF "<file>" <index>` —
   a presence test — so a hand-edit that commented a row out (`#  "01-domains.md"`) passed with
   `indexes: agree`. That is precisely the edit the ward exists to refuse; proved by running it.

### Mend

Three layers, wired where they can actually bite:

1. **The ward — the law.** `bin/gates/guards/weave-guard.sh` runs `bin/records/weave.sh --check`,
   refuses, and **names** the gap (index · the file · what is missing). It never fixes: a ward that
   repaired the drift would hide the hand-edit that caused it. Seeded into the ONE ward list in
   `bin/gates/guards.sh` (23 → 24), so the pre-push hook and both CI hosts judge it.
2. **The hook — convenience, narrow and loud.** The `--install` heredoc in
   `bin/gates/guards/secret-guard.sh` now weaves *before* the wards, `git add`s **only** the four
   WOVEN paths (`FEATURES.md`, `bin/README.md`, `.agents/backend/README.md`,
   `.agents/assets/agents/capabilities.md`), and prints each one it staged. The rule is enforced by
   mechanism, not by good behaviour: the hook hashes the four paths before the weave and stages
   only those whose **blob changed** — a hand-authored file can never be written or staged by it.
   It stays runtime-rooted (`git rev-parse --show-toplevel`) and resolves nothing absolute.
3. **CI — the last word.** One `gate weave` row in `bin/gates/ci-verify.sh`, beside the register
   rows, running `bash "$ROOT/bin/records/weave.sh" --check` — so a stale index is refused on the
   merge the host builds even if no hook on any machine ever fired.

Two mends in the dispatcher, both required by the layers above:

- `weave.sh`'s help arm no longer swallows the empty argument, so weave-what-can-be-woven runs.
- The presence test became `has_row`: comment lines are dropped before the test, so a commented-out
  row is **not** a row. The verdict is a `case` match rather than `grep -q` in a pipeline — under
  `set -o pipefail` the reader's early exit (SIGPIPE) reads as failure, which made every large index
  report every file unindexed the first time this was written (measured: 126 false drifts, then 0).

One mend in the aggregator: `guards.sh` carried a failing ward's own message up with
`grep -E '^(defaults|runtime)-guard:'`, so every other ward's reason was thrown away and its FAIL
row printed an empty finding (visible today on `inventory-guard` and `registers-guard`). The pattern
now matches the ward suffix, and the message is not cut to 96 characters — a gate that will not say
why is an obstacle, and the new ward's whole job is to name the drift.

### Verified

Measured on this branch, in a disposable worktree, every line a command:

```
bin/gates/guards/weave-guard.sh                 "none","rules · plans · features","indexes: agree"   rc=0

# the ward refuses — a row commented out in RULES/README.md
bin/gates/guards/weave-guard.sh                 "an index has drifted","rules","01-domains.md has no README row"
weave-guard: 1 index drift(s) — ...             rc=1
git checkout -- RULES/README.md
bin/gates/guards/weave-guard.sh                 "none",... rc=0        (the same ward, clean again)

bin/gates/guards.sh                             guards[24] … every row PASS
                                                (baseline before this change: guards[23], inventory-guard FAIL,
                                                 registers-guard FAIL — both healed by the regeneration below)

bin/records/weave.sh                            woven and checked: no drift      (the once-unreachable mode)
bin/gates/inventory.sh --check                  bin/README.md current · .agents/backend/README.md current (176 files)
bin/gates/capabilities.sh --check               current (662 door rows)

# the hook, proved by re-running its install path and committing what needed a weave
bin/gates/guards/secret-guard.sh --install      "install","<hooks>/pre-commit"
git commit                                      weave: wove and staged FEATURES.md (a woven file — the only kind a hook may write)
                                                weave: wove and staged bin/README.md (…)
                                                weave: wove and staged .agents/backend/README.md (…)
                                                weave: wove and staged .agents/assets/agents/capabilities.md (…)
                                                private-guard clean · vault-guard none · confidential-guard none · no-delete-guard 0

bin/gates/ci-verify.sh --fast                   "weave","PASS","every index names every rule, plan and feature page (plan 175)"
bin/gates/tests/test_new_doors.sh               13 ok, 1 failure
```

Four `ci-verify --fast` gates fail **before this change and after it**, and none of them touches a
path this branch touched (`git diff --stat HEAD -- <their areas>` is empty):

- `compliance` — the mock scan flags `bin/mcp/ymir-mcp.py:239` (`def todo(...)`); a word-matching
  false positive on a tool, not a mock.
- `contracts` — `apps/hlidskjalf/src/gates/Skirnir.tsx(266,153): error TS1005: '}' expected`.
- `queue` — `$YMIR_HOME/…/plans/queue.md` is STALE (home-side; `bin/gates/queue.sh`).
- `plan-ledger` — 220 gaps over the home's plan ledger, "no baseline recorded" (home-side).

`test_new_doors.sh` reports 13 ok and one failure — `seat-surface: check passes` — which failed
identically **before** this branch existed: `.hermes.md` is machine-local and gitignored, written by
the seat install/update path, and a fresh worktree has never been seated. Seating it from here would
repoint the machine's harness identity at a disposable tree, so it is left to install, honestly named.

### Files
- `bin/gates/guards/weave-guard.sh` — the ward (new)
- `bin/gates/guards.sh` — the ONE ward list (23 → 24) and the FAIL message it used to swallow
- `bin/gates/guards/secret-guard.sh` — the `--install` heredoc weaves, names and stages only woven files
- `bin/gates/ci-verify.sh` — the `weave` row (CI keeps the last word)
- `bin/records/weave.sh` — the unreachable default mode, and `has_row` (a commented row is not a row)
- `bin/README.md`, `.agents/backend/README.md`, `.agents/assets/agents/capabilities.md` — regenerated (the new door is `wired`)

### Not done, on purpose

The per-document weavers of plan 175 §2 (`weave-rules.sh`, `weave-plans.sh`,
`weave-features-index.sh`) stay **unbuilt**. The indexes are hand-kept prose, and a generator that
rewrote them could not preserve the reasoning a human put in a row; the dispatcher therefore
**verifies** completeness instead of regenerating, and the ward is what ends the drift. Recorded as
the deliberate deviation in the plan (`§6`).
