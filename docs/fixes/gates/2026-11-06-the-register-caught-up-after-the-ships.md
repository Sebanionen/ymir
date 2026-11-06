## gates · unversioned · 2026-11-06 — the capability register caught up after the ships

Three merges landed on `main` tonight (the ship ward, the heart's scheduler, the handoff-packet
schema). `registers-guard` then reported `bin/gates/capabilities.sh` **STALE** — the generated
aggregate had not been rebuilt in the same change as the code it describes.

The register was regenerated (`bin/gates/registers.sh generate`) and is committed here. Nothing
hand-edited: one line appears because `schemas/` and its fix note now exist.

Why it matters: a stale register is a ledger that lies about what the tree can do, and the ward
exists because the last time it drifted, four generated files carried 188-of-200-commit churn.

## CHANGE LOG

- 2026-11-06 · regenerated `capabilities`; no hand edit.
