## gate · 2026-11-04 — the harvest of four errands, integrated into one branch: the apostrophe, the two false gates, and what each teach

### Why
Four errands ran overnight (plans 174–179) and, by morning, every one of their pull requests was red on the same
job, `The gates` — and so was `main`. The Allfather's word: *"resolve the conflicts, get them all into one branch
and then make a PR … we are spending hours on the guards."* This note records the integration and the three
faults it exposed, because two of them were **false gates** — a gate that fails correct code teaches everyone to
override it, which is worse than no gate.

### Mend

1. **`apps/hlidskjalf/src/gates/Skirnir.tsx:266` — the apostrophe that broke every build.** The string
   `'The answer appears here from Skírnir's existing knowledge and answer gate.'` is single-quoted, and the
   apostrophe in **Skírnir** closes it early. `tsc --noEmit` therefore failed with `TS1005`, the app never built,
   `bin/desktop/app-build.sh` reported *3 built / 1 failed*, and the publish pretest refused the tarball — which
   is why `The gates` had been red on main since the Skírnir panel merged. Double-quoted; `tsc --noEmit` exits 0
   and the whole app builds. **This was the real, main-wide failure.**

2. **The config gate (Rule 07) flagged two sandbox paths that are not user paths.** It matches `/home/` as a
   substring, so a *test fixture* built as `$TMP/home/hodd/…` and a throwaway sandbox at `$SB/home/…` both read
   as hardcoded home directories. Fixed by naming the fixture honestly — `$YMIR_HOME/hodd/…` where it is the
   home being exercised, and `$SB/hodroot/…` where it is a sandbox root — never by loosening the gate.

3. **The mocks gate flagged a tool that is literally named `todo`.** `bin/mcp/ymir-mcp.py` mirrors Pi's own
   tool names so that every harness carries the same 31 doors; `def todo(...)` and the door list in
   `bin/seat/assets/hermes-soul.md.in` are *names*, not stubs. The packet's door list was reworded (it now says
   "the house's task board"), and the gate gained one documented exclusion: the `ymir-mcp.py` door file, whose
   whole purpose is to spell the tool names it mirrors. The exclusion is anchored on absolute paths
   (`^[^:]*bin/mcp/ymir-mcp\.py:[0-9]+:`) — the first version of it silently matched nothing, which is exactly
   the class of quiet no-op this house keeps paying for.

### Proven
- `npx tsc --noEmit` (apps/hlidskjalf) → **0**; `bin/desktop/app-build.sh` builds **4 / 4**.
- `bash .agents/skills/galdr-ymirsystem/scripts/compliance-check.sh` → `mocks … PASS (bin/ clean)`,
  `config … PASS`, and the rest of the 15 green.
- `bash bin/gates/tests/test_new_doors.sh` → **0 failures** (34 checks: the doors, the weave guard,
  `seat-surface --check`, the telegram registry refusals).
- `bash bin/gates/tests/test_hermes_seat.sh` → **0 failures**.
- `bash bin/gates/guards/weave-guard.sh` → `indexes: agree`.
- `bash bin/records/weave.sh --check` → `indexes: agree`; `bin/gates/registers.sh generate` run **after**
  `git add`, so the inventory counts the new doors.

### What the integration had to reconcile
Merging `eindri/catalogue-the-doors`, `eindri/weaver-hook-and-ci` and `eindri/telegram-every-machine` into one
branch produced nine add/add conflicts, all on the same doors: every errand branched from the same foundation
commit, so each carried its own copy of `bin/seat/seats.sh`, `bin/pi/arm.sh`, `bin/vault/push.sh`,
`bin/records/note.sh`, `bin/notify/telegram-machines.sh`, `bin/seat/hermes-telegram.sh`,
`bin/seat/seat-surface.sh`, `bin/seat/assets/hermes-soul.md.in` and `bin/gates/tests/test_new_doors.sh`. The rule
applied: **take the side that carries the later work per file**, not per branch — the catalogue errand's copies
were the foundation's (its work was the docs), the weaver's `weave.sh` was strictly better (it fixes a commented
row counting as an index entry and a SIGPIPE under `pipefail`), and the telegram errand's three files were
supersets. `main`'s versions won everywhere else.

**The lesson for the next overnight run:** four errands that all build on one unmerged foundation commit will
always produce this merge. The foundation belonged in its own pull request, merged first; it was not, and the
harvest cost an integration branch to repair.
