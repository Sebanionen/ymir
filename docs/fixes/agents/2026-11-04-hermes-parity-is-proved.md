## agents · unversioned · 2026-11-04 — Hermes parity is proved, and the asset knows the doors

### Why
Plan 177 claimed Hermes was a first-class harness — the seat in `SOUL.md`, `.hermes.md` at the git
root, the `ymir` MCP packet with 30 doors, and the Gná arm on every harness that has a hook surface.
None of it was PROVED by a command, and the governed asset
(`.agents/skills/galdr-ymirsystem/assets/harness-integration/README.md`) was silent on eleven doors
built the night of the crash. A claim without a test is a hope; a door without its asset is an
incomplete change (the governed-paths law). Both are closed here, without staging a model turn.

**The acceptance test.** `bin/gates/tests/test_hermes_seat.sh` proves, in the shape the other
production tests use (`ok`/`FAIL`, non-zero on any failure): `~/.hermes/SOUL.md` carries the marked
`ymir-seat:begin … end` block and names this seat, this seat's primary and this operator — all three
read from `hodd/identity/seats.yaml` and `hodd/identity/operator.yaml`, never a literal; `.hermes.md`
exists at the repo root and `git check-ignore` agrees it is machine-local; `hermes mcp list` names the
`ymir` packet; `python3 bin/mcp/ymir-mcp.py --selftest` lists its doors and the seat file's list is
EXACTLY that set (a seat file naming fifteen doors while the packet registers thirty is the drift
this house keeps paying for); no seat is named Brokk, a roster that says brokk is refused loudly and
writes no identity, and an unseated config renders *unnamed* rather than an invented name — proved by
a sandbox `HOME`/`YMIR_HOME` run of the real renderer, with the gitignored `.hermes.md` saved and put
back. A machine without Hermes is a clean skip with its reason and exit 0 (RULES/25); the test says in
its own footer what it cannot prove — that the model answers as the seat — because that is the one
sentence a human closes with one session.

**The arm, per harness.** `bin/pi/arm.sh hook <harness>` now names, and for Hermes INSTALLS
(`--install`) and verifies (`--check`), what a harness must seat. Hermes' session side is
`bin/seat/hermes-session-hook.sh`, reached through a stable shim at
`~/.hermes/agent-hooks/` that resolves the house at RUN time (a worktree is removed by
`yggdrasil.sh cleanup`, so a hook pointing into one dangles — the lesson the AGENTS.md contract
already learned). Two entries, one command: `on_session_start` runs the Sága digest once and stashes
it; `pre_llm_call` returns `{"context": …}` on that session's FIRST turn, and only when the working
directory is inside the house — the documented injection shape, so the bearings actually reach the
model. Consent is recorded per `(event, command)` pair in
`~/.hermes/shell-hooks-allowlist.json`, and re-arming refreshes the recorded mtime so
`hermes hooks doctor` stays clean. Codex and Cursor are recorded in the door's own text as unarmable:
no session hook surface, named and never faked. Install and Gróa both seat the hook
(`step_loaders` in `bin/engine/ymir-install.sh`, the rebound block in `bin/agents/groa-update.sh`);
a host without Hermes is a named skip.

**Delivery is idempotent by content.** `bin/seat/seat-surface.sh` now writes `.hermes.md` and the
`SOUL.md` block only when the bytes differ, so "the renderer ran" is provable by an unchanged mtime
(`seat-surface` twice ⇒ the second run writes nothing). The SOUL block's door list is READ from
`bin/mcp/ymir-mcp.py --selftest` rather than restated in the template — one list, no second table —
which is what makes the drift guard in the test possible.

**The asset.** `harness-integration/README.md` gained an appended section naming
`bin/seat/seats.sh`, `bin/pi/arm.sh`, `bin/seat/hermes-telegram.sh`,
`bin/notify/telegram-machines.sh`, `bin/records/{weave,plan,header,note,grade}.sh`,
`bin/agents/hall.sh`, `bin/vault/push.sh` and the 30-door `ymir` packet, each with its verbs and its
honest limit.

### Proof (commands, run in the errand's worktree)
- `bash bin/gates/tests/test_hermes_seat.sh` → 27 `ok`, 0 `FAIL`, exit 0.
- `bash bin/gates/tests/test_new_doors.sh` → 14 `ok`, 0 failure.
- `bash bin/seat/seat-surface.sh --check` → clean (seat, operator, SOUL block, `.hermes.md`, links).
- `bash bin/seat/valknut-load.sh --check` → PASS (after the worktree sparse exclusion the check itself names).
- `bash bin/pi/arm.sh hook hermes --install` → shim + hooks block + 2 consent pairs;
  `hermes hooks list` shows both `✓ allowed`; `hermes hooks doctor` → "All shell hooks look healthy".
- `bash .agents/skills/galdr-ymirsystem/scripts/compliance-check.sh` → no NEW failure: 17 PASS, and one
  inherited `mocks` row (`bin/mcp/ymir-mcp.py:239 def todo(…)` — the gate cannot tell a door named `todo`
  from a stub; that line is at the foundation commit and untouched here).
- `seat-surface.sh` twice → second run reports "already current (nothing written)" for both surfaces.

### Files
- `bin/gates/tests/test_hermes_seat.sh` (new) — the acceptance test (H2/H3)
- `bin/seat/hermes-session-hook.sh` (new) — Hermes' session side of the arm (H4)
- `bin/pi/arm.sh` — `hook <harness>` names each harness; Hermes `--install` / `--check`
- `bin/seat/seat-surface.sh` — writes only on change; the SOUL door list read from the packet
- `bin/seat/assets/hermes-soul.md.in` — `__DOORS__` / `__DOOR_COUNT__` instead of a restated list
- `bin/engine/ymir-install.sh` — `step_loaders` seats the arm's session hook
- `bin/agents/groa-update.sh` — the update re-seats it
- `.agents/skills/galdr-ymirsystem/assets/harness-integration/README.md` — the doors, their verbs, their limits
