# The seat seals its own PR — `bin/agents/pr-seal.sh`

**What it is.** A pull request opened from a seat belongs to that seat, and waiting for a human to press
merge is what makes branches drift: *main moves, and the merge arrives with conflicts*. So the seat's own PR
is sealed by the seat's own agent, the moment it is green — and the word that it is ready arrives through
**Gná**, the messenger, as a wake the seat cannot miss. Another hand's PR is never touched.

The reversal is narrow, and the narrowness is the safety. All six of these must hold, every time:

1. **It is the seat's own PR** — opened by this seat or an Eindri it dispatched.
2. **CI is green** — every check concluded success, nothing pending, nothing skipped by failure.
3. **No conflicts** — GitHub says the PR is mergeable, and is not blocked, draft or unresolved.
4. **It is the seat's ONLY open PR** — the one-PR rule still stands.
5. **One Runes entry** names the PR, its head and its merge commit.
6. **`state/.seal-hold` is absent** — the brake; while it exists the seat merges nothing and says why.

**What you need.** `gh` logged in as the operator, the house state directory (resolved through
`bin/vault/hoard-lib.sh`), and a seat identity in `~/.pi/agent/extensions/.ymir-seat`. A worker cannot use it
to merge its own work: ownership (condition 1) is the seat's, and a second open PR (condition 4) refuses the
rest.

**The commands**

```sh
bin/agents/pr-seal.sh watch          # judge every open PR; raise ONE wake per ready PR
bin/agents/pr-seal.sh watch --quiet   # the same, silently (used by the sweep)
bin/agents/pr-seal.sh seal <n>        # re-check all six, then merge, then carve the Runes entry
```

`watch` prints one row per open PR with its verdict — `SEAL` · `RED` · `CONFLICTED` · `QUEUE` (a second open
PR) · `HELD` (the brake) · `NOT OURS` — and, for a `SEAL`, appends one line to `state/.wake-queue`:

```
PR #<n> (<head> at <sha>) is green and conflict-free — the seat seals it now: bin/agents/pr-seal.sh seal <n>
```

The wake is idempotent per `(PR, head sha)`: a second `watch` in the same minute raises nothing new, and a
new head sha earns a new wake. It never retries blindly, and it never merges on red or on a conflict — under
any flag.

**How ownership is decided.** Every agent shares the operator's GitHub login, so authorship cannot answer
"whose PR is this". A PR is this seat's when its body carries `Arm: <seat host>` (or `Arm: <primary>@<host>`),
or its head is `eindri/<id>` for an errand this seat dispatched, or the head branch exists in this clone. A
peer's branch arrives only as a remote ref, so it is never mistaken for ours.

**Where the wake comes from.** The same mechanism the rest of the house uses: `state/.wake-queue`, drained by
Sága and the arm. `bin/agents/eindri-handoff.sh sweep` (the 06:45 Nornir row and every session start) runs
`pr-seal.sh watch --quiet`, so a green PR is noticed even when nobody asked. The seal itself is always the
seat's act — never a timer's.

**If it does not work**

- `NOT OURS` for a PR you opened: add the line `Arm: <hostname -s>` to the PR body, or re-open it from the
  errand branch (`eindri/<id>`), which is recognised without a marker.
- `QUEUE`: the seat has more than one open PR. Finish, rebase or close the other one first — that is the rule,
  and the seal will not break it.
- `RED`: read the check that failed. A red PR is never merged; fix it and push a new head.
- `CONFLICTED`: `mergeStateStatus=DIRTY`, `BLOCKED` or `DRAFT`. Rebase the branch, or clear the block.
- `HELD`: somebody left `state/.seal-hold`. Read it; remove it only by the Allfather's word.
