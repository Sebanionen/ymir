# A pull request judges its OWN commits — not the synthetic merge GitHub writes

**Date:** 2026-11-03 · **Component:** gate · **Found while:** the identity ward failed every PR, correctly and uselessly

## What was wrong

`identity-guard.sh --base origin/main` judges `origin/main..HEAD`. On a pull request, `actions/checkout` puts
**GitHub's synthetic merge commit** at `HEAD`, and GitHub authors that commit with the account that opened the PR — the
operator's mailbox on the commit it creates, not on any commit the contributor wrote.

So the ward refused **every** pull request with a finding about a commit nobody authored: a true refusal aimed at the
wrong object. The same shape had already been paid for once — `fixes-guard` learned that a merge commit has no range of
its own (2026-10-24, three archive-tag pushes refused) — and the lesson is the same: **judge the commits the author
made, not the merge the host made.**

## What changed

When `HEAD` is a merge whose first parent is the merge base, the ward judges `merge-base..HEAD^2` — the PR's own side —
and names that range in its verdict, so the scope is never in doubt.

## What it does not change

The refusal is unchanged for a branch pushed directly (`--base origin/main` on a plain commit still judges it), and
nothing about the ward's purpose moves: a private mailbox in an author line is still refused on the commits that carry
it.

## Files

`bin/gates/guards/identity-guard.sh`
