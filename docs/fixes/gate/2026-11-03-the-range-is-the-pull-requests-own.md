# The range is the pull request's own commits — `HEAD^1..HEAD^2`, no merge-base, no fetch

**Date:** 2026-11-03 · **Component:** gate · **Second fault in the same ward, found by CI**

## What was wrong, again

The first fix judged `merge-base..HEAD^2` when it could tell that `HEAD` was GitHub's synthetic merge. On a shallow
`actions/checkout` the merge base is the shallow boundary, not the base branch's tip — so the test for "is HEAD the
host's merge" did not hold, the ward fell back to `origin/main..HEAD`, and that range **includes the base's own
commits** — where the operator's mailbox lives in 1,236 published commits. The ward therefore refused every PR with a
true finding about a commit no contributor wrote, for ever.

## The fix, which needs no base branch at all

GitHub's merge commit has the base as its **first** parent and the PR's head as its **second**, so
`HEAD^1..HEAD^2` is exactly the set of commits the contributor wrote — on a shallow checkout, with no fetched base,
and structurally incapable of including a base commit. The verdict names the range and its size.

## The lesson, shared with `fixes-guard` and `no-delete-guard`

**A ward that judges a range must be able to say which commits are IN it, and the host's own commits are never in a
contributor's range.** Two wards have now learned this the same way; it belongs in the rule the next ward is written
against.

## Files

`bin/gates/guards/identity-guard.sh`
