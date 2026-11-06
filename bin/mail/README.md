# Gná — the one mail desk (production)

**Gná** carries word and brings it back: she is the secretary who reads the accounts
she is scoped to, judges what a message is, and puts it in a queue with a proposed
action and the evidence for it. **She cannot send** — there is no send path in this
directory, and a test fails if one appears.

Law: plan 116 (`svartalfaheim/whynotproductions/projects/ymir/plans/`, in the home).
Page: `docs/features/gna-the-one-mail-desk.md`.

## What is here, and what is private

```
bin/mail/gna_store.py     the store: an account is the boundary; a read without one is refused
bin/mail/gna_judge.py     the judge: six classes · six actions · rules only · evidence always
bin/mail/gna_import.py    the importer: the Gmail API OR IMAP, read-only, one account, --dry-run
bin/mail/gna_addresses.py the register behind the door: DNS MX by hand, routing, arrival proofs
bin/mail/addresses.sh     the addresses the house USES, and whether mail can reach them (--check)
bin/mail/gna_desk.py      the desk: 127.0.0.1:8494, token + account scope, GET only
bin/mail/inbound-test.sh  the acceptance test: send from outside, assert the arrival, or skip
bin/mail/mail-scan.sh     the earlier one-shot read (kept — it proved the door opened)
bin/mail/install.sh       seats the desk as a systemd USER unit, restart-always
bin/mail/tests/           16 proofs, including "no file here can send"
```

The **store and the scope never live here**: they are the home's
(`$YMIR_HOME/hodd/memory/mail/` — `accounts.yaml`, `retention.yaml`,
`messages.jsonl`), and the message spine is git-ignored. Schema, scope and
retention travel; raw mail does not.

## Install and run

```sh
bash bin/mail/install.sh                 # unit: gna-desk.service, enabled, /health proven
bash bin/time/nornir-job-gna-mail.sh --check     # is the desk answering?
bash bin/time/nornir-job-gna-mail.sh --dry-run   # read the mailbox, write nothing
bash bin/time/nornir-job-gna-mail.sh             # import, then prove the desk
python3 bin/mail/tests/test_gna.py               # the proofs
```

The schedule is a Nornir row in the home's `config/cron.yaml`
(`bin/time/nornir-job-gna-mail.sh`), never an absolute path to one machine.

## The four columns

| Column | Meaning | Human act |
|---|---|---|
| **Needs you** | judged, an action proposed, nothing sent | approve · change · dismiss |
| **Unsure** | low confidence, or a sender the book does not know | assign · teach · dismiss |
| **Waiting** | outbound, no answer yet | nudge · close |
| **Done** | a notice recorded, or bulk mail that asked nobody anything | read only |

Every row carries `evidence`: the rule **and the word** that fired.

## The laws, in code

- **No send capability.** No SMTP, no draft creation, no Gmail send endpoint.
  `tests/test_gna.py::NoSendCapability` scans every file here.
- **An account is the boundary.** `require_account()` refuses a blank account and an
  account not declared in the scope file; `get_message()` refuses a message from
  another account's scope. The desk answers 400, not an empty list.
- **Absence is a failure.** `/health` reports counts, the last ingest and the
  declared scope; `nornir-job-gna-mail.sh` writes a FAIL line to
  `state/gna-mail.log` and a Rune when the desk or the mailbox cannot be read.
- **The spine is append-only.** A re-judgment appends a new line for the same `id`;
  readers take the latest. Retention is reported, never silently truncated.
- **Rules first; no model at P0.** A message the rules cannot judge lands in
  **Unsure** with low confidence instead of being guessed at.

## Can anyone mail us? Ask the register, never a document

`bin/mail/addresses.sh` is the door plan 116 §15.3.1 asks for: the addresses the house
*uses*, each measured for MX, routing, and a proven arrival.

