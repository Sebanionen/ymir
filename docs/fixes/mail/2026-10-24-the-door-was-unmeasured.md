## mail · 2026-10-24 — the desk was honest about the mailbox and silent about the door

Plan 116 §15.3 (and §16, which corrects it the same evening). The full record — files,
measurements, proofs and what is owed — is the snotra note of the same day:
`docs/fixes/snotra/2026-10-24-nobody-could-mail-us.md`. This note exists because `bin/mail/`
is the component whose shape moved, and a hand looking here must find it.

### Files
- `bin/mail/addresses.sh` · `bin/mail/gna_addresses.py` (new — the register: MX by hand, declared routing, alias proof, arrival ledger)
- `bin/mail/inbound-test.sh` (new — ask → send from outside → assert the arrival, else SKIP exit 3)
- `bin/mail/gna_import.py` (IMAP beside the Google grant, host/port/TLS by vault key name)
- `bin/mail/gna_desk.py` (`--honesty`, `GET /addresses`, `inbox_state` per account)
- `bin/mail/gna_store.py` (`document()`; a `house:` row may be a mapping now)
- `bin/mail/tests/test_gna.py` (36 proofs: fixture IMAP socket, fixture resolver, honesty line, acceptance chain)
- `bin/time/nornir-job-gna-mail.sh` (every round reports undeliverable addresses as a WARN)

### The fault, measured
`zerwiz.org` publishes **no MX record**, so `gimle@`, `snotra@`, `reply+*` and `bounce+*` there
could not receive a single message — and the desk rendered an empty queue, which is
indistinguishable from "no mail today". `way-of.com` publishes Google Workspace MX and already
receives; its aliases (`gimle@`, `snotra@`) do not exist yet: `sendAs` on the account lists only
`<the operator's address>`.

### The rule this leaves behind
**A mailbox the desk can read is not a mailbox anyone can write to.** Two different questions,
two different measurements, and the desk now carries both: an address is `deliverable` only
after a real message from outside has landed with its `To:` intact, and `unproven` until then.
`--check` exits nonzero rather than let an empty page read as a healthy one.

**2026-11-03 (correction, appended):** the operator's name and address were redacted from this note. They are personal data: they belong in the home, and a public fix note may say *the operator* and nothing more (RULES/04, RULES/06 — the correction is recorded, not the leak).
