## hlidskjalf · 2026-11-03 — the Skírnir gate spoke Swedish; it speaks English

### Why
Rule 43 landed (two tongues: English for the work, Old Norse for the names) and
its ward found the Skírnir – Tala gate — merged into main — speaking Swedish in
28 lines: every phase label, every hint, the consent line, the language
selector, the buttons and the answer headings. The Allfather's word: *"we need
to make so the updates in the branches are using english instead of swedish.
thats againts the rules."*

### Mend
- `apps/hlidskjalf/src/gates/Skirnir.tsx` — all 28 Swedish lines translated;
  the feature name **Skírnir – Tala** stays (a name, and *tala* is Old Norse).
- `apps/hlidskjalf/src/app/Topbar.tsx`, `…/data/metadata.ts`, the Skírnir doc
  and the hlidskjalf-ui asset updated to the English labels.
- The four tests that legitimately carry Swedish (the contract, the selection,
  the voice input and the language-selection test) are declared in
  `language.allow` as **fixtures**: the foreign text IS the assertion.

### Proven
- `bin/gates/guards/language-guard.sh` → `"none","","two tongues: English for
  the work, Old Norse for the names"` (0 findings).
