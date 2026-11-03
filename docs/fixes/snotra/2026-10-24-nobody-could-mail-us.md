## snotra · 2026-10-24 — nobody could mail us, and every door said the inbox was empty

Plan 116 §15–§16. The Allfather's demand: *"users must be able to send email to all the
mails we are using. Otherwise it's pretty weird."*

### Files
- `bin/mail/gna_addresses.py` (new — the register behind the door: DNS MX by hand, routing, alias proof, arrival ledger, the acceptance plan)
- `bin/mail/addresses.sh` (new — the register of the addresses the house USES, with `--check`)
- `bin/mail/inbound-test.sh` (new — the acceptance test: ask → send from outside → assert the arrival, or SKIP with exit 3)
- `bin/mail/gna_import.py` — a second transport: IMAP beside the Google grant, by vault key name
- `bin/mail/gna_desk.py` — the honesty line, `GET /addresses`, `inbox_state` per account, `--honesty`
- `bin/mail/gna_store.py` — `document()`; `house_addresses()` reads mapping rows as well as strings
- `bin/mail/tests/test_gna.py` — 23 → 36 proofs, including a fixture IMAP server and a fixture resolver
- `bin/time/nornir-job-gna-mail.sh` — each round now reports whether anyone can mail us at all
- `bin/mail/README.md`, `docs/features/gna-the-one-mail-desk.md`, `FEATURES.md`, `.agents/assets/agents/subsystem-docs.md`, `.agents/skills/galdr-ymirsystem/assets/nornir-jobs.md`
- the home's `hodd/memory/mail/accounts.yaml` — the four `house:` rows the plan names, plus §16's inbound aliases

### Measured, tonight, over DNS and the grant
| claim | measurement |
|---|---|
| `zerwiz.org` can receive | **NO.** The DNS answer carries no MX record at all — every `@zerwiz.org` address is undeliverable, and the relay on `zerwizserver` sends only |
| `way-of.com` can receive | **YES.** Google Workspace MX (`aspmx.l.google.com`) is published, and the read-only grant we already hold reads the mailbox it delivers into |
| the Workspace aliases exist | **NO.** `GET /users/me/settings/sendAs` lists exactly one address, `<the operator's address>` — so `<the operator's address>` and `<the operator's address>` are `alias-missing`, one console step each |
| the desk could tell you that | it could not. It showed an empty queue, which reads exactly like "no mail today" |

### What now stands
`addresses.sh` reports per declared address the three facts that were being assumed — **mx**
(measured; a Null MX is a refusal, absent is absent), **route** (declared in the home, because
routing lives in a dashboard), **arrived** (a proof line only `inbound-test.sh` writes). An
address that cannot receive is `undeliverable`; an address with MX and a route and no proof is
`unproven`, never `deliverable`; a DNS answer that could not be read is `unmeasured` and fails
`--check` too. Exit `1` undeliverable · `2` register unreadable · `3` reachable-but-unproven · `0` proven.

`inbound-test.sh` asks before it sends — MX, route, and the alias through the account's own
read-only `sendAs` settings — then sends from an **outside** domain through the existing approved
send door, waits, and asserts the arrival's `To:` header came through intact. Today it prints the
missing record and exits **3**. It cannot pass on a guess, and it cannot pass by sending into a
domain with no MX.

The desk carries `deliverable · forwarded · unreadable` per address and an `inbox_state` per
account, so an empty queue now says *why* it is empty.

The importer reads `transport: imap` with host, port, TLS, user and password named **by vault
key**; the mailbox is opened `EXAMINE`-only and a test asserts no STORE, COPY, EXPUNGE, APPEND or
DELETE was ever issued. A row with no `imap:` block, a named key the vault lacks, and plaintext
off loopback are all refusals with the reason in them.

### Proofs run
```
bin/mail/gna_addresses.py --self-test      10/10   (fixture resolver: MX · absent · Null MX · unmeasured · outbox-only · alias-missing)
bin/mail/gna_import.py --self-test          9/9    (vault key names, refusals, a parsed message)
python3 bin/mail/tests/test_gna.py         36 tests OK (fixture IMAP socket, fixture DNS, honesty line, acceptance chain, no-send scan)
bin/mail/inbound-test.sh --self-test        7 tests OK
bin/mail/addresses.sh --check              rc=1   6 undeliverable · 1 unproven — the true state
bin/mail/inbound-test.sh                   rc=3   SKIP: alias-missing / no-mx, naming the record
bin/time/nornir-job-gna-mail.sh --check    rc=0   desk healthy, WARN with the undeliverable list
```

### Owed
Two console steps, not code: Cloudflare Email Routing for `zerwiz.org` (plan §15.2 records) or
the Workspace aliases for `way-of.com` (§16 — recommended, since that domain already receives).
Until one lands, `--check` fails by design. The next hand should re-run
`bin/mail/inbound-test.sh`; when it exits 0 the register has its own proof and `deliverable`
stops being a promise.

**2026-11-03 (correction, appended):** the operator's name and address were redacted from this note. They are personal data: they belong in the home, and a public fix note may say *the operator* and nothing more (RULES/04, RULES/06 — the correction is recorded, not the leak).
