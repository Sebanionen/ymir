## agents · unversioned · 2026-11-03 — the tongue rides every parchment

### Why
Rule 43 landed, but a law in `RULES/` binds only a reader who opens it. The
Allfather's word: *"make so all agents.md's that gets in to the harness tools
knows to only talk and use english inside ymir. if projects we're working on are
needed native language we should be able to handle that. but NOTHING in ymir are
allowed to be in something else then old norse and english."*

### Mend
- `AGENTS.md` (the repo contract; `~/.pi/agent/AGENTS.md` is a symlink to it) now
  states *The tongue (Rule 43)* beside the voice bounds, and its rules table
  carries the RULES/43 row (count 11 → 12).
- **All 24 figure briefs** (`.agents/agents/*.md`) carry *The tongue (Rule 43)* in
  their body — a dispatched Eindri reads the law before its first word.
- `RULES/43-two-tongues.md` gains the appended propagation clause and the
  **native-project handling**: a client project's own tongue lives in that
  project's scope, never in Ymir's craft; inside Ymir a foreign tongue appears
  only as a declared `fixture`, `detector` or `quotation` with its reason.
- `bin/gates/guards/language-guard.sh` gains a third judgment: the law must be
  present in the repo AGENTS.md and every brief — *a law nobody is told is no law*.

### Proven
- The ward is clean on the tree: `"none","","two tongues: English for the work,
  Old Norse for the names"`.
- A planted fault (Rule 43 stripped from `elder.md`) is caught and named:
  `"the tongue is not declared",".agents/agents/elder.md"`.
