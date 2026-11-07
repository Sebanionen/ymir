## docs · 2026-11-04 — the doors are catalogued, and the six that lied while being written down

### Why

Twelve user-facing doors were built on 2026-11-04 — `plan · note · header · grade · weave ·
layout`, `seats · hall · arm`, `telegram-machines · hermes-telegram`, `push` — and **not one had a
page**, so not one was finished (Rule 14). A door no user can find is a door that does not exist;
a page the catalogue does not name is a page no user finds. This note is the catalogue's record.

### Mend — the pages

Written for the **operator**, never the agent: *what it is · what you need · the commands · the
limits · if it does not work*, grouped so a person finds a task, not one page per flag.

- `docs/features/the-records-shelf.md` — the ledger's next number, the append-only note, the
  declared header, the Norse grade, the placement oracle, the weaver (`--check`, `--fix`,
  `--fix-count`), and the feature ward.
- `docs/features/the-seats-and-the-arm.md` — `seats` (either backend, dead shells named, `close`
  refuses a live seat), `hall` (the whole house in one read), and the arm per harness: which can be
  armed, which cannot, and what to install.
- `docs/features/telegram-across-the-fleet.md` — the machine registry, `list · me · relay`, the
  honest limit (no bot can list members), the relay's Runes hop, and what the Hermes ears can and
  cannot do yet.
- `docs/features/the-home-push-door.md` — named paths only, never `-A`, and why.

Four fragments added under `docs/features/_catalogue/entries/`
(`00-018 · 00-019 · 01-010 · 04-007`) and `FEATURES.md` **woven**, never hand-edited. The four
pages are also pointed at from `docs/features/README.md`, which is hand-kept and had no rows for
them. The Telegram registry finally has the stub its own error message has been pointing at since
it was written: `hodd/identity/machines.yaml.example` (placeholders only, no bot id, no chat id, no
token — named `*.example` because `hodd/.gitignore` admits only that shape).

### Mend — the six doors that lied

Writing a page for a door is the fastest way to find out that the door does not do what it says.
Each of these was measured before it was corrected.

1. **`features-guard.sh` passed by printing its own help.** A bare invocation matched the
   `-h|--help|""` branch **first** and exited 0 — so the ward Rule 14 rests on answered *nothing*
   and returned success. The gatekeeper of the catalogue was the one thing in this errand that
   could not fail. `check` is now the default branch, and a bare run prints a real finding list.
2. **`seats.sh list` was a raw herdr JSON dump** (the door's own header promises panes with states
   and dead shells named), and **`close` could not refuse a live seat**: it grepped
   `"pane_id":"<id>"[^}]*`, and in herdr's object `pane_id` arrives *after* `agent_status`, with a
   nested `}`, so the fragment it inspected never carried `agent_status` at all. Measured:
   `grep -o '"pane_id":"w3:pB"[^}]*'` returns a fragment ending inside `scroll`. It now parses the
   pane's own record and refuses on it; `list` renders `pane · agent · state · dir · title` with
   `DEAD` for a bare shell inside a disposable `.yggdrasil/` worktree.
3. **`hall.sh` printed `doors: 0` over 612 doors** — it counted lines matching a markdown table
   (`| foo.sh |`) in a file that is TOON (`  "foo.sh",`). A door that reports zero over a full
   shelf is the false green this house keeps paying for. It also parsed `--runes N` and never used
   it; the ledger tail now shows the last N entries with their dates and actors.
4. **`note.sh --help` printed two lines of the script** below the comment block (an off-by-two in
   the `sed` range).
5. **`telegram-machines.sh` advertised two actions it never had** (`token`, `count`), and its `me`
   called `bin/notify/telegram-members.sh`, which **did not exist in this tree when the door was
   written**. `me` first asked `getMe` itself; then PR **#498** landed `telegram-members.sh` the same
   night, so `me` now **delegates to it** — and `count · admins · chat · who` pass through it too,
   asked with the named machine's own bot. Two faults found while wiring that: the phantom `token`
   action is gone, and `emit_token` under `pipefail` **aborted the caller with no message at all**
   when the vault held no token for a machine — the door now refuses in words, which is the only
   kind of refusal a person can act on. The limit is written in the door's own header and is
   Telegram's, not ours: a bot cannot enumerate ordinary members, only the chat, the count, the
   administrators and one known user ([who is in a Telegram chat](telegram-members.md), [the roster](telegram-roster.md)).
6. **`push.sh` promised "refuses to delete a tracked file" and did not.** It staged and committed
   whatever it was given, including a deletion — the one irreversible mistake a vault can make
   (Rule 11: retire by MOVING). It now refuses before staging, gained `--dry-run`, and stopped
   calling "nothing to commit" a failure.

And the test that was supposed to catch #2 could never fail: its body ended
`|| true`. It is now a real assertion — pick the first pane the door reports as live and prove
`close` refuses it — plus two regressions: `list` must never emit a raw JSON dump, and the hall's
door count must not be zero.

