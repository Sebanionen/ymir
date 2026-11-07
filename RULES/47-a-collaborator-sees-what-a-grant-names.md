# 47 — A collaborator sees what a grant names, and nothing else

**Appended 2026-11-05** at the Allfather's word:

> *"do we have any colaberations rules in ymir? how users can interact whats for them to see and not to see? pivacy and secrets rules?"*
> *"tail net are only ours. colberators are not using our tailnet."* · *"tailnet are for the fleet. and ssh are for the fleet"*
> *"we cannot have thet un authirized users can reatch our memories and the things that only belongs to the fleet."*

Until now the law covered **the ward** (24), **the vault** (15/16), **the manner** (39), **the hoard** (04) and **the ladder**
(plan 154) — but no single rule said, in one place, *what a person outside this house may see*. That gap is closed here.

## The law

```
collaborator_law[7]{rule,what_it_means}:
  "A COLLABORATOR IS A COUNTERPART, NEVER A SEAT","nothing in `fleet.json`, the seats map, or any `*-ensure.sh` enrols them (plan 172). They hold accounts and grants; they do not become one of us"
  "THE TAILNET AND SSH ARE THE FLEET'S","a collaborator is never on either. They reach the house at the public gate, or through one token-checked door. We never ssh into their machine, and they never ssh into ours"
  "A GRANT IS THE WHOLE PERMISSION","person · tenant · skills · expiry. A token that verifies but names no skill is refused; a skill that is not granted is refused by name. Reachability confers nothing"
  "WHAT IS OURS IS NOT A DOOR","our memory (the well), our meetings (Snotra), our desk and our membership are the house's. They are shared as DOCUMENTS the operator chooses to send, never as a live tool"
  "ANOTHER CLIENT IS ANOTHER ROOM","a token for tenant A cannot read tenant B — not by a path, not by a query, not by a 'search everything' skill. Tenancy is on the token, not in the folder"
  "NDA IS A BOUNDARY IN THE DOOR","material written under confidence is tagged and withheld by the door itself, by name, whatever the query asks for"
  "PRIVACY IS THE DEFAULT, NOT A SETTING","a new surface is private until a grant names a person; a new field is private until the operator says it is public. Nothing is opened by adding it"
```

## What a collaborator may see, in one table

```
visibility[4]{surface,collaborator,rule}:
  "the suite (hall · board · documents · forge)","their own workspace and their own repositories","a login is a workspace, not a key to the house"
  "the published skills","the subset granted to them, read-only","`skills_list` · `skills_get` over the built, redacted copy — never the live shelf"
  "the A2A door","one skill, one tenant, an expiry, one Rune per call","plan 192; the card is the only anonymous answer"
  "everything else — the well, Snotra, the desk, the fleet","nothing","a request is refused BY NAME, and the refusal is a Rune"
```

## What must never appear in a public repository

```
never_public[6]{thing,why}:
  "a tailnet host or address","the fleet's road is not publishable (home RULES/network.md N1/N3)"
  "an ssh user or a key path","a key is a credential; a path is a map to it"
  "a mailbox, a phone number, an operator's name","private data (Rule 04/39)"
  "a port that answers on a private host","a port is a door and a door is a hint"
  "a tenant's material","one client's record never appears in another's document, and never in the repo"
  "a token, a password, a session cookie","Rule 24: secrets are references, never values"
```

## Enforced by

- `bin/gates/guards/vault-guard.sh` and `confidential-guard.sh` — the vault boundary, at commit.
- `bin/gates/guards/rules-compliance-guard.sh` — a new document that carries an internal address or a plain-HTTP cross-host
  URL is refused at the push (Rule 46).
- `bin/bridge/a2a-front.py` — the token ward: no token, no call; a token for one skill cannot call another; a replay and a
  rate are refused, and every call and refusal is a Rune.
- `hodd/identity/skills-grants.yaml` — the rows that are the permission.

## Recognised gap, stated so it is not assumed closed

The heart's MCP doors (the well, the skills door, Snotra) still answer an unauthenticated `initialize` **on the tailnet**.
The tailnet is the fleet's own road, so no stranger can reach them — but a door that is safe only because of a network is a
door whose guest list is a routing table. Plan 194 records the fix: bind loopback, put the ward in front.

## CHANGE LOG

- **2026-11-05** — appended (Hœnir) after the Allfather asked the question the shelf could not answer in one place.
