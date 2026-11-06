# The assistant's heartbeat is another seat's fact, not this one's

**Date:** 2026-11-06 · **Plan:** 203 §19 (six instances) · **Law:** `RULES/25`, `RULES/07`

## What was wrong

`bin/time/housewatch.sh` judged `$YMIR_HOME/hodd/state/assistant/telegram.heartbeat` as if the beat
belonged to the seat running the check. It does not: the home is **shared across seats**, so a beat
written on one machine is read as evidence on every machine — and an absent beat reads as *"no heartbeat
file yet — the service has not run here"*, which is the wrong sentence for a seat where the assistant is
never meant to run at all.

Measured 2026-11-06 while the ledger carried a repeating alarm — *"Skírnir has not polled Telegram for
179022s — he may be deaf"*:

```
measured[3]{where,finding}:
  "this seat (nidavellir)","no skirnir unit, no process, no beat file in the home"
  "the heart (zerwizserver)","`systemctl --user status skirnir.service` → Unit could not be found"
  "the shared home","no hodd/state/assistant/telegram.heartbeat anywhere"
```

So the alarm repeated about a mouth that was not on either seat, from a beat that had gone. The check was
reading a **local fact from a shared file** — the sixth instance of plan 203 §19, in the very script that
raises the alarms.

## The fix

The check now asks **whose mouth it is** before it judges the beat:

```
# A unit file is the evidence; `pgrep -f skirnir` was no good here, because the shell that runs
# this check carries the word in its own command line and matched itself.
if ! systemctl --user list-unit-files 2>/dev/null | grep -q '^skirnir[.]service'; then
  "assistant","SKIP","the assistant does not run on this seat - a beat in the shared home is another seat's fact"
elif [ ! -f "$ABEAT" ]; then
  ... the beat is judged, as before ...
```

A seat without the unit now says so, and a seat **with** it still raises the deaf alarm — the check is
narrowed, not switched off.

## How it was proved

- `bash -n bin/time/housewatch.sh` → clean.
- `bash bin/time/housewatch.sh` on this seat →
  `"assistant","SKIP","the assistant does not run on this seat - a beat in the shared home is another seat's fact"`
  and `housewatch{checked,failed}:"6","0"`.
- The first draft used `pgrep -f 'skirnir'`, which **matched the shell running the check** — its own
  command line carried the word. That is why the evidence is a unit file and nothing else; the wrong
  branch was caught by running it, not by reading it.

## Owed

The assistant itself: no `skirnir.service` exists on this seat or on the heart, and the home holds no
beat. Either it runs on a third machine (heimdall) or it was retired without the ledger being told. That
is a question for the Allfather, not a fix, and it is written here so the alarm is not mistaken for a
mouth.

## CHANGE LOG

- **2026-11-06** — first cut: the "whose mouth is it" gate, the unit-file evidence, the self-matching
  `pgrep` lesson, and the open question about where the assistant actually runs.
