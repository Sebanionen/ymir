# The gate uses the ward's merge-aware range, not `--base`

**Date:** 2026-11-03 · **Component:** gate · **Third fault in the same ward, found by CI**

## What was wrong

The ward grew a merge-aware range (`HEAD^1..HEAD^2`, the contributor's own commits) and the test that proves it —
but `ci-verify.sh` still called it as `identity-guard.sh --base origin/main`, which takes the *other* branch of the
ward and judges the base's own commits. So the fix was inert exactly where it was needed, and CI kept refusing every
pull request for a mailbox in a commit no contributor wrote.

**The lesson is the same one three times over:** a ward that judges a range must be called the way it was written to
be called, and the caller is part of the gate. A ward proved on a laptop and invoked differently in CI is a ward that
has never run.

## What changed

`ci-verify.sh` calls `identity-guard.sh --check` (the merge-aware path on a PR, the branch path on a plain push), with
the reason written at the call site.

## Files

`bin/gates/ci-verify.sh`
