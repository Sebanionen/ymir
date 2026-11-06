## time · unversioned · 2026-11-06 — the heart's scheduler stays up, and every caller reads ONE state dir

### Why

Two faults, both measured on the heart (zerwizserver) on 2026-11-06, and both of a kind that
turns a *declared* schedule into a silent one.

**1. The persistent seat was lost in the restructure.** Plan 51 Part 7 gave the always-on box a
scheduler that binds to the machine's role instead of a session: a headless seat has no session
lock, so the default retire-check would have killed the record crons every time it started. The
heart carried that guard as a local edit; the `bin/` restructure landed the file at
`bin/time/` **without** it, so the guard survived only in the old tree. When the units were
repointed at the pinned checkout, the scheduler started and retired at once — `cron: stopped
jobs=32` while the unit said `active`.

**2. The default state dir was the code tree.** With no `BROKK_STATE_OVERRIDE` the scheduler
defaulted `STATE="$BROKK_HOME/state"` — the *repo's* scratch. The units set the override, so
they were fine; every advisory caller (`ymir-validate`, a session start, a session-start digest)
was not. Measured: two schedulers over one `config/cron.yaml`, one under the unit with the
home's pidfile and one under the repo with its own — so `--status` answered "stopped" while a
loop was alive, and `nornir-cron-start.sh` spawned a rival beside it. This is the shape the
2026-09-23 orphan-loop fault had (eight loops from ended seats), reached from a new direction.

### What

Two changes in `bin/time/nornir-cron-start.sh`, and nothing else:

| change | detail |
|---|---|
| the persist guard returns | `BROKK_NORNIR_PERSIST=1` skips **both** the session-lock retire check and the machine-lock lookup it needs: a persistent seat never retires for want of a session. The drop-in `nornir.service.d/persist.conf` already sets the variable; before this commit it set it for a file that no longer honoured it |
| one state dir, the home's | with no explicit override, `STATE` resolves through `hoard-lib`'s `ymir_home_root` → `<home>/state`, and only falls back to `$BROKK_HOME/state` when there is no home at all. `ymir_home_root` is an **out-param** call (`ymir_home_root _hoard`), not a stdout call — the first cut of this patch called it as `$(ymir_home_root)` and got an empty string, which read as "no home" and quietly restored the old behaviour |

### Proof

- `bash bin/time/nornir-cron-start.sh` from a plain shell (no env) → `cron: running pid=… jobs=32`,
  and it spawns nothing; before, it printed `cron: started` and forked a second loop.
- `nornir.service` restarted against the pinned checkout `~/ymir-runtime` → one loop, alive
  after 30 s; `--status` agrees with the pidfile.
- `bash bin/engine/ymir-validate.sh` → `cron PASS`.
- The rival-state pidfile in the repo (`state/cron.pid`) is no longer written at all.

### Not done, and why

- The drop-in that sets `BROKK_NORNIR_PERSIST=1` lives in the **operator's** systemd tree, not
  in this repo; the repo change is only that the script honours it. A seat without the drop-in
  keeps the session-gated behaviour, which is correct for a dev body.
- No test ships here. The proof above is by measurement on the seat; a unit test would have to
  fake `systemd` and a `/proc` lock, and a fake of that shape proves nothing about the retire
  path it is meant to cover.

### The drift this removes

The pinned checkout at `~/ymir-runtime` briefly carried this file as a local modification, because
the heart's schedule was dead without it. With this merged, `bin/engine/runtime-deploy.sh` can
reset the pinned checkout without taking the heart's cron with it.

## CHANGE LOG

- 2026-11-06 · first cut: the persist guard restored at its new path, and the state default moved
  from the code tree to the hoard; the out-param bug in the first attempt named rather than hidden.
