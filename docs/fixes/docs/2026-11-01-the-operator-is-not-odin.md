# 2026-11-01 — the operator is not Odin

**Component:** docs · **Scope:** naming law and lore glosses across `.agents/`, `RULES/`, `apps/`, `docs/`, `bin/`

## What was wrong

Twenty-three files called the operator **Odin** — in the naming law, in the asset that teaches the naming law, in
the app READMEs, and in a fix note about the model's own priors. The operator's words: *"we should never use odin
anywhere within ymir .. im not odin"*, and then *"my name are zerwiz online and Lars-<the operator> normally"*.

Two things follow, and they are different:

1. **In this house's voice the operator is the Allfather** — a role, not a borrowed god. `(Odin)` was a gloss that
   turned a role into a name, and the name was never his.
2. **A person's own names are theirs.** `zerwiz` online, `Lars-<the operator>` in person. They belong in a repository's
   `.agents/identity.json`, where the person states them — not in a lore paragraph, and never inferred.

## What changed

`Allfather (Odin)` → `the Allfather`; `(Odin)` dropped; `Odin's` → `the Allfather's`; a bare `Odin` → `the
Allfather`. Twenty-three files, no record rewritten: the append-only shelves — the Runes ledger, the daily log, the
masterplan and the archived plans — were **left alone**, and an attempt to sweep them was reverted before it was
committed, because a chained ledger that is edited stops being a chain.

## What is left

`assets/Ymir.md` — the imported lore corpus, ~4,000 lines — still carries the mythology where the god is genuinely
the subject. Whether that corpus is edited at all is a decision, not a sweep: it is a source document, and a source
is quoted rather than corrected.

## The rule

A document that must name a developer takes the name from `.agents/identity.json`; the log file uses the stable
`id`; and the house voice uses the role. No file assumes a particular name, so a second operator needs no edit.

**2026-11-03 (correction, appended):** the operator's name was redacted — it is personal data and belongs in the home, not in a public repository (RULES/04, RULES/06).
