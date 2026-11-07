## agents · unversioned · 2026-11-05 — the seat seals its own PR, and the word arrives through Gná

### Why

The Allfather's word (plan 190 §1):

> *"The arm holder ALWAYS NEED TO GET A NOTIFICATION IN THRU THE ARM on when a PR are done. And merge that PR
> directly. Otherwise main will move and merge will have conflicts"*

A PR left open is a branch drifting from a moving `main`: two seats and three errands pushed into the same
file set tonight, and every hour of delay bought a rebase. `RULES/08` §08.1 said an agent opens a PR and never
merges it, so the law had to change **first** (append-only, Rule 06) and the change had to be narrow.

### The fix

1. **`RULES/08-delivery-gate.md`** gains a dated, appended section (§ above §08.5 is untouched): the seat's own
   PR is sealed by the seat's agent — Sindri on nidavellir, Hœnir on heimdall — when SIX conditions hold:
   the seat's own PR · CI green · no conflicts · the seat's only open PR · one Runes entry naming PR, head and
   merge commit · `state/.seal-hold` absent. Another hand's PR is never merged. **No merge on red or
   conflicted, under any flag.**
2. **`bin/agents/pr-seal.sh watch`** — judges every open PR raised by this credential and, for each one that
   holds conditions 1–4 and 6, raises ONE wake line into `state/.wake-queue` naming PR, head, checks and the
   exact merge command. Idempotent per `(PR, head sha)`: the flood brake this house already paid for.
3. **`bin/agents/pr-seal.sh seal <n>`** — re-checks all six IMMEDIATELY (a green from an hour ago is not
   evidence now), runs `gh pr merge <n> --squash --delete-branch`, carves ONE Runes entry through
   `bin/records/runes-append.sh`, and prints the merge commit. A refusal names the failing condition and
   stops; it never retries blindly.
4. **Ownership, without a second identity.** Every agent shares the operator's GitHub login, so authorship
   cannot decide whose PR is whose. A PR is the seat's own when its body carries `Arm: <seat host>` / `Arm:
   <primary>@<host>`, OR its head is `eindri/<id>` for an errand this seat dispatched (`state/<id>.meta`
   exists), OR the head branch exists in THIS clone (a peer's branch arrives only as a remote ref). Anything
   else is another hand's and is never sealed.
5. **The sweep walks the arm's road**: `bin/agents/eindri-handoff.sh sweep` runs `pr-seal.sh watch --quiet`
   after the liveness question, so a green PR that nobody noticed still reaches the seat.

### Proof

```
# (c1) watch judges real open PRs and refuses what it must not touch
$ bin/agents/pr-seal.sh watch
pr-seal[6]{pr,head,ci,merge,verdict}
  "#519","feat/one-door-for-the-registers","red","conflict","RED"          why: gates=failure
  "#518","fix/garmr-retention","red","conflict","NOT OURS"                 why: no Arm marker, no errand of this seat, and no local branch
  …
# (c2) seal refuses, on real PRs, without merging anything
$ bin/agents/pr-seal.sh seal 518
seal-refused[1]{pr,condition,detail}:
  "#518","not ours","no Arm marker, no errand of this seat, and no local branch — another hand's PR"
$ bin/agents/pr-seal.sh seal 511      # (while it was still open, and red)
seal-refused[1]{pr,condition,detail}:
  "#511","CI not green","gates=failure, gates=failure"
```

The positive wake — one line for a green own PR — was NOT exercised tonight: the one-open-PR rule refuses a
second PR of this seat while `#519` (own per the rule above, red and conflicting) stands open, so the branch
that would have been that PR was pushed and reported instead. The wake path is the same call, one condition
earlier; the seat runs `pr-seal.sh watch` the moment its own PR can exist.

### Files

- `RULES/08-delivery-gate.md` (dated amendment appended; nothing rewritten)
- `bin/agents/pr-seal.sh` (new)
- `bin/agents/eindri-handoff.sh` (`sweep` walks the arm's road)
- `docs/features/pr-seal.md`, the catalogue entry, and `FEATURES.md` (woven)

galdr-reread: `brokk-distro-runtime.md` (the arm and the failsafe sweep), `nornir-jobs.md`.
