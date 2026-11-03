## install · 2026-11-03 — the loader seats Hermes

### Why
`bin/seat/valknut-load.sh` bound OpenCode and Pi but knew no `--hermes`, so a machine
with Hermes installed never received Ymir's packets on an install or an update — the
Allfather's word on 2026-11-03: *"hermes should also be one of the harnesses we support."*

### Mend
- `--hermes` is a first-class flag; `--all` includes it; bare invocation still defaults
  to OpenCode + Pi (Hermes is opt-in there, since installing it is the operator's choice).
- The Hermes seat runs `bin/seat/hermes-seat.sh` (packets + skills trust); a machine
  without Hermes prints *"hermes: not installed on this seat — skipped"* and never fails.

### Proven
- `valknut-load.sh --hermes` → *hermes: packets seated, skills trusted*.
- `valknut-load.sh --status` unchanged for the other harnesses.
