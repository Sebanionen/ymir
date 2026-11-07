## gate · 2026-11-03 — the fixes-guard judges our own commits, and the map learns what it generates

### Why
Pushing a branch that had **merged main** was refused with *"no fix note in this
range"* although correct notes rode in it: the guard judged `git diff remote..HEAD`,
which drags **every path main brought** into the range, so no note could ever cover
the push (measured on PR #493). Two further paths the branch touched —
`bin/gates/registers.sh` and the derived registers (`bin/README.md`, the backend
index, `capabilities.md`) — mapped to **no component** at all, so a note that named
them covered nothing; the same defect the 2026-10-12 StartLimit mend found.

### Mend
- **A merge is not a change.** The range's notes and touched paths are read from
  `git log --no-merges --name-only`: a branch that took main in owes no note for
  main's history.
- **The map learns the gate's own output:** `bin/gates/registers.sh`,
  `bin/gates/guards.sh`, `bin/gates/tests/*`, the woven catalogue (`FEATURES.md`,
  `docs/features/*`) and the three derived registers now map to `gate`.
- A correction to a note already pushed is itself a change: it owes a **new** note
  (Rule 06) — the state that produced this file.

### Proven
- `fixes-guard.sh --check` on a branch with a merge + register changes:
  *ok — N note(s), and the record speaks to the change*.
- `fixes-guard.sh` with the hook's own ref input on the same branch: *ok*.
- All 22 wards PASS on the tree.
