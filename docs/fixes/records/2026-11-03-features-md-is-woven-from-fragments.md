## records · 2026-11-03 — FEATURES.md is WOVEN from fragments (Þættir, plan 174)

### Why
The Allfather: *"we need to do features.md to some kind of folder structure or
file structure over the features. FEATURES.md are always colliding."* Measured
this week: FEATURES.md conflicted in PR #482 and PR #483 (and earlier, whenever
two features landed at once) — because every feature appends to one shared tail.

### Mend
- `docs/features/_catalogue/` — the catalogue is now fragments:
  - `_header.md` — the doctrine above the sections (it now states the file is woven);
  - `_sections.md` — the section order (`<order> | <title> | <slug>`);
  - `entries/NN-III-<slug>.md` — **one file per entry** (155 of them), each carrying
    its section in front matter. A new feature adds its OWN file, so two hands never
    edit the same line.
- `bin/records/weave-features.sh` — the weaver: header + sections + entries, in
  order; `--check` fails when the woven file is stale; `--install` seats the merge
  driver.
- `bin/records/regenerate-on-merge.sh` — the `merge=regenerate` driver (seated in
  `.gitattributes` for FEATURES.md, bin/README.md, the backend register and
  capabilities.md): a conflict on a woven file is answered by weaving, never by hand.
- `bin/gates/guards/features-guard.sh` — a third judgment: the woven catalogue must
  be current, and the merge driver must be seated (a planted hand-edit is refused).
- `AGENTS.md` — the feature how-tos teach the fragment, not the file.
- The law's mirror: `.agents/skills/galdr-ymirsystem/SKILL.md` carries the Rule 43
  line its agent brief already had (the dual-surface gate was red). Mended here
  because main was red on it.

### Proven
- The first weave reproduced the catalogue **byte-identically** (cmp against the
  pre-refactor file), then against main's own post-merge bytes (sections identical;
  only the header doctrine is new).
- `features-guard.sh check` → current; a hand-edited FEATURES.md is refused and named.
- The four merge drivers seated (`git config merge.regenerate.driver`).
