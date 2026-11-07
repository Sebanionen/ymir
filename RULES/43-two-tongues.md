# 43 — Two tongues: English for the work, Old Norse for the names

**Appended 2026-11-02**, at the Allfather's word, twice in one breath:

> *"append to the rules in ymir that all need to be in english in ymir — we need to have a guard
> that looks for chinese, swedish, etc."*
>
> and, asked whether anything else might pass: *"english and old norse are the only approved
> languages."*

## The law

```
two_tongues[8]{rule,what_it_means}:
  "TWO TONGUES, AND NO THIRD","the house writes in **English**, and it names itself in **Old Norse**. Nothing else: not Chinese, not Swedish, not German, not Spanish, not Japanese, not Russian — however convenient the source it was copied from."
  "ENGLISH IS THE LANGUAGE OF THE WORK","code, identifiers, comments, commit messages, plans, fix notes, documentation, UI strings, error messages, agent output, and every answer to the operator are English."
  "OLD NORSE IS THE LANGUAGE OF THE NAME","a figure, a shelf, a hall, a project, a rune: `Sága · Skírnir · Þjazi · Hnitbjörg · Gladsheim · Níðhöggr`. Its orthography (á é í ó ú ý þ ð æ ö ǫ ę œ) and the **Runic block** are allowed wherever a name is written, including a motto carved in runes."
  "A NAME IS NOT A LICENCE FOR A SENTENCE","an Old Norse name inside English prose is English with a name in it. A paragraph, an error message or a UI label written in Old Norse is refused — the tongue flavours the naming, it does not replace the work."
  "RECOGNISING A LANGUAGE IS NOT WRITING IN IT","code that detects, classifies or translates a foreign language is legal, and so is the foreign text inside it: those words are matching DATA. The assistant's Swedish language hint is the standing example."
  "A QUOTATION IS KEPT AS SPOKEN","a person's actual words, and a program's own output, are recorded as they came — never translated, never tidied. Marked as a quotation, they are not the house's prose."
  "THE GATE MAY NAME WHAT IT REFUSES","the rule and the ward carry the characters they refuse as specimens — a gate that cannot say 'this letter' in its own words would be a violation of itself."
  "CORRECT BY TRANSLATION, NEVER BY DELETION","foreign text that is not one of the four exceptions is replaced by English written in its place. Nothing is deleted to satisfy this rule (Rule 11); the meaning is carried over, and the change is recorded."
```

## Why it is law, and not tidiness

**A user must be able to read the house they run.** At ten thousand downloads, Ymir is read in
English by people who did not write it; a comment, a plan or an error message in a language they
do not hold is a locked door in their own home. The house is also *shipped* — every foreign
sentence is a thing no reviewer can check and no gate can judge for meaning.

**Old Norse is not decoration in this house, it is the naming law** (`.agents/assets/agents/naming.md`).
Refusing it would refuse the house's own vocabulary; allowing anything else would refuse the
reader. So the line is drawn at two tongues, exactly where the Allfather drew it.

## The five legal exceptions, each declared

`language.allow` (repo root) names them, one line each — `path | class | reason` — and a line
without a real reason, or naming a file that no longer exists, is itself a finding. A rotten
allow line is a lie, and a lie in a gate is worse than no gate.

```
exceptions[5]{class,what_it_covers,example}:
  "fixture","a test that proves unicode handling — the foreign text IS the assertion","the locale table, a homoglyph URL, a unicode filename"
  "detector","code that RECOGNISES a foreign language — the words are matching data","the assistant's Swedish language hint · the mail classifier's invoice words"
  "quotation","a person's actual words, or a program's own output, kept as it came","a transcript of the operator's own session · a test reporter's line"
  "table","a table of LETTERS — a transliteration, an alphabet, a character map","the rune-to-letter table in the design system"
  "specimen","a document that NAMES the characters this rule refuses — a gate must be able to say 'this letter' without violating itself","this rule · its fix note · the ward's own marker lists"
```

## What the ward judges — and what it honestly cannot

