# The collaborator door — how a partner outside our network asks the house a question

## What it is

One public door in front of Ymir's A2A node, for hands that are **not** on our tailnet and never will be.

A partner gets a **card** (public), a **token** (short-lived, scoped to one skill) and a **grant** (a row in our house,
per pair, per skill, with an expiry). They get no seat, no ssh, no repository.

## What you need

- A seat with `bin/bridge/a2a-front.py` (this tree).
- An Ed25519 key pair under `$YMIR_HOME/hodd/state/a2a/` (never in the repo).
- A tunnel hostname pointing at the front's loopback port.

## The commands

```bash
# mint a token for one partner, one skill, one hour
bin/collab/kit/scripts/collab-connect.sh mint --peer andre --skill well-recall --minutes 60

# check a token before you send it
bin/collab/kit/scripts/collab-connect.sh check --token "$TOK" --pub "$YMIR_HOME/hodd/state/a2a/ed25519.pub.pem" --skill well-recall

# what the partner pastes into their harness
bin/collab/kit/scripts/collab-connect.sh snippet --endpoint http://<host>:8321 --harness pi
```

## Limits

- The card is the only anonymous answer. Everything else needs a token.
- A token that names one skill cannot call another: `403`, and the refusal is recorded.
- A token is single-use (a replay is `409`) and the front allows 30 calls a minute per caller (`429` after).
- One Rune is carved per call and per refusal.

## If it does not work

`401` — no token, or it does not verify (expired, wrong audience, wrong signature).
`403` — the token verifies but does not name that skill.
`409` — that token has already been used; mint a fresh one.
`429` — rate limit; wait a minute.
`502` — the front is up and the node behind it is not.

## CHANGE LOG

- **2026-11-05** — first written (Hœnir) with the ward and the kit.
