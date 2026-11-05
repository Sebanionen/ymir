# The collaborator door — how a hand that is not on our network talks to the house

**What it is.** One door, three layers, and one law: *a collaborator is a counterpart, never a seat.*

A seat is a machine of this fleet. A collaborator is another hand with its own house, its own repos and its own operator.
They get a **door**, not a membership.

## The three layers

```
layers[3]{layer,what,why}:
  "the card","`/.well-known/agent-card.json` at the public name — name, endpoint, skills, owner","a card is metadata and enrols nobody; it is how a peer discovers what may be asked"
  "the token","a short-lived JWT (EdDSA): `iss` the house, `aud` the seat, `sub` the collaborator, `skills` the one list it may use, `iat`/`exp`","a token is a grant of a question, not of a machine"
  "the grant","a row in the house's own grants table — the pair, the skill, an expiry","a token without a grant buys nothing; reachability is not authority"
```

## The rule a public door must satisfy — no exceptions

```
ward[5]{requirement,refusal}:
  "the card is public","that is the only anonymous answer the door ever gives"
  "every other request carries `Authorization: Bearer <jwt>`","no token → 401, and the refusal is recorded"
  "the token must verify: signature, `exp`, `aud`, `iss`","a stale, wrong-seat or forged token → 401"
  "the token must name the skill being called","a valid token for `well-recall` cannot call anything else → 403"
  "every call and every refusal is appended to the ledger","a door with no record is a door nobody can audit"
```

**Never:** ssh into a collaborator's machine (or theirs into ours), a seat in `fleet.json`, a card that enrols them as one of
us, a grant that names a shell, a write path, or a repository. **Never** an open endpoint "for now" — a door with no ward is
the fault this house has paid for twice.

## The two roads

```
roads[2]{road,when,cost}:
  "tailnet","the collaborator will join our Tailscale network and be named one host and one port","fastest; full MCP; the collaborator is on our network, which some will refuse"
  "public door","the collaborator will not join any network of ours","a hostname behind the tunnel, a token, a grant, a Rune per call"
```

## Connecting (the snippet a collaborator pastes)

```json
// pi — ~/.pi/agent/mcp-adapter.json
{ "mcpServers": { "snotra": { "url": "http://<host>:8321/mcp" } } }

// opencode — opencode.json
{ "mcp": { "snotra": { "type": "remote", "url": "http://<host>:8321/mcp" } } }
```

```bash
# the public door — one call, one token
curl -s -X POST https://<door-host>/ \
  -H "Authorization: Bearer $YMIR_TOKEN" -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"message/send","params":{"skill":"well-recall","message":{"role":"user","parts":[{"kind":"text","text":"recall: the Windows path limit"}]}}}'
```

A token is minted by the house, not by the collaborator:

```bash
bin/collab/kit/scripts/collab-connect.sh mint --peer andre --skill well-recall --minutes 60
```

## What the collaborator is told, in one paragraph

> The card is public; everything else needs your token. You have exactly one skill until we say otherwise, and no grant
> names a shell. Your token expires and is re-minted on request. If you want us to call you, publish your own card at an
> endpoint that answers and we will ask for one skill — never for your machine.

— the kit · read `bin/collab/kit/README.md` for the ten pieces this sits beside.
