# The collaborator door is a ward — JWT, scoped to one skill, carved per call

**2026-11-05 · component: collab · `bin/bridge/a2a-front.py` · `bin/collab/kit/docs/collaborator-door.md`**

## His word

*"the colabaration mcps must be secure with jwt tokens or equal"* · *"we need to have this in the colabaration kitt for ymir"*.

## The fault this closes

The heart's A2A node answers with `securitySchemes: []`. Publishing that address behind a tunnel would hand the well to
anyone who guessed the hostname. A collaborator road needs a **ward in front**, and the ward must be the thing that decides —
not a note in a document saying it should.

## What was built

```
built[3]{piece,what,proved}:
  "bin/bridge/a2a-front.py","a front that serves the card (public by design), requires `Authorization: Bearer <jwt>`, verifies EdDSA signature + `exp` + `aud` + `iss`, requires the token to name the skill being called, proxies to the node, and carves one Rune per call","no token → 401 · garbage token → 401 · valid token, wrong skill → 403 · valid token, right skill → 200 with the node's answer · the card proxied"
  "mint / verify","`a2a-front.py mint --peer --skill --aud --minutes` and `verify` — one JWT implementation, no second","mint→verify ok; verify against a skill the token does not hold → refused with the skill named"
  "the kit","`bin/collab/kit/docs/collaborator-door.md` + `bin/collab/kit/scripts/collab-connect.sh` (`snippet · mint · check`)","snippets print for pi and opencode; mint and check delegate to the one JWT door"
```

## The measurements

```
front_test[4]{request,answer}:
  "POST / with no Authorization","401 — 'a token is required'"
  "POST / with 'Bearer nope'","401 — 'token does not verify: Not enough segments'"
  "POST / with a valid token for `well-recall`, asking `shell`","403 — 'this token names no such skill (shell)'"
  "POST / with that same token, asking `well-recall`","200 — the upstream's answer, proxied"
```

## The law written into the kit

The card is the only anonymous answer. Everything else carries a token; the token must verify **and** name the skill; every
call and every refusal is a Rune. Never ssh into a collaborator's machine, never a seat in `fleet.json`, never a grant that
names a shell, never an open endpoint "for now".

## Owed, and named so it is not assumed

- The tunnel hostname (`a2adell.zerwiz.org`) and the token file live at `hodd/state/` (gitignored) — the operator's seal.
- The grant table still holds the placeholder uuid; a token without a grant grants nothing.
- The front is tested against a stub upstream here; the first call against the real node is the acceptance line.


## Appended — production readiness, same day

```
production[6]{item,state,proved}:
  "replay guard","one token, one use (`jti` recorded until its expiry)","first call 200 · same token again 409 · a fresh token 200"
  "rate limit","30 calls a minute per caller","`429` past the limit, refusal carved"
  "a shell face","`bin/bridge/a2a-front.sh` — one executor, a thin door (Rule 23)","`serve|mint|verify` pass through unchanged"
  "a unit","`tools/systemd/a2a-front.service` — user unit, `Restart=always`, `NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome=read-only`, `ReadWritePaths` only the token shelf and the Rune state","installable with `cp` + `systemctl --user enable --now`"
  "a feature page","`docs/features/collaborator-door.md` + a catalogue row + the woven FEATURES index (166 entries)","the how-to names every refusal code the front can return"
  "the key shelf","`$YMIR_HOME/hodd/state/a2a/ed25519.{key,pub}.pem` — the home, never the tree; 0600 on the private half","the unit reads only the public half; minting happens by hand"
```

**Still owed before a partner is invited:** the tunnel hostname and the DNS record (the operator's seal), the real grant row
replacing the placeholder, and the first call against the live node rather than the stub.

## CHANGE LOG

- **2026-11-05** — first written (Hœnir) with the ward, the kit and the feature page.
