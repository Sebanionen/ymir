# The mail desk claims its own port — 8490 was gimle-share's

**Date:** 2026-11-06 · **Plan:** 203 §19 (the fifth instance) · **Law:** `RULES/07-config.md`, `RULES/24-the-ward.md`

## What was wrong

`gna-desk.service` was installed on `:8490` because a docstring and a README said that was the mail
desk's port. It is not: `config/services.yaml` declares **gimle-share** on 8490 — the team share-scene
on `whiteboard-ai.zerwiz.org` — and that process was already listening. Measured on the heart:

```
LISTEN 127.0.0.1:8490  users:(("python3",pid=1928101,...))
  1928101 /usr/bin/python3 /home/zerwizserver/gimle/desk/share-scene.py --port 8490 …
```

`gna-desk` started at 06:03, answered `GET /health 200`, and was stopped at 06:04 — so the mail desk,
the inbox the arm is told about, has been **down** since. A port copied out of a document is a local
fact quoted as a portable one, which is the fifth instance of plan 203 §19 and the only one that cost a
running service.

## The fix

**The mail desk moves to 8494, and the port is declared where ports are declared.**

- `config/services.yaml` (the home, private) gains an **operator** row: `gna-desk`, host `127.0.0.1`,
  class operator, gate *none — loopback only, GET only*, port **8494**, with the reason in the note.
  8490 stays gimle-share's, untouched.
- The default moves from 8490 to 8494 in the one place each consumer reads it: `bin/mail/gna_desk.py`
  (`--port` and `GNA_DESK_PORT`), `bin/mail/install.sh`, `bin/fleet/fleet-ensure.sh` (which templates
  the unit), and `bin/time/nornir-job-gna-mail.sh` (`DESK_URL`). `bin/mail/README.md` follows.

## How it was proved

- `python3 bin/mail/tests/test_gna.py` → **36 tests, OK** after the change.
- `grep -rn 8490 bin/mail bin/fleet/fleet-ensure.sh bin/time/nornir-job-gna-mail.sh` → nothing left in
  the mail path.
- On the heart, `8494` is free: `ss -ltn` shows 8491–8493 taken, 8494 free.
- `gimle-share` is still active and still holds 8490 — the incumbent is not disturbed.

## Owed

The heart's unit still names 8490 until `fleet-ensure` re-templates it from this commit, so the desk
comes back only after this lands and the unit is re-installed. That is the next step, and it is named so
nobody reads "tests pass" as "the desk is up".

## CHANGE LOG

- **2026-11-06** — first cut: the declared row, the four default sites, the unchanged incumbent, and the
  honest owed line.
