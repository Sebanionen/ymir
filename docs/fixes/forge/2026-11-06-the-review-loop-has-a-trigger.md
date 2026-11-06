# The review loop has a trigger — `bin/forge/review-watch.sh`

**Date:** 2026-11-06 · **Plan:** 206 §10 · §3 F2 · **Law:** `RULES/08-delivery-gate.md`, `RULES/25-agnostic-by-construction.md`

## What was wrong

The review spine already existed (`bin/agents/eindri-review-spawn.sh`, Forseti the Judge), and it fired only
on an errand's own terminal `done`. **Nothing watched the repository.** A PR opened by another hand, or by an
agent that never called `acclaim`, was never seen — which is the whole of the Allfather's question: *"why
isn't the heart reviewing all prs that come in on the ymir repo."*

## What was built

`bin/forge/review-watch.sh` — one pass lists the open PRs of the named repos and, for each PR not already
judged at **this head**, raises exactly one question into the lock owner's queue through
`bin/seat/lock-ask.sh`, naming the PR, its head sha, its CI and its mergeability. The `(PR, head)` marker
means a second pass in the same minute raises nothing, and a moved head earns a new question.

It never merges, pushes, comments, or decides. `--judge <n>` is the owner's answer and seats the judge
through the spine's new `--pr` mode.

## The refusals it keeps

- **No GitHub identity, no watch.** `gh auth status` failing is a REFUSAL that names the road; an
  unreadable repository is never reported as "nothing to do" (the false green of plan 206 §3 F1).
- **No live lock owner, no question.** The ask door refuses rather than writing into a queue nobody drains.
- **A draft is not offered** for review, and says so in its own row.
- **A conflicting PR is still asked about** — the judge's verdict will name the conflict; the watch does not
  pre-judge.

## Verified

`review-watch.sh --dry-run` on nidavellir: `seen 1 · raised 0` for `zerwiz/ymir` #552 (head `fff945404d00`,
`CONFLICTING`, `ci=none`). A real pass raised one ask (`ask-20261106T204921Z-5dcd`) into
`state/.wake-queue`, and a second pass raised nothing. `bin/seat/tests/test_lock_ask.sh` — 9 ok / 0 fail.

## CHANGE LOG

- **2026-11-06** — written with the doors it describes (plan 206): the review loop joined to the
  spine, the read-only agent's mouth, the resolver that replaced five hardcoded model ids, and the
  operator-only mail door.
