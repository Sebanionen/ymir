## ward · 2026-11-03 · The hound asks for root, and renders from the pinned runtime

### What

Two faults in `bin/ward/garmr.sh`, both found while chasing a hanging Gróa.

`seat_units` now probes `sudo -n true` before it writes the hound's two system units. When sudo
needs a password it leaves them alone with a named refusal — and still seats the operator's own
brain timer — instead of blocking on a prompt no unattended run can answer.

The units it renders now name the **pinned runtime** (`YMIR_RUNTIME_DIR`, default
`$HOME/ymir-runtime`), falling back to the working tree only when no pinned checkout exists. Before,
every refresh re-pointed `garmr-brain.service` at whichever checkout the caller stood in, which the
`runtime-pinned-guard` refuses.

### Why

`bin/agents/groa-update.sh` hung on `garmr.sh refresh`; three runs were killed by hand after five
minutes. Under a timeout the refresh was seen waiting on `sudo tee /etc/systemd/system/garmr-hound.service`.
The same refresh then re-rendered the user unit from `$ROOT`, undoing the deploy that had just moved
the seat onto the pinned runtime.

### Files

- `bin/ward/garmr.sh`
- `bin/README.md`, `.agents/backend/README.md` (the door register, regenerated)

### Verified

```
$ bin/ward/garmr.sh refresh
garmr: the hound needs root, and sudo is not available without a password here; its two system units were left alone (run: sudo -v, then garmr.sh install)
garmr: units re-rendered and reloaded (rules untouched)
rc=0                       # returned in under a second; before, it never returned

$ grep ExecStart ~/.config/systemd/user/garmr-brain.service
ExecStart=/usr/bin/python3 /home/ymir/ymir-runtime/bin/ward/garmr/brain.py --once

$ bin/gates/guards/runtime-pinned-guard.sh
runtime-pinned-guard[1]{finding,detail}:
  "none","every unit names /home/ymir/ymir-runtime, and it stands on main"
```

The hound remains unarmed until the operator runs `sudo -v` once and then `bin/ward/garmr.sh install`;
that is a root act, and the door now says so instead of hanging.
