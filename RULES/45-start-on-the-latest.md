# 45 — Start on the latest: fetch before you begin

**Appended 2026-11-04** at the Allfather's word — twice in one session, the second time as a
verdict rather than a request:

> *"make a rule in ymir that before any updates on ymir starts to always pull and make sure the work
> starts on latest codebase."*
> *"this is why the rule for pulling must exist."*

**The wound it answers, from this day.** This seat sat **seven commits behind** `origin/main` and asked
the plan ledger for the next number. `bin/records/plan.sh` numbered from the directory listing it could
see — `ls | sort -n | tail -1` — with no fetch. It answered **182**. The plan was written. But another
machine had already taken 182 that same afternoon, so the number now names two plans, and the second had
to be renumbered by hand. Nothing failed loudly; a distributed allocation was simply made from a memory.

The same shape was one line away in the errand door: `einherjar-spawn.sh` cut a Yggdrasil worktree from
`refs/remotes/origin/<default>` — a ref that only moves when somebody fetches. A worker could be seated
on yesterday's tree and told it was the tip.

```
start_latest_law[6]{rule,what it means}:
  "A BASE IS FETCHED, NOT REMEMBERED","anything that starts work — an errand, a worktree, a plan number, an update — fetches first. A remote-tracking ref nobody fetched is a memory, and a memory is not a head."
  "READING IS FREE, TAKING IS NOT","a command that only REPORTS may run on a stale tree and say so. A command that ALLOCATES or CREATES from it must refuse: a number, a branch point, a worktree base and a version pin are all allocations."
  "A STALE BASE REFUSES, WITH THE REPAIR","the refusal names how far behind, the one command that mends it (a fast-forward or a rebase of one's OWN branch), and a loud override for the operator."
  "OFFLINE IS A STATED SKIP, NEVER A SILENT PASS","no remote, no network, or `YMIR_OFFLINE=1` is a clean skip (Rule 25) that says the base is UNVERIFIED — never a green that hides a guess."
  "NEVER FORCE, NEVER SOMEONE ELSE'S BRANCH","rebase or fast-forward one's own branch only. Another hand's pushed work is never rewritten to make our base look current."
  "THE UPDATE STARTS BY PULLING","Gróa's update path fetches and fast-forwards before it mends anything; a mend applied to a stale tree is a mend for a tree that no longer exists."
```

**Enforced by**

- `bin/records/plan.sh` — `refuse_stale_ledger()` runs before `next` (allocation) is granted; it reports
  `fresh` · `behind:<n>` · `unverified:<why>`, refuses on `behind` and names the `git pull --ff-only`,
  and honours `YMIR_ALLOW_STALE_LEDGER=1` as a loud override. Reading (`list`, `next`) stays free.
- `bin/gates/checks/fresh-base-check.sh` — the same question for any tree: it fetches, compares, names
  the distance, and exits 1 under `--strict` (the errand door). A clean skip names its reason.
- `bin/agents/einherjar-spawn.sh` — fetches before it resolves the worktree base, and states a failed
  fetch as UNVERIFIED rather than seating a worker on a stale tip.
- `bin/agents/groa-update.sh` — already fetches and fast-forwards per home; its `--check` mode reports
  `behind` without touching the tree.

**The test that keeps it true:** `.agents/tests/plan-ledger-fresh.test.sh` — a fixture home whose ledger
is behind a bare remote must refuse to allocate, must allocate after `--ff-only`, and must allocate under
the loud override.

**What is deliberately not law:** that every read of a document requires a network. A seat on a plane
reads its ledger; it just may not hand out the next number as if the world stood still.
