# The watch heard its own hands

**Date:** 2026-11-04 · **Component:** snotra · **Door:** `systems/snotra/services/ear/snotra-detect.sh`

## What the Allfather saw

*"why are we using 33% cpu"* — then, after the boot burst had settled, *"ots still 20% and
were doing nothing"*. He was right: the machine had work in it, and none of it was his.

## What it was

The meeting watch runs a loop that reads the PipeWire bus with `pactl subscribe` and calls
`tick` after every event. `tick` calls `snapshot`, which opens **four `pactl` clients and a
`python3` interpreter**. Every one of those clients connects and disconnects on the **same
bus the watch is listening to**. So each tick generated the events that woke the read that
ran the next tick: a closed loop with no floor in it.

Measured on this seat, idle, no call in progress:

```
broken[4]{measure,value,how}:
  "forks","178/second","/proc/stat processes delta over 15s, nothing of the measurer's own in flight"
  "child CPU","0.85 of one core","1286's cutime+cstime delta: 1014 ticks in 12s"
  "bus events","96/second","timeout 5 pactl subscribe | wc -l => 479 while running, 0 when stopped"
  "box busy","11-13% of 16 cores","falls to 5% when the watch is stopped, and returns when it starts"
```

The audio stack looked guilty first — `wireplumber` had banked **39m 40s of CPU over 4h 58m**
across one session — but it was innocent: it was servicing those 178 client registrations a
second. Stop the watch and WirePlumber, PipeWire and pipewire-pulse all go quiet on their own.

## The mend

A tick is now spaced. `TICK_MIN_GAP_MS` (default 1000, `SNOTRA_TICK_GAP_MS`) is a floor
between ticks; when one is not yet due, the loop **blocks** on the bus for the remainder with
a fractional-timeout `read` and swallows what arrives. Blocking, not polling: a `read -t 0`
drain loop was tried first and spun at **97% CPU** — the guard became the cost. Both guards
are shell builtins, so spacing the ticks forks nothing.

```
mended[3]{measure,value}:
  "its own CPU","0.03 of one core (47 ticks in 15s), against 0.85 before"
  "forks","68/second, against an idle baseline of 65/second — the watch adds almost nothing"
  "box busy","5% of 16 cores, the floor with the watch idle"
```

## The second fault, found on the way

**The door could not run at all.** `systems/snotra/services/ear/snotra-detect.sh` carried the
*retired shim's* path guard verbatim: it computed its target as `$_d/../../../`, which from
`systems/snotra/services/ear` is `<repo>/systems`, not the repo root — so the file always
concluded it was missing and exited **127**. It had been copied in from `bin/time/snotra/`,
where three levels up *was* the root. Both the door and the shim that execs it are dead on
main today:

```
$ bash systems/snotra/services/ear/snotra-detect.sh status
snotra: the door moved to systems/snotra/services/ear/snotra-detect.sh and is not there
exit=127
```

What kept the watch alive was the **stale installed copy** in `~/.fleet` — 1091 lines dated
2026-10-23, older than the door's move — which `fleet-ensure` had not refreshed. The guard is
removed here: this file *is* the door, and a door has nothing to point at.

## What changed

- [x] `systems/snotra/services/ear/snotra-detect.sh` — `TICK_MIN_GAP_MS` beside `POLL_SECONDS`;
      the `run()` loop spaces its ticks and blocks instead of spinning; the shim guard removed.
- [x] this note.

## What did not change

- The capture, the arm/leave gates, the probes and the summarizer path are untouched. The watch
  still answers `status`, still arms inside a second of a call beginning.
- `~/.fleet/snotra-detect.sh` was refreshed from this file so the live watch stopped burning the
  core before the PR was sealed. Until this merges, the installed copy is *newer* than main —
  the reverse of the drift that hid the bug, and the PR is what closes it.
- The affected unit was restarted, not redesigned: one process, one door, same state.
