## agents · 2026-11-03 · Gróa no longer hangs on the hound

### What

`bin/agents/groa-update.sh` now bounds and detaches the two maintenance calls it makes after the
fast-forward — `bin/ward/garmr.sh refresh` and `groa-agent/seat.sh --quiet`. Each runs under
`setsid timeout -k 2` with its own stdin and output closed, so a refresh that waits on a console,
a polkit prompt or a missing unit can no longer stall the whole update.

### Why

Gróa was reported as hanging: three runs were killed by hand after five minutes, and a fourth
never returned at all. A traced run (`bash -x`) printed every row and then stopped at exactly one
line:

```
+ /home/ymir/coding/ymir/bin/agents/../ward/garmr.sh refresh
```

and nothing after it. The hound's refresh had no timeout, and it is not the update: the tree was
already fast-forwarded, the migration applied and the seat identity checked before that line. A
maintenance nicety was allowed to hold the whole door shut.

### Files

- `bin/agents/groa-update.sh`

### Verified

- traced run, before: last line `+ .../ward/garmr.sh refresh`, no exit, process killed by hand.
- the same call alone: `timeout -k 3 12 bin/ward/garmr.sh refresh` also failed to return, so the
  fault is in the refresh, not in Gróa's bookkeeping.
- after the patch, a detached run completed with `exit=0` and printed every row:

```
groa[1]{state,root,remote,branch,mode}: "renew","/home/ymir/coding/ymir","origin","main","apply"
update[2]{id,target,state,detail}:
  "/home/ymir/coding/ymir","this Brokk home","skipped","dirty (7)"
  "-","registry","absent",".../eindri-homes.md (no Eindri-homes registered)"
seat-identity: ok	DESKTOP-FRS81OR	medusa
nudge-eindri-homes: none
exit=0
```

The overrides `YMIR_GROA_GARMR_TIMEOUT` (default 15s) and `YMIR_GROA_SEAT_TIMEOUT` (default 20s)
are the operator's if a slower machine needs longer.
