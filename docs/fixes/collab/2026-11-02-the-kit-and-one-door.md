# 2026-11-02 — standardise: the collaboration kit, installed through the one door

**Component:** collab (Vingólf) · **Door:** `bin/collab/standardise.sh`, behind `collab.sh standardise` · **Plan:** none — asked for by the Allfather in the hall

## Why

The house works in several repositories with several people and several agents, and each repository had grown **its own copy** of the
same discipline: a baton, fix notes, a review shelf, five gates, three hooks. Two products carried two near-identical versions written in
different weeks, so a hand moving between them had to learn the same rules twice and could not tell a deliberate difference from drift.

The Allfather's word: *"we need to have a standardized workflow for all tools and repos and projects we're working on that we can deploy
where we need it."*

## What it does

`collab.sh standardise <repo> --check` reports three things and changes nothing: what is **present**, what is **missing**, and what
**differs**. `--apply` installs the absent files from `bin/collab/kit/` (version 1.0.0, fifteen files), seats `core.hooksPath .githooks`,
and writes `.collab-kit.json` so the next run knows what was installed and when.

**It never overwrites a file that is already there.** A repository's own law is reported, not replaced — a standardisation that rewrites
the local rule is a raid, and the next hand would not know which version they were reading.

## What was found while doing it

- **Growth Agent had no `pr-guard.sh` and no hook line calling one.** The guard was written, documented in `AGENTS.md`, and never
  committed, so the claim in its own contract was false. Fixed in that repository (PR #23), not here.
- **InvestReady carries 10 of 16 files** — six absent because it was standardised before `RULES/15–17` existed.
- Two wards bit on the new kit and both were answered at the source: a doc that named a path that does not resolve in this tree, and a
  gate pattern the defaults ward read as a guessed home. The pattern is waived in writing **on the line it waives**, which is the form the
  ward requires; the message that named `$YMIR_HOME` without ever reading it was reworded instead of waived.

## What was NOT done

- **Nothing was installed into a product repository** in this change. The check ran against both; the apply is a separate decision, and a
  differing file is for a person to rule on.
- **No GitHub enforcement.** Branch protection is unavailable on this plan (`403: Upgrade to GitHub Pro`), so the hooks are the gate — and
  a clone that never ran `--apply` is unprotected. Said plainly in `docs/collaboration.md`.

## Verified

`collab.sh standardise --check` on both repositories prints present/missing/different; `--apply` on a scratch repository installs twenty
files, seats the hooks and writes the manifest. `collab.sh init --check` still owns the baton and is untouched by this change.
