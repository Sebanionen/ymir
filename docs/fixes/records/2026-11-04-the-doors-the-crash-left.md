## records · 2026-11-04 — the doors the crash left: one home for the plan ledger, the note, the header, the grade, the weaver and the seats

### Why
The night of 2026-11-03 built a run of doors that only Pi could reach, and then the session carrying them
died (SIGKILL, `code 137`, a 870k-token context) four seconds into its last command. The doors were written
and never committed, never catalogued and never tested — a bench, not a delivery. This note is their record,
written before anything is pushed.

### Mend
- **`bin/records/plan.sh`** — the ledger's next number, read from the index, never reused (`next · list`).
- **`bin/records/note.sh`** — the append-only note: a dated section onto an existing home document.
- **`bin/records/header.sh`** — the declared header (`kind · status · verified · verified_by · supersedes ·
  superseded_by`) a home document carries, with `--check` and `--apply`.
- **`bin/records/grade.sh`** — Dellingr's craft: a Norse grade (`nýr · eldri · forn · safn`) from measurable
  signals only; an old document MOVES, it is never deleted (Rule 11).
- **`bin/records/layout.py`** — the placement oracle: `classify` a path against the layout law, `find-home`
  for a file that is not yet placed.
- **`bin/records/weave.sh`** — the weaver's dispatcher: `--check` every woven document and every index,
  `--fix` appends only the rows a plan or a rule is missing, `--fix-count` the rules index only. It healed 34
  unindexed plan rows on its first run; `indexes: agree`.
- **`bin/seat/seats.sh`** — every pane and errand in **either** backend (herdr first, tmux fallback), with dead
  shells named, and `close` refusing a live seat.
- **`bin/seat/hermes-telegram.sh`** — Hermes' ears, honest about an empty platform.
- **`bin/notify/telegram-machines.sh`** — the fleet's Telegram registry door (`list · me · relay`); a missing
  registry is loud, never an empty list.
- **`bin/agents/hall.sh`**, **`bin/pi/arm.sh`**, **`bin/vault/push.sh`** — the hall in one read, the Gná arm
  named per harness, and the home's push door (named paths only, never `-A`).
- **`bin/mcp/ymir-mcp.py`** — the same doors over MCP, so every harness reaches them; `--selftest` lists 30.

### Proven
- `bin/gates/tests/test_new_doors.sh` — **14 ok, 0 failures** (the production tests the plan still owed).
- `python3 bin/mcp/ymir-mcp.py --selftest` — 30 doors listed, the home resolved.
- `bin/records/weave.sh --check` — `indexes: agree`.
- `bin/pi/arm.sh status` — watch unit `active`, and the session side named per harness.
- `hermes mcp list` — eight servers, `ymir` among them; `bin/seat/valknut-load.sh --check` passes.
