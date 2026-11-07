# The register does not count a template — fifteen files were doors Ymir never runs

**Date:** 2026-11-03 · **Component:** gate · **Found while:** getting the collaboration PR green

## What was wrong

`bin/gates/capabilities.sh` walks every `bin/**/*.sh` and asks the question the register exists for: *what
can Ymir do, and which door does it?* The collaboration kit landed twelve shell files under
`bin/collab/kit/scripts/` — a standard **copied into another repository**, never executed by this one.

The register counted them as doors, with the disposition `keep (a human or a cron row must run it)` — a
sentence that is false about every one of them — and CI's `capability` gate went red on 664 vs 676. The
nearer fault is not the count: it is that the register offered to **move or retire** (Rule 11) a shipped
template, which is content a repository is given.

## What changed

- `capabilities.sh` skips `bin/collab/kit/*` when it enumerates doors, with the reason written in the file:
  a template is content, not a door. `bin/README.md` still indexes them as files — it answers "what is on
  this shelf", not "what can the house do".
- The register regenerated: 664 shell doors, the same as before the kit landed, which is the honest number.

## Why it is a gate fix and not a test fix

Nothing was wrong with the kit, and nothing was wrong with the test. The register asked the wrong question
of the right files: `bin/` holds both doors and shipped templates, and only the generator knows the
difference. A count that includes a template is a count that makes an operator chase a nonexistent runner.

## Files

`bin/gates/capabilities.sh` · `.agents/assets/agents/capabilities.md`
