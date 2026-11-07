# The ruleset hash is per seat and per moment — the record must quote all three

**Date:** 2026-11-06 · **Plan:** 203 §13 (the review record) · **Law:** `RULES/07-config.md`

## What was wrong

Two seats ran the same rules floor against the same repository and printed **different** hashes —
`f7c802a0752d040d` and `f224f6147ddc2119` — and for a while that looked like drift, or like one of
them holding a stale law. It was neither. Source #4 of the floor is **the plan ledger**, and one seat
had appended plan 204 that evening. The hash moves whenever the plans grow, and it also moves with the
home's own `AGENTS.md`, because the floor reads the seat's contract.

So the number was being printed as if it were a portable identifier, and it is not. A review record
that carries only the ruleset names nothing: the same law on two machines, an hour apart, gives two
numbers, and neither is wrong.

## The fix

`bin/forge/review-rules.sh` now prints **seven** facts instead of five, and says the rule out loud:

```
review-rules[7]{facts,value}:
  "repo","/home/zerwizomar/ymir"
  "sources",8
  "frozen",2
  "forbidden",9
  "ruleset","d8cbdebadcfb2345"
  "seat","nidavellir"
  "at","2026-11-06T09:32:50Z"
note: the ruleset hash is PER SEAT and PER MOMENT (source 4 is the plan ledger, which grows) —
      a review record carries ruleset + seat + at, never the number alone
```

`seat` is the hostname and `at` is UTC at the moment the floor was read, so a record can quote the
three together and a reader can tell "the same law" from "a different law".

## How it was proved

Run on this seat after the change: sources 8, frozen 2, forbidden 9, ruleset `d8cbdebadcfb2345`,
seat `nidavellir`, at `2026-11-06T09:32:50Z`, floor complete. The same command an hour earlier printed
`73b0883e04947683` and then `f7c802a0752d040d` — three different numbers for one unchanged law, which
is the whole point: the number alone is not a fact about the law, it is a fact about the moment.

## Owed

The review record shape (`review[]` in `schemas/handoff-packet.toon`) already has `ruleset`, `reviewer`
and `at` columns; what is owed is the discipline of always filling seat and time, and it belongs to the
reviewer's side (the heart), not to this tool.

## CHANGE LOG

- **2026-11-06** — first cut: two new facts, the note that says what they mean, and the reason the
  difference is not drift.
