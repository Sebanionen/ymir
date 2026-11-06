---
name: smidr-the-workbench
description: Smíðr — the craft, taught at the bench: how a hand from another house works inside this repository, from the branch to the pull request, without breaking its law or its gates. Use when you are a contributor's agent in a repository that is not yours, before your first branch, before a fix, before you open the pull request, and when a gate refuses you.
domain: collab
allowed-tools: read,write,bash,glob,grep
role: craftsman
norse_name: Smíðr
descriptor: the craft, taught at the bench
capabilities:
  - contributor_discipline
  - gate_reading
  - small_slices
---

# Smíðr — the craft, taught at the bench

Read this once, at the start, and once again before the pull request. It is the discipline of a guest hand: the work is
wanted, the house's law is not yours to edit, and the reviewer's time is the scarcest thing in the building.

## The shape of a slice

```
slice[6]{step,rule,why}:
  "1 · read before you branch","`AGENTS.md`, `RULES/`, the plan that owns your work","a rule discovered after the code is a rewrite, not a fix"
  "2 · branch from the latest base","`git fetch` then branch from `origin/main` — never from your last branch, never from a stale clone","a branch cut before the rules is a branch that breaks them silently"
  "3 · one concern, one pull request","a screen, or a module, or a rule — not a screen and a module and a rule","a 800-line pull request cannot be reviewed, and an unreviewed change cannot be learned from"
  "4 · the note with the change","`scripts/fixes.sh record --component=<area> --title=\"…\"` in the same commit range","a behaviour change with no note is refused at the push, and the note is what a later hand reads"
  "5 · a test beside a new module","a module earns a test that names it, or one line in `.module-test.allow` saying why not","reachability is not behaviour"
  "6 · the pull request in the same session","`gh pr create` before you stop, not tomorrow","a branch that exists on the remote with no pull request is refused at the second push"
```

## Five things that are never yours to change quietly

```
referee[5]{thing,why,what_instead}:
  "the gates (`scripts/gates/`)","they decide whether work may land; a gate edited to pass is not a gate","fix it, and say why — a note under `docs/fixes/` and a word in the message; the referee guard demands both"
  "the hooks (`.githooks/`)","the same","the same"
  "the wards (`scripts/wards/`)","they are the doctor this house trusts","the same"
  "another hand's plan or baton","plans and batons are appended, never rewritten","add a dated section citing it, or write your own"
  "another hand's pull request","it is theirs to tend","review it with a file, and say what is good before what is wrong"
```

## When a gate refuses you

A refusal is a sentence with a reason, not an obstacle. Read the reason, fix the cause, and **never** reach for
`--no-verify` — the one acceptable use is a gate that is provably wrong, named in the commit message, and fixed in the same
range.

```
refused[5]{what_you_see,what_it_means,do}:
  "\"a behaviour change with no note\"","your range changes behaviour and carries no `docs/fixes/` note","record the note, then push — the same range"
  "\"the referee is changed with no explanation\"","you touched a gate, a hook or a ward","say which and why in the message, and add the fix note"
  "\"a module arrived with no test\"","a new file with no test naming it","write the test, or declare why in `.module-test.allow`"
  "\"a branch that exists on the remote with no pull request\"","the first push was allowed; this is the second","open the pull request — that is what the branch was for"
  "\"master is protected\"","only a human seals a merge","push your branch; the pull request is the delivery"
```

## Before you say you are done

```bash
npm run check      # the wards — a fault here is a fault, not a warning to accept
npm test           # the behaviour
npm run typecheck  # the contract
bash scripts/pr-check.sh   # is every commit of yours proposed?
```

If a command is missing from the repository, that is a finding worth reporting — not a reason to claim the check was run.

## What this skill is not

It is not the house's law and it does not replace `AGENTS.md`. Where the two disagree, **the repository wins**; the skill is
the part a repository usually forgets to write down because everyone senior already knows it.

## CHANGE LOG

- **2026-11-06** — Written with the kit's referee and module-test guards, from a collaborator's review: the faults were process, not craft.
