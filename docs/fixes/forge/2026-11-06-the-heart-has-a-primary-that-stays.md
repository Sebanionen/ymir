## forge · unversioned · 2026-11-07 — the heart has a primary that stays, and answers its own ask

Plan 206 §11 measured the loop inert: `review-watch` ran every ten minutes, saw all five open PRs,
and raised **none** — *"there is NO lock on this machine — nobody holds it, so there is nobody to
ask."* The lock pointer named a `brokk.lock` inside the machine state directory, and the file did not exist.

Two causes, both closed here, plus the seat door that had never been committed:

| file | what it fixes |
|---|---|
| `bin/seat/lock-hold.sh` (new) + `ymir-seat-lock.service` (operator unit) | **a lock needs a holder that does not exit.** A lock taken by a shell that then ends is not a lock. This process acquires it, yields to a live interactive owner, reaps a dead one, and stays — so the heart always has a primary, headless or not |
| `bin/forge/review-watch.sh` | **the ask is answered by the seat itself when this machine IS the reviewer's.** Gated hard: `YMIR_REVIEW_SELF=auto` (default) acts only when the topology role contains `heart` **and** the seat primary resolves to `forseti`; `1` forces, `0` disables. The decision is recorded — runes entry *"the heart answered its own ask … the seat decided for itself"* — so the exception is visible, never assumed. It then seats the judge itself (`review-seat.sh ask N --wait`) |
| `bin/forge/review-seat.sh` (committed) | the seat door: shelf, brief + charter appended, the shelf's duplicate `.pi/extensions` set aside (which is what produced 40+ `Tool … conflicts` errors on the operator's own launch), and the model resolved per seat |

### Measured, in order, on the heart

```
before[2]{step,result}:
  "review-watch by hand","5 PRs seen · 0 raised · every ask REFUSED (no lock owner)"
  "lock-ask who","owner_pid=none · live=no"

after[3]{step,result}:
  "ymir-seat-lock.service","active · lock owner 2140216 · live=yes · arm agrees · queue shared"
  "review-watch by hand","5 seen · 1 raised · 'the seat answers its own ask for #560 (role heart, primary forseti) — recorded'"
  "the judge","pane w4:p1 prompted, agent_status=working, running bin/gates/guards.sh on PR #560's head"
```

### Not done, and named

- The four **CONFLICTING** PRs (#552, #556, #557, #558) are still conflicting: the loop correctly
  raises them, and the seat correctly refuses to judge a head that cannot merge. Clearing a conflict
  is a **smith's** act (plan 203: the reviewer never edits), so they wait for one.
- The operator's paid model keys are expired (`opencode-go` 401, `openrouter` 401); the reviewer's
  overlay row was moved to `opencode-go/beam-free`, which answers. Renewing the key restores the
  stronger model without touching this code.

## CHANGE LOG

- 2026-11-07 · lock-hold door + seat-lock unit; review-watch answers the ask it raised on the heart
  and records it; the seat door committed. Proven: raised → self-answered → judge working.
