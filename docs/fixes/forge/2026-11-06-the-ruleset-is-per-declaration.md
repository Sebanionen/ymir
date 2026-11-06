# The ruleset is per DECLARATION, not per seat — a correction to yesterday's fix

**Date:** 2026-11-06 · **Plan:** 203 §18 · **Corrects:** `docs/fixes/forge/2026-11-06-the-ruleset-is-per-seat.md` (§3 of the manner: a fix note is never rewritten — a correction is its own note)

## What was imprecise

The first note said the ruleset hash is "per seat and per moment". Both words were guesses dressed as
measurements. The heart measured both halves in one message, and the second one is the real cause.

```
measured[3]{repo,ruleset,why}:
  "the game clone (~/CodeP/the-outer-byway)","7332edd065bd1ff7 on BOTH seats","its declaration lists no plan ledger — a fixed set of files, so the hash is STABLE across seats and time"
  "the ymir tree, on the heart","08f5954d → f224f614 → fee527c1 across one night","its declaration names the plan ledger as source 4, so every appended plan moves the hash"
  "the ymir tree, on this seat","73b0883e → f7c802a0 → d8cbdeba → aea8cfbe, same cause","same declaration, different home contract — the seat shifts it too"
```

## The sharper rule

The hash is per **declaration and moment**. A project whose declared sources are fixed is stable
forever; a project that declares a growing ledger moves every time the ledger grows. "Per seat" was
doing too much work: the game's number is identical on both machines, so the seat is not the axis — the
declaration is, and the seat only matters because each seat declares its own `AGENTS.md`.

## The correction in the tool

The note beside the facts in `bin/forge/review-rules.sh` now says *per declaration and per moment*, and
names the mechanism (a declared source that grows). The `seat` and `at` facts stay, because a record
still cannot quote a number alone.

## How it was proved, and by whom

On this seat, one minute apart: the game clone printed `7332edd065bd1ff7` — **exactly** the heart's
number, from a different machine — and the ymir tree printed `aea8cfbe3da261e2`, both at seat
`nidavellir`, both at `2026-11-06T10:11:53Z`. The same tool, two repositories, two answers, and the
difference is entirely what each repository declares.

The heart's own words are the evidence for the ymir side: *"my seat moved 08f5954d → f224f614 →
fee527c1 across tonight, every time the plans grew."*

## Owed

Nothing. The heart carries `seat + at` in every `review[]` from tonight, which it has said plainly is
its discipline and not the tool's.

## CHANGE LOG

- **2026-11-06** — the correction as its own note, because the guard was right: `fixes-guard` refused a
  push that APPENDED to an existing fix note. A fix note is never rewritten; a correction is a new one.
