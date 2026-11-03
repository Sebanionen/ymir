## gate · 2026-11-03 — the branch drops a duplicate

### Why
While shipping #495 (the fixes-guard judges our own commits), this branch was also
carrying the **Hermes** commit — the same work #496 owns — so the two pull requests
collided on the same two files (`harness-integration/README.md` and the Hermes note).
A branch must carry one concern; the duplicate is excised here and Hermes stands
in #496 alone.

### Mend
- The branch was reset to its own commit (the fixes-guard change) and main re-merged;
  the woven registers were re-generated on the settled tree by their own doors.
- Nothing is lost: the Hermes work lives in #496 exactly as it was proved there.

### Proven
- The merge into main completed with **no conflict** (`bin/README.md` auto-merged by
  the weave driver — the seat from #497 at work).
- This branch now touches only `bin/gates/guards/fixes-guard.sh` and its notes.