7. **`home-contract-guard.sh` carried the same false green as #1** — a bare invocation printed its
   help and exited 0. The contract ward now judges when it is given no argument. It also caught the
   real fault this pass introduced: the shipped registry stub was a **template no home receives**
   (Rule 42). Its row now stands in `.agents/home-contract.yaml` (`hodd/identity/machines.yaml`,
   kind `stub`, `required: false`), so `bin/engine/home-seed.sh` copies it into a fresh home instead
   of the door pointing at a shape that lands nowhere.

### Proven (commands and their answers)

```
bin/gates/guards.sh                     → every ward PASS (23 of 23)
bin/gates/guards/features-guard.sh        → "none" — every feature page is catalogued, the woven
                                            catalogue is current (bare invocation, i.e. the check)
bin/records/weave-features.sh --check     → FEATURES.md is current (161 entries)
bin/records/weave.sh --check              → indexes: agree
bin/gates/inventory.sh --check            → bin/README.md current (732 files) · backend (176)
bin/gates/tests/test_new_doors.sh         → 14 ok, 1 pre-existing failure (named below)
bin/seat/seats.sh list                    → backend: herdr; 18 panes; 4 named DEAD
bin/seat/seats.sh close w3:pB             → refused: w3:pB holds a live agent (pi, done)  [rc=1]
bin/seat/seats.sh close no:such:0:0       → no such pane                                    [rc=1]
bin/agents/hall.sh                        → seat · 612 doors · 0 pending wakes · last 5 runes
bin/pi/arm.sh status                      → watch unit active · arm possible
bin/pi/arm.sh hook codex                  → "cannot be armed mid-session (named, never faked)"
bin/records/plan.sh next                  → 179
bin/records/grade.sh hodd/docs/INDEX.md   → nýr 0d
layout.py classify hodd/docs/runbooks/x   → legal: True · hodd/docs/runbooks/
layout.py classify hodd/random/thing.md   → legal: False, and the shelf list          [rc=1]
telegram-machines.sh list                 → one row per machine: bot id · chat · token_ref
telegram-machines.sh me <host>            → refused: no TELEGRAM_BOT_TOKEN in its vault ref
telegram-machines.sh count <host> --chat  → the same refusal, in words (never a silent exit)
hermes-telegram.sh check                  → exit 1, "no platform attached … hermes gateway setup"
push.sh --dry-run "…" <path>              → the dry-run block, ` M <path>`, nothing staged
```

`push.sh` was proved **end-to-end against a throwaway home and a bare origin** (never the real
home), with `YMIR_HOARD` pointed at it: a named-path push committed and pushed; a second push
answered `nothing to push` (exit 0); and a deleted tracked file was refused. The temp origin's log
showed two commits and only the named file.

`relay` and `close <dead pane>` were deliberately **not** run: one sends a real Telegram message,
the other closes another errand's shell. Both are documented as untested-in-this-pass on their
pages rather than claimed.

### Named, not fixed

`bin/seat/seat-surface.sh --check` fails inside a fresh Yggdrasil worktree — `~/.hermes.md` is
not rendered there — and it fails identically on the foundation commit (proved with
`git stash`), so it is not this errand's. The Hermes parity errand owns it.

### Private data

Nothing private entered this public repository with these pages: no hostname, no user path, no
machine name, no bot id, no chat id, no plan title, no rune count from the operator's ledger. The
pages show the **shape** of an answer with placeholders, and the registry stub ships empty; the
real `machines.yaml` stays in the home, where Rule 04 says it lives.

### Files
- `docs/features/the-records-shelf.md`, `the-seats-and-the-arm.md`,
  `telegram-across-the-fleet.md`, `the-home-push-door.md` — the four pages
- `docs/features/_catalogue/entries/{00-018,00-019,01-010,04-007}-*.md` — the four rows
- `docs/features/README.md` — points at the four pages
- `FEATURES.md` — woven from the fragments (never hand-edited)
- `hodd/identity/machines.yaml.example` — the registry stub, placeholders only
- `.agents/home-contract.yaml` — a row for that stub, so every fresh home receives it (Rule 42)
- `bin/gates/guards/home-contract-guard.sh` — `check` is the default; a bare run judges
- `bin/gates/guards/features-guard.sh` — `check` is the default; a bare run judges
- `bin/seat/seats.sh` — a readable table, `DEAD` named, and a refusal that fires
- `bin/agents/hall.sh` — the real door count, and `--runes N` honoured
- `bin/records/note.sh` — help prints help
- `bin/notify/telegram-machines.sh` — `me`/`count`/`admins` delegate to the member door; phantom actions removed; a silent exit turned into a refusal; the member limit written down
- `bin/vault/push.sh` — refuses a deletion, `--dry-run`, honest exit codes
- `bin/gates/tests/test_new_doors.sh` — the vacuous live-seat test made real, two regressions added
- `bin/README.md`, `.agents/backend/README.md`, `.agents/assets/agents/capabilities.md` —
  regenerated by `bin/gates/registers.sh generate`
