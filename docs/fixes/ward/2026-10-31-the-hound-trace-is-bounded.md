# The hound's trace is bounded — three classes, three policies

**Date:** 2026-10-31 · **Component:** ward · **Status:** live on heimdall, PR owed

## The fault, measured

`/var/log/ymir/garmr` held **20 GB** across **3,960 rotated files**, and the hound burned
**26.9 % of a core** for twenty hours (auditd 6.3 %). `common.rotate()` moves the findings file
aside at 5 MB and — by design, Rule 11 — never truncates it. Nothing ever removed the moved-aside
files, so a sensor trace grew without bound and the guardian spent its day reading and writing its
own noise: about **17,000 execve events a minute**, 5 MB of findings every two minutes.

## The law that had to be told apart

- **Records** (runes ledger, the well, plans, fixes) are append-only and are never retired by a
  sweeper — RULES/06, RULES/20.
- **Observations** (this trace) are a *sensor*, and a sensor trace is bounded, declared and rotated
  by policy — or the disk fills and the guardian becomes the fault it guards against.

## What changed

| file | change |
|---|---|
| `bin/ward/garmr/common.py` | `prune_rotations(path, keep)` — keeps the newest N rotated siblings and retires the rest; returns how many, never touches the live file |
| `bin/ward/garmr/hound.py` | class split + retention + dedupe + fast path: security events also to the kept shelf; `hound.exec.mode` (`first_seen` default, `all`/`none` declared); repeats of the same kind+target+comm inside `dedupe_seconds` folded into one row carrying a `repeat` count; a line with no `ymir-` key skipped before the field regex |
| `$YMIR_HOME/config/guardian.yaml` | the declared policy: rotate 5 MB, keep 48 (≈240 MB live), kept shelf 12 (≈60 MB), dedupe 300 s, exec `first_seen` |

## Measured after

- disk **20 GB → 245 MB**, files **3,960 → 52** on the first pass;
- hound CPU **26.9 % → 16.5 %** (exec policy) **→ 12.6 %** (fast path);
- `kept.jsonl` holds **929 bytes** — security events are genuinely rare, which is the point.

## What is still owed (needs root)

`/etc/audit/rules.d/ymir.rules` still records **every** execve (`-S execve -k ymir-exec`). Production
shape: narrow it to what a guardian needs — execution from world-writable trees
(`-F dir=/tmp`, `-F dir=/dev/shm`), privileged execution (`-F euid=0`), and the identity and
persistence watches already present. Then the remaining volume is signal, and the last of the CPU
goes with it.

Also owed: a `garmr status` readout (trace size · files retained · evidence-shelf size · last
escalation · whether the audit rules are missing and the senses are deaf), so the guardian can
answer *am I working?* without a human reading a directory listing.

## The reader's budget — the third fix (measured: 12.6 % → 4.6 %)

Cutting what the hound *wrote* was not enough, because a tailer that reads as fast as auditd writes is
not a guardian — it is a second load. The reader now has a **declared budget** in
`$YMIR_HOME/config/guardian.yaml`:

- `max_lines_per_tick: 4000` — bounded work per pass, so CPU follows *policy*, not traffic;
- `tick_seconds: 1.0` — the floor between passes;
- `lag_alert_bytes: 8388608` — past this backlog the hound writes **one** `kind: lag` finding saying
  it is behind, and clears it when it catches up. A guardian that goes quietly stale is the failure
  this house has paid for twice; a guardian that says "I am behind" is production.

The per-line test is now a substring before any regex — a record this hound wants carries
`key="ymir-…"` on its own line — so the ~17,000 records a minute that belong to other rules cost a
`find()`, not a parse.

**Measured across the three fixes:** 26.9 % → 16.5 % (exec policy) → 12.6 % (fast path) →
**4.6 %** (reader budget), with the novelty signal, the security shelf and the dedupe all intact.

**The last of it is at the source, and needs root.** Production shape for
`/etc/audit/rules.d/ymir.rules` — the same evidence, a fraction of the volume:

```
# keep: risk-bearing execution (this is the novelty signal that matters)
-a always,exit -F arch=b64 -S execve -F dir=/tmp       -k ymir-exec
-a always,exit -F arch=b64 -S execve -F dir=/var/tmp   -k ymir-exec
-a always,exit -F arch=b64 -S execve -F dir=/dev/shm   -k ymir-exec
-a always,exit -F arch=b64 -S execve -F euid=0         -k ymir-exec   # privileged execution
# drop: -a always,exit -F arch=b64 -S execve -k ymir-exec   (every exec, ~17k/min)
# keep unchanged: kill/tkill/tgkill · sensitive opens · identity · persistence
```

With that in place the hound's budget can be spent on freshness instead of on filtering, and the
guardian gets *better* at the same cost — which is what production means here.
