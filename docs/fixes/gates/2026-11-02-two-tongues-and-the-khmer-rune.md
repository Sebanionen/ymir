## gates · unversioned · 2026-11-02 — two tongues: English and Old Norse, and a ward that sees the other scripts

### Why
His word, twice in one breath: *"all need to be in english in ymir — we need to have a guard that looks for
chinese, swedish, etc."* and, asked what may pass, *"english and old norse are the only approved languages."*

A user must be able to read the house they run. At ten thousand downloads Ymir is read in English by people who
did not write it, so a comment, a plan or an error message in a tongue they do not hold is a locked door in their
own home — and a foreign sentence is also the one thing no reviewer can check and no gate can judge for meaning.
Old Norse is not decoration here, it is the naming law: refusing it would refuse the house's own vocabulary.

### Files
- `RULES/43-two-tongues.md` (+ its README row; the index count moves to 39) — the law, the five declared
  exceptions (`fixture · detector · quotation · table · specimen`), and what the ward honestly cannot see.
- `bin/gates/guards/language-guard.sh`, seated in `guards.sh` — one test refuses any letter that is not English,
  Old Norse or runic, which catches every foreign script (Han · Kana · Hangul · Cyrillic · Arabic · Hebrew · Thai ·
  Devanagari) and every foreign Latin letter (ä · å · ü · ß · ç · ñ · ø · š · į · ł) without a word list. A second
  test catches a diacritic-free foreign prose (Dutch · Danish · Norwegian · Indonesian · Tagalog, and Swedish
  without its ä) by its function words, read only on PROSE lines — ≥6 words and no code punctuation — so a regex,
  an identifier or a CSS class cannot be mistaken for a sentence.
- `language.allow` — the five exception classes, one line each, `path | class | reason`. A line with no real
  reason, a class outside the five, or a path that no longer exists is itself a finding: a rotten allow line is a
  lie, and a lie in a gate is worse than no gate.
- `assets/mimirswell.html` — one character corrected (below).

### The defect the ward found on its first run
The Elder Futhark array in that asset carried a **Khmer letter where a rune belonged**: `ᛜ ធ ᛟ` in a sequence of
runes, one forgotten keystroke, invisible to every reader since it was written. Corrected to `ᛞ` (dagaz), the rune
that belongs in that place. Thirteen other findings were the declared exceptions and are written into
`language.allow` with their reasons — the locale fixtures, the assistant's Swedish language hint, the mail
classifier's Swedish invoice words, the rune-to-letter transliteration table, a homoglyph URL in a security test,
and the operator's own transcript.

### Proof
- `language-guard.sh --self-test` plants a Chinese comment, a Swedish sentence with diacritics, a German
  sentence and a Swedish sentence with the diacritics stripped, and requires all four refused while an English
  line and an Old Norse line pass. It passes: `self-test PASS — 4 planted fault(s) caught`.
- On the tree: `"none","","two tongues: English for the work, Old Norse for the names"`.
- `rules-number-guard` clean at 39 rules; `bin/gates/guards.sh` passes with the new ward in its list.

### Not done, and named
The ward reads the tree, not a pushed range: it cannot attribute a finding to the change that introduced it. And
it cannot see a single ASCII foreign word (`danke`, `merci`, `tack`) inside an English sentence — that stays the
reviewer's, and the rule says so rather than pretending otherwise.