`bin/gates/guards/language-guard.sh`, seated in `guards.sh`:

```
what_it_sees[3]{test,catches}:
  "a letter that is not English, Old Norse or runic","every foreign SCRIPT (Han · Kana · Hangul · Cyrillic · Arabic · Hebrew · Thai · Devanagari) and every foreign LATIN letter (ä · å · ü · ß · ç · ñ · ø · š · į · ł) — one test, no word list, no guess"
  "the function words of a diacritic-free language","Dutch · Danish · Norwegian · Indonesian · Tagalog, and a Swedish paragraph that carries no ä — read only on PROSE lines (≥6 words, code punctuation absent), so a regex, an identifier or a CSS class cannot be mistaken for a sentence"
  "an allow line with no reason, or one naming a file that is gone","the allow list itself"
```

**What it cannot see, stated so nobody assumes it does:** a single foreign word spelled in plain
ASCII (`danke`, `merci`, `tack`) inside an English sentence; a transliteration without its
original; and whether a translation is *faithful*. The ward raises the floor; the rule is the
standard.

**A guard that cannot fail is not a guard.** `language-guard.sh --self-test` plants a Chinese
comment, a Swedish sentence with diacritics, a German sentence, and a Swedish sentence with the
diacritics stripped — and requires all four to be refused while English and an Old Norse line
pass. It is proved on every run of the ward.

## What it found on the day it was written

Fourteen findings in a tree nobody had checked for this. Thirteen were the declared exceptions
(above) and were written into `language.allow` with their reasons. **The fourteenth was a
defect:** the Elder Futhark array in an asset's UI carried a **Khmer letter (`ធ`) where a rune
belonged** — `ᛜ ធ ᛟ` in a sequence of runes. A single forgotten keystroke, invisible to every
reader, found by the ward on its first run. Corrected to `ᛞ`.

**Related:** Rule 21 (a company document is plain business English), Rule 04 (the repo ships
craft; the operator's own words stay his), Rule 11 (never delete — translate), Rule 27 (the
documents are checked).

---

## Appended 2026-11-03 — the law rides every parchment, and how a native project is served

The Allfather's word: *"make so all agents.md's that gets in to the harness tools
knows to only talk and use english inside ymir. if projects we're working on are
needed native language we should be able to handle that. but NOTHING in ymir are
allowed to be in something else then old norse and english."*

**The propagation.** A law in `RULES/` binds a reader, not a harness. So the two
tongues are written where every agent actually looks:

- `AGENTS.md` at the repo root (Pi's `~/.pi/agent/AGENTS.md` is a symlink to it),
- the machine's `~/AGENTS.md`, and the private home's `AGENTS.md`,
- **every figure brief** under `.agents/agents/*.md` — all 24 carry *The tongue
  (Rule 43)* in their body, so a dispatched Eindri reads the law before its first
  word, whichever harness seats it.

**The native project.** A client project may genuinely need its own tongue — a
Swedish site, a German contract, a Japanese interface. The law does not forbid
that; it forbids it **inside Ymir**. The handling is scope, not exception:

- the project's native material lives in the **project's own scope** — its
  repository, its shelf — and never in Ymir's craft, plans, rules or docs;
- inside Ymir, a foreign tongue appears only as a **declared class** in
  `language.allow` — `fixture` (the foreign text is the assertion), `detector`
  (code that recognises a language) or `quotation` (a person's own words) — each
  with its reason, and a rotten line is itself a finding;
- a translation is how a foreign work is *described* here (Rule 11: translate,
  never delete);
- when a project's brief is dispatched, the brief says which tongue its
  deliverable is in and where that deliverable lives — the agent then knows it
  leaves Ymir's tongue at that boundary and nowhere else.

**What is refused:** a Swedish sentence in a plan, a German comment in a door, a
foreign UI string in an app, a commit message in another tongue. **What is
allowed:** English for the work, Old Norse for the names — and at the boundary of
a native project, that project's own tongue, inside its own walls.
