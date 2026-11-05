# The install table declares the rows it holds

**2026-11-05 · component: install · `.agents/skills/galdr-ymirsystem/assets/installation.md`**

Found by the compliance gate on the integration branch (#535): `install[35]{…}` declared 35 rows and carried 36. The TOON
reader counts, so one row was invisible to every reader of the asset — the newest step was the one nobody could see.

The header now says `install[36]`, which is a number a script can check, so the shape and the content cannot drift apart
without the gate saying so.

## CHANGE LOG

- **2026-11-05** — declared count corrected from 35 to 36 (Hœnir); found by `compliance-check.sh`, not by reading.
