# The reviewer has a seat, a verdict and a ship door — `review-seat.sh` · `review-verdict.sh` · `ship.sh`

**Date:** 2026-11-06 · **Plan:** 206 §3 F3 · §6 M3–M5 · **Law:** `RULES/08-delivery-gate.md` (appended 2026-11-06)

## What was wrong

Three pieces of the loop were prose and not doors.

1. **No seat.** Plan 203 §12 asked for the reviewer on the heart, in a herdr pane, running pi. The pane
   existed; nothing gave it a charter, a clone, or a way to be asked. The Allfather's word:
   *"make so we're using the pi harness in herdr for this work."*
2. **No verdict.** The judge is `edit: deny, write: deny` — correct, and it meant the judge could not write
   the verdict that `ship` must read. A verdict spoken into a chat is not a record.
3. **No ship door.** `delivery: reviewer-merges` was declared in `hodd/identity/projects.yaml` and
   `RULES/08`, and **no code read it**. Nothing could merge a judged PR, so "the reviewer merges" stayed a
   sentence.

## What was built

- **`bin/forge/review-seat.sh`** — `status · ensure · ask · charter · close`. One herdr workspace named
  `review`, one **pi** agent, cwd the review **clone**, the role file plus a generated charter through
  `--append-system-prompt`, a private `BROKK_MACHINE_STATE_DIR` set at workspace create (the two seat laws),
  and the model resolved by `bin/model/agent-model.sh` for that seat. `ensure` verifies the agent reached a
  real state — seating without verifying leaves an idle agent.
- **`bin/forge/review-verdict.sh`** — `write · show · list`. The judge's one act of writing: it refuses an
  abbreviated head, refuses a verdict for a head the PR has left, and writes `state/eindri-reports/pr-<n>-review.md`
  whose first line is `PASS`, `REFUSE` or `NEEDS-REWORK`, with the ruleset id and the moment.
- **`bin/forge/ship.sh`** — the merge, and six conditions with the first failing one named: the project's
  `delivery:` row, an open and mergeable PR, green CI, a verdict that is not a refusal, a verdict naming the
  **same** head, and no `state/.seal-hold`. Then it merges, writes **one** Runes entry, and mails him —
  MERGED with the record, or a FAIL line (the merge stands; the word that did not arrive is said out loud).
- **The watch prefers the seat**: `review-watch.sh --judge <n>` raises the herdr seat and asks it when
  `HERDR_ENV=1`; the einherjar spine is the fallback on a machine with no seat.
- **Forseti's card** gained exactly two bash allowances: its verdict door and its mouth. `edit: deny` and
  `write: deny` are untouched.

## Verified

`ship.sh --check 552` → `REFUSED — PR #552 is UNKNOWN — no merge on a conflicted, behind or blocked head`.
`ship.sh --check 1 --repo zerwiz/ymirhome` → `REFUSED — project 'zerwiz/ymirhome' declares delivery:
operator-merges`. `review-seat.sh charter` prints the law floor. `review-verdict.sh list` answers
`no verdict has been written` rather than an empty success. `review-watch.sh --judge 552 --dry-run` names the
road: `pi in herdr (review-seat.sh)`.

## CHANGE LOG

- **2026-11-06** — written with the doors it describes; the seat is raised on the heart in the same pass.
