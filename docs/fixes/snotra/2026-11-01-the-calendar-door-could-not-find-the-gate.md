# 2026-11-01 — the calendar door could not find the gate

**Component:** snotra · **Door:** `systems/snotra/services/calendar/calendar-invite.sh`

## What happened

A meeting was asked for and the door refused: *"the word was not good enough: bash:
/home/heimdall/ymir/systems/bin/time/snotra/snotra-approve.sh: No such file or directory"*.

Two paths were one `..` short after Snotra became a system (plan 129). The script sits at
`systems/snotra/services/calendar/`, so its root is **four** levels up, not three — and the gate it calls had
itself moved from `bin/time/snotra/` to `systems/snotra/services/approve/`.

```
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"   # → ~/ymir/systems
APPROVE="$ROOT/bin/time/snotra/snotra-approve.sh"               # → does not exist
```

The effect was worse than a broken command: **every invitation and every cancellation with an attendee was
refused**, because the gate check could not run. The door failed safe — nothing was posted and nobody was mailed —
but the capability was dead and the message blamed the approval rather than the path.

## The fix

```
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"          # → ~/ymir
APPROVE="$ROOT/systems/snotra/services/approve/snotra-approve.sh"          # the gate's real home
```

## Proof

The same command that had been refused then created the event and mailed both attendees:

```
created 8gnqs1fc7ik8sto1m0fhcbifs0
meet    https://meet.google.com/ewn-doph-vfd
mail    all
```

Read back through the Calendar API: title *Trello and Control Tower — how we work*, 2026-11-03 09:00–10:00
Europe/Stockholm (08:00Z), status `confirmed`, both attendees `needsAction`, and the approval recorded as
**SENT** — spent by the one post that used it, as the gate requires.

## Owed

A note that the same one-`..`-short pattern may exist in the other Snotra doors that were moved in plan 129: a
door that calls a sibling by path should be checked against the tree it now lives in, not the tree it was written
in.

## The same fault, twice — appended after the mail door refused

The approval gate itself carried the identical error. `snotra-approve.sh` resolved its root one level short and
pointed at `$ROOT/bin/time/snotra/mail-send.sh`, so approving a draft failed with *"cannot read the bytes"* and the
send that followed was refused — correctly, because the word could not be recorded.

```
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"       # → ~/ymir/systems
MAIL="$ROOT/bin/time/snotra/mail-send.sh"                            # → does not exist
```

Both are now four levels up and point at `systems/snotra/services/…`. Proved end to end: the agenda letter to two
counterparts was drafted, approved (`approved mail r6123598373090961464`), and sent (`1a19877c54a87a4b`).

**The lesson is the phase-2 task, and it is now urgent:** every Snotra door that calls a sibling by path was moved
in plan 129, and at least two of them kept the old depth. A door that cannot find its own gate is a door that
refuses everything, and the refusal blames the wrong thing.

## The sweep — appended after the two fixes

The same fault was hunted across the tree rather than fixed where it was found: every `.sh` under
`systems/snotra/` that resolves its root by counting `..` was compared against the depth it actually sits at.
**Nine more doors were one or more levels short** — `calendar-ask`, and eight under `cron/` and `ear/`
(`snotra-cron`, `snotra-route`, `snotra-rules`, `snotra-card-moves`, `snotra-friday-synch`, `snotra-grooming`,
`snotra-ingest`, `snotra-live`). Each now resolves to the repository root. Fifty-nine files were scanned; the ones
that were right were left alone.

## The address ward — appended the same evening

The delivery notification that started this said a message to `<a personal address>` could not arrive because
that domain's mail exchanger is `127.0.0.1`. The register could already measure an MX (`mx_state`), but the **send
path never asked it**.

- `bin/mail/gna_addresses.py` gained an `mx` action: one domain, one verdict, exit 0 only when it is `present`.
- `mail-send.sh` gained `guard_recipients`: before a draft is created it asks the register about every recipient
  domain, and refuses with the measurement — *"a letter to a domain with no mail exchanger is lost, not sent"*.

Measured: `<a personal address>` → refused, naming *"thegleemachine.com publishes no MX record"*;
`craig@way-of.com` → drafts normally.

## The memory index — appended the same evening

`bin/records/mimir-log.sh reseed` failed with `TypeError: Engram.observe() got an unexpected keyword argument
'provenance'`: the log was written and the index was not, so a lesson could be stored and be unfindable. It now
reads the engine's own signature and passes only what it accepts. **Measured after the fix: 58 memories observed,
104 already present** — fifty-eight lessons that had been written and never indexed are now searchable.
