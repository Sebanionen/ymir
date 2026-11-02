# The kind vocabulary is not a stub — the mocks gate learns one word of law

**Date:** 2026-11-02 · **Component:** gate

## What was wrong

`main` went red the moment two changes landed together: **RULES/42**'s home contract (whose kinds are
`seeded · stub · defaulted · optional · generated`) and `bin/engine/home-seed.sh`, the door that switches on those
kinds. The compliance gate greps shipped code for `\b(mock|stub|placeholder|todo)\b` and flagged:

```
bin/engine/home-seed.sh:137:      seeded|stub|defaulted) ;;
bin/gates/checks/home-contract-check.sh:81:  "") say "kind missing" … "seeded · stub · defaulted · optional · generated"
```

Neither line is a mock. Both name a **documented vocabulary** that RULES/42 makes law — and the gate's own header
already says so for another pair: *"a word that is a documented vocabulary token is not a stub"* (`consumer:` /
`todo:`).

## What changed

One exclusion, shaped like the vocabulary itself, in either separator form:

```sh
| grep -vE 'seeded[ |·]+(stub|defaulted)|stub[ |·]+defaulted'
```

A line that merely **names** the kind list is excused; a real stub elsewhere is not.

## Measured

```
compliance-check.sh                     → 0 FAIL rows (green)
probe: a file containing "mock behaviour" → the mocks gate still FAILs   ← the exclusion is narrow, proved
guards.sh                               → 18 wards
```

## Why this is worth a note

The alternative was to reword working code around a grep — which is how a gate teaches people to write around it
instead of reading it. The house's own doctrine already had the answer; the gate simply had not learned this
vocabulary yet.
