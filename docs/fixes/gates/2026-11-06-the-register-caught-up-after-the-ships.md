## gates · unversioned · 2026-11-06 — the register was right, and the drift was a stray

Three merges landed on `main` tonight (the ship ward, the heart's scheduler, the handoff-packet
schema). `registers-guard` then reported `bin/gates/capabilities.sh` **STALE**.

Regenerating it added one row — for `bin/well-vault-sync.sh`. That file turned out to be a
**stray**: an untracked, pre-restructure copy at the top level of `bin/` (83 lines) superseded by
the tracked `bin/time/well-vault-sync.sh` (104 lines, *"the log is the truth, the engram is
derived"*). The register had been reading a file the repo does not ship, which is exactly the state
a register must never be in: it described a tree nobody could check out.

The stray was preserved in the hoard (`hodd/state/strays/bin-well-vault-sync.stray-20261106.sh`)
and removed from the tree; the register was regenerated and now agrees with `origin/main` byte for
byte. **Nothing was hand-edited** — and the net diff of the generated file is empty, which is the
honest outcome: the register was stale because a phantom file existed, not because the register
was wrong.

Why it matters: the last time these aggregates drifted, four generated files carried 188 of the
last 200 commits between them (plan 180). A register that names an untracked file is the same fault
from the other side.

## CHANGE LOG

- 2026-11-06 · the stray removed (preserved in the hoard), the register regenerated, no hand edit;
  the first cut of this note blamed `schemas/`, which was wrong and is corrected here rather than
  edited away.
