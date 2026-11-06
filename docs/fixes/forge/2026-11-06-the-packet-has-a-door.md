# The packet has a door — `bin/forge/handoff-packet.py`

**Date:** 2026-11-06 · **Plan:** 203 §3 · §14.1 · §15.2 (gap 1) · **Law:** `RULES/08-delivery-gate.md`

## What was wrong

Plan 203 described a packet in §3 and built no way to write one, so every smith invented a
shape and the reviewer parsed prose. §15.2 named it gap 1, and the Allfather's own correction in
§14 made it load-bearing: the smith pushes a branch and the packet is what the reviewer trusts.

A schema alone would not have fixed it. The two refusals that make a packet worth reading are the
ones §15.3 says to protect — the sha check and the reviewer running the gates itself — and neither
exists if the only thing between a smith and a reviewer is a document nobody validates.

## What was built

`bin/forge/handoff-packet.py` — `write` · `check` · `show`. The packet lives at
`$YMIR_HOME/state/handoff/<id>.packet` in the house's TOON face, with the eleven fields §3 names:
task, plan, branch, base, head, changed[], gates, tests, claims[], not_done[], needs[].

**`write`** takes the facts from git, not from the smith's memory: the head is the full sha (a
branch name can move), the base is resolved to its sha, and `changed[]` is read out of
`git diff --numstat base...head`.

**`check`** refuses a packet on five grounds:

- **a moved head (§14.1)** — `--fetched <sha>` that is not the packet's head is refused with the rule
  quoted: a packet may not vouch for code that moved.
- **an understated or overstated changed list** — every claimed path is compared with the real diff.
  A packet that omits a file it touched is refused and the file is named.
- **a base nobody can resolve** — a base with no full sha, or one not present in the repository, is
  refused: the diff could not be verified, so the packet is not read.
- **a gate that is a claim, not evidence** — `all pass`, `green`, `CI green`, `n/a` and their cousins
  are refused by name; the field carries output, not a promise.
- **a missing required field** — every one of the eleven, named individually.

And it never approves: a sound packet prints *"soundness is not approval — run the gates on the
fetched commit yourself"*, because §15.3's second protected rule is that CI is a second opinion.

`write` also refuses a packet with no base sha and a head that is not a full sha, so a bad packet
cannot be created in the first place.

## How it was proved

`bin/gates/tests/test_handoff_packet.sh` builds a throwaway repository with a real base and head,
then proves each refusal — **9 passed, 0 failed**:

```
  ok   a packet with evidence is written
  ok   a true packet reads as sound
  ok   a moved head is refused
  ok   the refusal quotes §14.1's rule
  ok   an understated changed list is refused
  ok   the refusal says understated, and names the path
  ok   "all pass" is refused as evidence
  ok   a base with no sha is refused
  ok   a missing packet is refused
```

Proved against a real handoff too: a packet written for `feat/ship-gate-ward` at
`43891b626b66b136779c2b404cf9b80185a0b540` over base `0ff2b10e…` read **sound** with all thirteen
changed paths, and the same packet with a wrong `--fetched` sha was refused by §14.1.

## What it does not do yet

- **The `gh` shim** (§15.2 gap 2) — belongs to the spawn path, which exports no smith identity.
- **The review shelf and the timer** (gap 4) — Hœnir's side: `bin/seat/pending.sh` already reads open
  PRs, so the shelf is one more source there, not a new list.
- **The delivery switch** (gap 0, the contradiction) — reviewer-merges vs operator-merges is the
  Allfather's to set; until it is written the default is **his hand on GitHub**.

## CHANGE LOG

- **2026-11-06** — first cut: the door, its five refusals, the nine-case test, and a real packet for
  the ship-gate branch proved end to end.

## Correction, 2026-11-06 (later) — the door now writes the SCHEMA, not a shape of its own

**What was wrong.** The first cut of this door wrote a shape of its own: flat `gates`, `tests`,
`claims` and `not_done` blocks, and no `author`, `written_at`, `ruleset` or `floor`. The same night
Hœnir landed the contract at `schemas/handoff-packet.toon` (PR #541) — richer, with structured
`changed{path,added,removed,why}`, `gates{gate,cmd,exit,output_tail}`, `tests{cmd,exit,tail}`,
`claims{claim,state,evidence}`, `not_done{item,why}`, `needs{need,who}`, and a `review[]` block the
smith may not write. **Two shapes then existed, which is exactly the drift gap 1 was meant to end.**

**The correction.** The schema is the contract, so the door conforms to it and to nothing else. It
now writes all nine packet fields (with `written_at` in UTC, `author` from `$YMIR_AGENT_NAME` or git,
and `ruleset`/`floor` read from `bin/forge/review-rules.sh` itself), the six blocks in the schema's own
columns, and it performs three new refusals the contract named:

- **a `review[]` block written by a smith** — that verdict belongs to the reviewer, and a packet that
  carries one is a review that never ran;
- **`floor partial`** — a partial floor is a refusal waiting to happen (schema rule 6), so the packet
  is not read until the floor loads whole;
- **a claim with no state** — `verified` or `unverified`, and the reviewer looks where `evidence` says.

**Proved.** `bin/gates/tests/test_handoff_packet.sh` now drives the schema's shape explicitly —
**16 passed, 0 failed**, including the three refusals above, the moved-head rule, the understated
`changed` list, the "all pass" tail, a base with no sha, and a missing packet.

**One thing the old packet on disk cannot do:** `$YMIR_HOME/state/handoff/ship-gate-ward.packet` was
written in the old shape and is now refused, which is correct — it describes a branch that has since
merged (#539). A packet is for a commit that is still waiting.
