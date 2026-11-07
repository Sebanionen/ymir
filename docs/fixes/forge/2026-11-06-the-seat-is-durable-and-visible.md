# The reviewer's seat is durable and visible — a herdr server unit and a keeper timer

**Date:** 2026-11-06 · **Plan:** 206 §12.2 · **Law:** `RULES/25-agnostic-by-construction.md`

## What was wrong

The Allfather: *"yes but it should run in herdr so i can see it."* Two faults in one sentence.

1. **A pane raised over ssh dies with the session.** Measured on the heart: `review-seat.sh ensure
   --primary` raised a pi seat, it reached `idle`, and the pane was gone minutes later. A seat that
   dies when the operator disconnects is not a seat.
2. **A headless agent is invisible.** The alternative — a unit running `pi` with no terminal — would
   review where nobody can look, which is the opposite of what he asked for.

## What was built

`review-seat.sh --install-unit [--primary]` writes and enables **two user units**:

- `herdr-server.service` — the herdr **server** as a service (`Type=simple`, `Restart=on-failure`),
  so the panes outlive every client. Its `ExecStart` guards against a second server: if one answers,
  it sleeps instead of starting a rival.
- `review-seat.timer` → `review-seat.service` — a keeper every 5 minutes that runs
  `review-seat.sh ensure` (idempotent: it returns immediately when a live pi is already in the
  clone) and re-raises the seat when it is gone.

`--unit-status` and `--uninstall-unit` are the other two verbs. Nothing in the unit takes the helm by
itself: `ensure --primary` decides that, and refuses when a live primary already holds the lock.

## Verified

On `zerwizserver`: `review-seat.sh --unit-status` → `herdr_server, keeper_timer` states;
`herdr workspace list` showed the `review` workspace alive with a pi agent in `~/review/ymir`
**working**, its status line `(opencode-go) deepseek-v4.1-flash • high`, and the machine's
`brokk.lock` naming that seat's pid with the arm lease's `session=` equal to it — the seat holds the
helm and drains the arm, which is exactly what the loop needs.

## CHANGE LOG

- **2026-11-06** — written after the ssh-raised pane died and he asked for a seat he can watch.
