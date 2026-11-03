# 42 — The home is a contract: every file the runtime reads ships as a shape

**Appended 2026-11-02**, at the Allfather's word:

> *"do we have all templates we need from ymir home in ymir so they come on updates and
> installations? do the users ymir home gets set up in the right way with the users?"*
>
> and, the same hour, with the stakes named: *"we have over 10 000 downloads of ymir now,
> and our full crew are using ymir and our gimle. it needs to be production ready."*

## Why this rule exists — measured, not supposed

A home was raised in a temp directory and the session digest was run against it, exactly as
a new user's first session would:

```
the fresh home, before this rule
  ABSENT: hodd/data/operator.md        the standing preferences, read at every start
  ABSENT: hodd/data/projects.md        the project registry in prose
  ABSENT: hodd/data/learnings.md       the operational facts the digest prints
  ABSENT: <realm>/HOOD.md              the holdings map the digest prints whole
  refused: hodd/identity/seats.yaml    "roster not readable" — the seat could not be named
  realm fell back to `default`, with no `.env.realm`
```

**Five documents that a session opens with, and a new user's home holds none of them.**
They existed on this machine because a hand wrote them there over months — which is exactly
the fault Rule 04 named for tools: *work that is correct and unreachable.* The repo shipped
34 `.example` shapes, so the gap was not *nothing ships*; it was that **only the files
somebody remembered to templatise shipped, and nothing measured the difference.**

A second fault, found the same hour: `bin/engine/ymir-install.sh` wrote
`hodd/identity/workspaces.yaml` from an **inline heredoc whose shape its own shipped
template did not teach**, while `registry/workspaces.yaml.example` said something else. Two
sources of one truth — the exact thing `bin/identity/registers-seed.sh`'s own header forbids
in capitals — and the user receives whichever the code path happened to run.

## The law

```
home_contract[8]{rule,what_it_means}:
  "THE HOME IS A CONTRACT, AND ITS SHAPE IS PUBLIC","every file the runtime READS from $YMIR_HOME is named in ONE place — `.agents/home-contract.yaml` — with its kind, the shape that ships it, and the door that writes it. A home assembled from whoever remembered is not a contract, it is a habit."
  "EVERY READ HAS A SHAPE","a file the runtime reads either (a) has a template on a shipped shelf, or (b) is declared `optional` with the reason its absence is a clean skip. Silence is neither, and a required file with no template is a WISH, not a row."
  "ONE OWNER PER COPY","a home file arrives through exactly ONE door. An inline heredoc in the installer is refused where a template exists, because two writers of one file drift by construction — measured, this day, in `workspaces.yaml`."
  "THREE DOORS, ALWAYS","**install** seeds it for a new user (`bin/engine/home-seed.sh`, called by the installer); **update** heals an existing home forward (a numbered `.agents/migrations/` row); **template** teaches the shape publicly (a `.example` that mirrors the real file by NAME and rides ZERO private values — Rule 04)."
  "NEVER OVERWRITE A HOME","a file that exists is the operator's record and outranks any default. Seeding is additive: it writes what is absent and says what it left alone."
  "A MISSING FILE IS A NAMED ABSENCE, NEVER A GUESS","a reader that finds no file prints ABSENT with the path and the fix, and a `defaulted` read says which file answered. A digest that prints a zero or a default as if it were the operator's data is Rule 37's fault in a new coat."
  "THE WARD READS THE CONTRACT","`bin/gates/guards/home-contract-guard.sh` (in `guards.sh`) refuses a row whose template or door does not exist, a required file with no shape, and — the widest fault — a TEMPLATE NO ROW NAMES: a shape shipped to every user that lands in no home."
  "A NEW READ IS PART OF THE CHANGE","a script that starts reading a new home path adds its row, its template and its door in the same commit. The same duty Rule 25 gives a moved path, applied to a new dependency."
```

## The kinds — what a row owes

```
kinds[5]{kind,owed,example}:
  "seeded","copied once from its template if absent; never touched again","config/agents.yaml · the four identity registers · .ymir-layout.yaml"
  "stub","the operator's OWN words: an empty shape with a prompt, copied once, never overwritten","hodd/data/operator.md · hodd/data/learnings.md · hodd/identity/seats.yaml"
  "defaulted","read from the home, else the shipped template, and the reader says which answered","config/cron.yaml · config/model-catalog.yaml"
  "optional","read if present; absence is a clean skip naming its reason; no template owed","config/room.yaml · hodd/identity/confidential.yaml"
  "generated","written by a door from live facts — never seeded, never hand-edited, never committed","hodd/memory/kaia.engram · .agents/skills/skills.yaml"
```

An **empty roster is honest and is shipped that way.** `hodd/identity/seats.yaml` arrives
with `seats: {}` and one printed command (`bin/agents/seat-identity.sh set <host> brokk`),
because a seat's name is a person's act and never a script's invention (Rule 02 §4 — no
mock agents). The same holds for every stub: the shape teaches, the operator writes.

## Why this is law and not housekeeping

At ten thousand downloads a missing template is not a papercut, it is the same papercut ten
thousand times, on machines nobody can ssh into. The failure is silent by construction: an
absent file reads as an empty preference, an unnamed seat, an unregistered realm — a house
that answers, wrongly, in a voice its operator never chose. **A shape that ships to everyone
and lands in no home is worse than a missing feature, because the feature looks present.**

## Enforcement

| gate | refuses |
|---|---|
| `bin/gates/guards/home-contract-guard.sh` | a row with no shipped template or no standing door; a required file with no shape; a template no row names |
| `bin/gates/checks/home-contract-check.sh` | the same, reading the contract through the ONE parser (`bin/engine/home-seed.sh --list`) |
| `bin/engine/home-seed.sh` | a seed whose template is missing — it fails, naming the row, rather than copying nothing |
| `.agents/migrations/0016-home-contract.sh` | the drift itself: an existing home is healed forward, additively, and can never be rewritten |

**The duty, in one sentence:** *if the runtime reads it, a user's home holds it, a template
teaches it, one door writes it, and a ward proves the three still agree.*

**Related:** Rule 22 (the home has a layout — this rule is how the layout is *raised*),
Rule 04 (the repo ships craft, the home holds data), Rule 25 (a move is a migration),
Rule 37 (a surface may not show what it did not receive), Rule 14 (a feature owes a how-to).
