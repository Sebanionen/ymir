# The one list names the file it runs — so the register can see the ward

**Date:** 2026-11-03 · **Component:** gate · **Found while:** proving the platform fix in CI

## What was wrong

`bin/gates/guards.sh` is the ONE list of tree wards. It held **bare stem names** and built the path as
`$ROOT/bin/gates/guards/$w.sh`, so the literal filename of a ward appeared **nowhere** in that file.

`bin/gates/inventory.sh` decides whether a door is alive by looking for its **filename in another door's
text** (`name in read(other)`), and `bin/gates/capabilities.sh` reads that verdict. So the moment two new
wards joined the list on 2026-11-03 — `path-legality-guard.sh` and `packaging-guard.sh` — the register
filed them as `orphan` / *"uncalled · **decide** — unnamed and untested: move it to src/ or hodd/reference/
(Rule 11), never delete"* while they were run on **every** invocation of `guards.sh`.

CI caught it (`capability` FAIL on the platform branch) and no local run did, because a working tree is
not the commit.

## What changed

- `WARDS=(… runtime-guard.sh … packaging-guard.sh …)` — each entry is the **file**, and the loop runs
  `$ROOT/bin/gates/guards/$w`. The list is still the one home; it now also *names* what it runs.
- Regenerated `bin/README.md` (caller counts) and `.agents/assets/agents/capabilities.md` from the tree.

## Why it matters beyond two rows

A ward that is called but invisible to the register is a ward the register invites you to **retire** — and
Rule 11 says a retired thing moves rather than disappears. The nearer fault: a new ward would look dead the
day it landed, and the honest reader would delete a live gate. Naming the file is what makes "appears in the
one list" mean "wired".

## Files

`bin/gates/guards.sh` · `bin/README.md` · `.agents/assets/agents/capabilities.md`
