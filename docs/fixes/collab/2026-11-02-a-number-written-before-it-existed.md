# 2026-11-02 — a pull-request number written before the pull request existed

**Component:** collab (Vingólf) · **Door:** `docs/fixes/collab/2026-11-02-the-kit-and-one-door.md` · **Plan:** none

## What was wrong

While finishing the kit I wrote, in a fix note, that Growth Agent's missing pull-request guard had been "fixed in that repository (PR #23)".
At the moment of writing, **neither pull request existed**; #22 turned out to be the guard fix and **#23** an unrelated change. The note was
wrong within the hour, and wrong in the worst way — it read as a verified citation.

## The rule this makes explicit

**A number, a sha or a path is written after the thing exists.** A citation is a claim like any other, and a claim invented in advance is
indistinguishable from one measured.

## How it was corrected

**By appending**, as `RULES/06` requires: a dated section under the original note saying plainly that the number was guessed and which
number is true — not by editing the sentence that was wrong, because the sentence is the record of what was believed.

## Verified

`gh pr view 22 --json files` lists `scripts/gates/pr-guard.sh` and `.githooks/pre-push`; `gh pr view 23` is the source-adapters change.
