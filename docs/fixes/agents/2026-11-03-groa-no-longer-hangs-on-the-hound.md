## agents · 2026-11-03 · Gróa no longer hangs on the hound

### What

`bin/agents/groa-update.sh` now bounds and detaches the two maintenance calls it makes after the
fast-forward — `bin/ward/garmr.sh refresh` and `groa-agent/seat.sh --quiet`. Each runs under
`setsid timeout -k 2` with its own stdin and output closed, so a refresh that waits on a console,
a polkit prompt or a missing unit can no longer stall the whole update.

And the cause beneath it: `bin/ward/garmr.sh refresh` probes `sudo -n true` before it writes the
hound's two system units. When sudo is not available without a password it leaves them alone with
a named refusal and still seats the operator's own brain timer, instead of blocking on a prompt
nobody will answer.

### Why

Gróa was reported as hanging: three runs were killed by hand after five minutes, and a fourth
never returned at all. A traced run (`bash -x`) printed every row and then stopped at exactly one
line:

```
+ /home/ymir/coding/ymir/bin/agents/../ward/garmr.sh refresh
```

and nothing after it. The hound's refresh had no timeout, and it is not the update: the tree was
already fast-forwarded, the migration applied and the seat identity checked before that line. A
maintenance nicety was allowed to hold the whole door shut. Under the bound, `seat_units` was then
seen waiting on `sudo tee /etc/systemd/system/garmr-hound.service` — a password prompt on a
terminal that does not exist.

### Files

- `bin/agents/groa-update.sh`
- `bin/ward/garmr.sh`

### Verified

- traced run, before: last line `+ .../ward/garmr.sh refresh`, no exit, process killed by hand.
- the same call alone: `timeout -k 3 12 bin/ward/garmr.sh refresh` also failed to return.
- after the hound's probe: `bin/ward/garmr.sh refresh` returns `rc=0` with

```
garmr: the hound needs root, and sudo is not available without a password here; its two system units were left alone
garmr: units re-rendered and reloaded (rules untouched)
```

- after the Gróa bound, a detached run completed with `exit=0` and printed every row:

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
