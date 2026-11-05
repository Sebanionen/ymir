# The register follows the ward

**Date:** 2026-11-04 · **Component:** gate · **Doors:** `bin/gates/registers.sh`, `bin/gates/guards/registers-guard.sh`

Two generated registers describe this tree: `bin/README.md` (the bin inventory) and
`.agents/assets/agents/capabilities.md` (the capability register). Both are derived, both are
judged by `registers-guard`, and both went stale in the same change that mended the ward — the
inventory because `bin/ward/garmr.sh` grew from 254 lines to 266, the capability register because
the door set moved with it.

Regenerated with `bin/gates/registers.sh generate` and committed with the change they describe, as
the ward's own remedy says. The generator is reproducible, so the diff is one row each and the
numbers can be checked rather than trusted.

Nothing here changes behaviour: a register is a measurement of the tree, and this is the
measurement catching up to it.
