# The operator-only mail door — `bin/notify/mail.sh`

**Date:** 2026-11-06 · **Plan:** 206 §3 F4 · **Law:** `RULES/15-vault-confidential.md`, `RULES/39`, `RULES/24-the-ward.md`

## What was wrong

The Allfather: *"he can also email me then he have merged or if he have questions about the merge."* The house
had one letter door (`systems/snotra/services/letters/mail-send.sh`) and it is right to demand an approval
before it sends — a letter to a stranger is correspondence and costs the operator his name. So a
notification to the operator himself had no door at all: a merge record could only reach him as a wake, and a
question the judge could not answer alone died in a file.

## What was built

`bin/notify/mail.sh --kind merged|ask --subject … --body FILE` — sends through the Gmail API with the vault
grant (`GOOGLE_MCP_CLIENT_ID` · `GOOGLE_MCP_CLIENT_SECRET` · `SNOTRA_GOOGLE_REFRESH_TOKEN`), and it may
address **one person**: the operator's own `email:` row in `hodd/identity/operator.yaml`. Any other recipient
is a refusal that names the rule — a notification door that could address anyone is a send path without an
approval.

## The wards it keeps

- **No secret, ever** — a body matching a credential shape is refused (`RULES/15`), not even to him.
- **No address of the house** — a body carrying what looks like an IP is refused (`RULES/39`); name the door.
- **Silence is failure** — an unreadable grant, a refused refresh token or a non-200 answer each print a FAIL
  line and exit 1; `--status` answers "is this seat able to send at all", which is the check that would have
  caught the heart's dark vault.
- **The reference travels** — `--ref` puts the record's path in the body and an `X-Ymir-Ref` header on the
  message.

## Verified

`mail.sh --status` on nidavellir and heimdall: `ready` (the grant mints a token); on the heart it answers
`no grant` — the vault cannot be opened there, which is the fault plan 206 §3 F1 names. `--dry-run` builds
and validates the message without sending.

## CHANGE LOG

- **2026-11-06** — written with the doors it describes (plan 206): the review loop joined to the
  spine, the read-only agent's mouth, the resolver that replaced five hardcoded model ids, and the
  operator-only mail door.