```sh
bash bin/mail/addresses.sh            # TOON: address · domain · mx · route · arrived · state
bash bin/mail/addresses.sh --check    # nonzero when an address cannot receive
bash bin/mail/addresses.sh --aliases  # re-measure the Workspace aliases (read-only sendAs)
bash bin/mail/inbound-test.sh         # send from outside, wait, assert — or skip with the reason
```

Three facts per address, and none of them is an assumption:

- **mx** — measured over DNS with the resolver's own query (no `dig` dependency, Rule 07:
  `$GNA_DNS_SERVER`, else `/etc/resolv.conf`). A domain with no MX is `absent`; a Null MX
  (RFC 7505) is a deliberate refusal, not a mailbox.
- **route** — *declared* in the home's `accounts.yaml` under `house:` (routing lives in a
  dashboard, not in DNS), so the register can say "explicit" or "catch-all" honestly.
- **arrived** — *measured*: a proof line in `hodd/state/mail/inbound-arrivals.jsonl`, written
  only by `inbound-test.sh` when a message actually landed with its `To:` intact. Until one
  does, a routed address is **unproven** — `deliverable` is something a machine measured.

`--check` exits `1` when an address is undeliverable, `2` when the register cannot be read,
`3` when everything is reachable but nothing is proven, and `0` only when it is all proven.
Measured 2026-10-24: `zerwiz.org` publishes **no MX at all**, so `gimle@`, `snotra@`,
`reply+*` and `bounce+*` there cannot receive; `way-of.com` publishes Google MX, and the
Workspace aliases do not exist yet — the register says `alias-missing`, naming the console
step, rather than showing an empty inbox.

## The desk's honesty line

`bin/mail/gna_desk.py --honesty` prints, per address, `deliverable · forwarded · unreadable`;
`GET /addresses` returns the same as JSON; `GET /queue` carries it beside the four columns,
with an `inbox_state` per account (`arrivable` · `declared-only` · `cannot-arrive`) and a
`notice` that says why. **An empty queue can never again be mistaken for "no mail" when
nothing could arrive**: the desk renders the reason.

## Reading a mailbox that is not Gmail

An account row names its transport, so a store the house runs itself needs no rewrite:

```yaml
  - id: team@example.org
    transport: imap
    imap:                       # these are NAMES of vault keys, never values
      host_key: GNA_IMAP_HOST
      port_key: GNA_IMAP_PORT   # optional — 993 (IMAPS) when absent
      tls_key:  GNA_IMAP_TLS    # optional — ssl (default) · starttls · none (loopback only)
      user_key: GNA_IMAP_USER
      password_key: GNA_IMAP_PASSWORD
      mailbox: INBOX            # optional
```

The reader opens the mailbox with `EXAMINE` (`readonly=True`) and never issues STORE, COPY,
EXPUNGE, APPEND or DELETE — a test asserts it against a real fixture IMAP server. A row that
declares `transport: imap` with no `imap:` block is **refused** ("no IMAP account is
declared"), a key named but absent from the vault is refused by name, and plaintext TLS off
loopback is refused outright.

## Not built yet (plan 116, in order)

Drafts and approvals (P1) on the same gate · a second account with its own grant
(P2) · the agent door `mail_search · mail_thread · mail_draft` (P3) · rules that
earn their place (P4). None of them may add a send path.

## Appended 2026-10-24 — the send path she is owed goes through the gate, not around it

Plan 116 P1 (drafts and approvals) is still owed, and this line is the debt written down before anyone pays it
(today it was only a hope, which is how a hole opens): **when Gná's draft and send verbs land they must call
`systems/snotra/services/approve/snotra-approve.sh gate mail <draft-id>` before any send, exactly as `mail-send.sh send` does.**
No SMTP, no `users/me/drafts/send`, no socket of her own — the gate is the only socket in the house (plan 124 §7).

The two wards that keep this honest are already standing: `tests/test_gna.py::NoSendCapability` fails if a send
pattern appears in any file here, and
`bin/time/snotra/tests/test_outbound_gate.py::GnaOwed` fails if a send in `bin/` does not name the gate.
