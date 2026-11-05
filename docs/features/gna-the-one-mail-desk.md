# Gná — the one mail desk

**What it is.** One page that answers *"what needs me?"* across the mailbox Ymir reads. It is not a
mail client: there is no send button, no draft box, and no way to widen it to another account. Each
message arrives judged — six classes, six proposed actions — and every row shows the rule **and the
word** that gave it. **Gná** is the messenger who carries word and brings it back; she drafts, she
never speaks for the Allfather.

**What you need.** A scoped account in the vault (the Gmail grant), and the desk service raised. The
store lives in the home (`hodd/memory/mail/`), never the repo — and the message bodies themselves are
git-ignored: schema, scope and retention travel, raw mail does not.

**The commands**

```sh
cd "$YMIR_HOME/hodd/bin/gna-agent"

python3 gna_import.py --account <the scoped account> --days 7 --dry-run   # read, write nothing
python3 gna_import.py --account <the scoped account> --days 7             # fill the store

python3 gna_desk.py            # the desk on 127.0.0.1:8490 (token: hodd/state/gna-desk.token)
python3 gna_desk.py --print-token

python3 tests/test_gna.py      # 16 proofs, including "no file here can send"
```

Then open **Hlidskjalf → Gná**. The page forwards three routes
(`/api/mail/accounts`, `/api/mail/queue`, `/api/mail/message`) to the desk with its token, and the
desk's refusals come back unchanged.

**The four columns**

| Column | What it means | What you do |
|---|---|---|
| **Needs you** | judged with confidence, an action proposed, nothing sent | approve · change · dismiss |
| **Unsure** | low confidence, or a sender the book does not know | assign · teach · dismiss |
| **Waiting** | outbound, no answer yet | nudge · close |
| **Done** | a notice recorded, or bulk mail that asked nobody anything | read only |

**The limits — read these as promises**

- **Machine sends: zero.** No SMTP, no draft creation, no Gmail send endpoint exists in the desk, and
  a test fails if one appears.
- **An account is the boundary.** A query without an account is refused (HTTP 400), and so is a
  message fetched through another account's scope. The UI hiding things is not a boundary; the store
  refusing is.
- **Rules only at this phase.** No model sees a mailbox. A message the rules cannot judge lands in
  **Unsure** with low confidence instead of being guessed at.
- **Read-only in the gate.** Drafts and approvals (plan 116 · P1) are not built yet; the page cannot
  send, and neither can the service behind it.

**If it does not work**

| Symptom | What it means | The mend |
|---|---|---|
| The page says *"the desk has no token yet"* | the desk has never run | `python3 gna_desk.py` in `hodd/bin/gna-agent` |
| *"the desk did not answer at 127.0.0.1:8490"* | the service is down | raise it, or check `ss -tln \| grep 8490` |
| *"account scope required"* | no account was chosen | pick one at the top; one must be declared in `hodd/memory/mail/accounts.yaml` |
| *"account not declared in …"* | that address has no grant row | add the row **with its own grant** — never widen another account's |
| Everything reads as **Unsure** | the sender is not in `collaborators.yaml` | add the person (or teach a rule in P4) — a stranger is meant to wait |
| A bulk newsletter wants your judgement | its `List-Unsubscribe` / `Precedence` header is missing | that is the rule's evidence; the row says which marker it looked for |

**Measured 2026-10-23.** Seven days of the operator's own mailbox: 61 messages → **needs you 5 · unsure 1 ·
waiting 20 · done 35**, machine sends 0. The first run judged a forwarded meeting recap as an
*invoice* and put 35 newsletters in Unsure; the fix was evidence that names the word, and a bulk rule.

---

## Can anyone mail us? (added 2026-10-24, plan 116 §15–§16)

The desk answered *"what is in the mailbox?"*, and that was not the same question as
*"can mail arrive at all?"*. Measured on 2026-10-24: `zerwiz.org` published **no MX
record**, so `gimle@zerwiz.org`, `snotra@zerwiz.org`, `reply+*@zerwiz.org` and
`bounce+*@zerwiz.org` could not receive anything — while the desk showed an empty inbox
that looked exactly like "no mail today". Three doors now close that gap.

**The register — `bin/mail/addresses.sh`.** One row per address the house uses: whether the
domain publishes MX, whether the address is explicitly routed or caught by a catch-all, and
whether a test message has actually arrived. An address that cannot receive is reported
`undeliverable`, never assumed good.

```sh
bash bin/mail/addresses.sh            # the register, TOON
bash bin/mail/addresses.sh --check    # nonzero when an address cannot receive
bash bin/mail/addresses.sh --aliases  # re-measure the Workspace aliases (read-only)
```

The addresses are declared in one place — `$YMIR_HOME/hodd/memory/mail/accounts.yaml`,
under `house:` — with the routing a human declared and the account it forwards to.
`--check` exits 1 for an undeliverable address, 2 when the register cannot be read, 3 when
everything is reachable but nothing is *proven*, and 0 only when a message has arrived.

**The honesty line — the desk.** `python3 bin/mail/gna_desk.py --honesty`, `GET /addresses`,
and every `GET /queue` answer now carry, per address, `deliverable · forwarded · unreadable`,
plus an `inbox_state` for the account: `arrivable` (proven), `declared-only` (MX and a route,
no arrival proof) or `cannot-arrive` (with the reason spelled out). The desk can never show
an empty inbox where nothing was able to land.

**The acceptance test — `bin/mail/inbound-test.sh`.** It asks first, then sends from an
outside address through the house's approved send door, then waits for the arrival and
asserts the `To:` header came through intact. When the address cannot receive it prints
exactly what is missing and exits **3** — a skip with a reason, never a pass.

```sh
bash bin/mail/inbound-test.sh                    # the registry's acceptance address
bash bin/mail/inbound-test.sh --to gimle@zerwiz.org
bash bin/mail/inbound-test.sh --mx-only          # only "could mail arrive here at all?"
bash bin/mail/inbound-test.sh --self-test        # the proofs, offline
```

**Reading a mailbox that is not Gmail.** An account row may declare `transport: imap` with
host, port, TLS, user and password named **by vault key** (`host_key`, `port_key`, `tls_key`,
`user_key`, `password_key`) — never as values. The IMAP reader is read-only (`EXAMINE`, no
STORE/COPY/EXPUNGE/APPEND/DELETE), refuses a row with no `imap:` block, refuses a named key
the vault lacks, and refuses plaintext off loopback.

**What is still missing, exactly.** `zerwiz.org` has no MX: the Cloudflare Email Routing
records are in plan 116 §15.2. `way-of.com` already receives (Google Workspace MX, plan 116
§16), but `<operator-mailbox>` and `<operator-mailbox>` are not yet aliases on the account — one
console step each (`Directory → Users → <the account the grant reads> → Aliases`). The
register prints the exact path for your account when it runs. Until then `--check` fails and
`inbound-test.sh` skips with those two reasons, which is the honest state.

**If it does not work.** `addresses.sh --check` exit 2 means the register itself is
unreadable (check `$YMIR_HOME/hodd/memory/mail/accounts.yaml` parses). `inbound-test.sh`
exit 1 after MX exists means the send left but nothing landed — check the routing row, the
destination verification, and the mailbox the address forwards to. Exit 3 is not a failure:
it is the door telling you what the world is missing before you trust an empty inbox.
