## install · 2026-11-03 — the weave driver is seated by install and by every update

### Why
The Allfather: *"the bin readme and the capabilities .md have conflicts AGAIN … we can not
use this files like we do either … conflicts all the time."* The files ARE marked
`merge=regenerate` in `.gitattributes`, and this seat had the driver — but **nothing
seated it automatically**. A merge driver lives in `git config`, not in the repo, so
every other clone (and every fresh one) still hand-merged a **generated** file and
collided on every branch that regenerated it.

### Mend
- `bin/engine/ymir-install.sh` seats `merge.regenerate.driver` beside the seat surface.
- `bin/agents/groa-update.sh` seats it on **every update**, so an existing clone that
  never had the driver is repaired by the next renewal.
- `features-guard` names the whole family when the driver is missing
  (*FEATURES.md · bin/README.md · capabilities.md*), not FEATURES alone.

### Proven
- The driver is seated: `git config merge.regenerate.driver` answers the weaver.
- With it seated, a branch that merged main resolved `bin/README.md` and
  `capabilities.md` by **re-weaving** (the register door and the merge of #483/#482
  earlier the same night) — no hand-merge, no conflict.
- `--install` is idempotent; the install and Gróa calls are silent and safe.
