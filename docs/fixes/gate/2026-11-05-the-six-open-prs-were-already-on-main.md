# The six conflicting PRs were already on main, and the one real delta shipped

**Date:** 2026-11-05 · **Component:** gate · **Errand:** one-open-pr (integrate the six)

## What was asked

Six open PRs against `zerwiz/ymir` all conflicted with `origin/main` as measured on
2026-11-05 (`a475eb46`): `#519 feat/one-door-for-the-registers` (ahead 3, 12 files),
`#518 fix/garmr-retention` (ahead 2, 3 files), `#516 feat/snotra-plan144-full-build`
(ahead 1, 2 files), `#515 backup/the-gate-parses-2026-10-23` (ahead 1, 4 files),
`#514 rules/platforms-and-tiers` (ahead 1, 5 files), `#513 compliance-fix`
(ahead 6, 197 files). The errand was to land their **commits** — never a merge — on one
branch, `integrate/open-prs`, and open one PR.

The ahead-counts were re-measured on this seat and matched the table exactly. What the
counts do not say is whether the *content* is still absent from main. For five of the six
it was not.

## What was measured, branch by branch

Each branch was taken by `git cherry-pick <its range>`, not by `git merge`. A pick that
resolves to an empty tree means main already carries that work through some other commit.

- `feat/one-door-for-the-registers` — all three commits empty against main. Main already
  holds the same changes as `0773a5a1 Who is in a Telegram chat — and what the Bot API
  will not say` and the earlier Skírnir apostrophe repair; `bin/notify/telegram-members.sh`,
  its page, its catalogue row and both fix notes are byte-identical to the branch's.
  The one commit that was not already there — `features-guard judges the declaration, not
  the workstation` — was already carried by the precede apply commit, so it landed with
  `fix/garmr-retention` (see below).
- `feat/snotra-plan144-full-build` — its single unmerged commit is a register
  regeneration; it resolves empty, so main's registers already say the same.
- `rules/platforms-and-tiers` — empty. Main's `bin/fleet/ymir-platform.sh` already carries
  all six shim verbs **and** a later `ymir_stat_c`, and main's
  `bin/gates/checks/portability-ratchet.sh` already carries the sixth verb row plus a
  stricter HEAD-based counter. The branch's ratchet is the older, tree-reading shape.
- `backup/the-gate-parses-2026-10-23` — empty once the plan-109 surface is kept. Main
  already has `step_opencode_v2_plugin` gated on the harness (RULES/25's tiers, not a dev
  role), a `step_codex_plugin` the branch does not have, and `ymir-tools.ts` refusing to
  guess `YMIR_HOME` where the branch still guesses `~/Documents/ymirhome`.
- `fix/garmr-retention` — **the one live delta.** Main already has the bounded trace
  (classes, dedupe, the security rows that are never folded); it did not have the reader
  budget. Carried as `db8f6f19 integrate(apply): fix/garmr-retention`.
- `compliance-fix` — superseded. Its first pass is on main as `6f7e8657 gate: bin gets its
  system folders — 250 doors moved`; its second pass moves 69 doors into
  `bin/seat/sessrumnir/`, an application-named folder in `bin/`, and main has since moved
  the same doors to `bin/desktop/` under RULES/23. Resolving all 69 conflicted paths
  toward main leaves an empty tree; `0490cc86` and its `72ad046e` revert cancel each other
  and were carried as the no-op pair they are.

## What was wrong in the precede apply, and what changed

The precede commit `db8f6f19` resolved `feat/one-door`'s `features-guard.sh` by keeping
**both** sides of the conflict, so `<<<<<<< ours` … `>>>>>>> theirs` sat inside the shipped
ward and that block parsed as nonsense shell. Repaired in `b312ff1b`: the branch's intent
is kept (judge the DECLARATION in `.gitattributes`, and the presence of
`bin/records/regenerate-on-merge.sh`, never the per-clone `git config`), main's newer
`check is the default` head is left alone, and the clone-local seating is reported as a
note rather than a fault.

## Measured after the integration

```
guards[25]{ward,status,finding}:
  runtime-guard.sh PASS · runtime-pinned-guard.sh PASS · defaults-guard.sh PASS
  app-folder-guard.sh PASS · app-functional-guard.sh PASS · rules-number-guard.sh PASS
  inventory-guard.sh PASS · registers-guard.sh PASS · fleet-version-guard.sh PASS
  subsystem-docs-guard.sh PASS · path-ledger-guard.sh PASS · path-legality-guard.sh PASS
  packaging-guard.sh PASS · public-data-guard.sh PASS · cron-guard.sh PASS
  features-guard.sh PASS · weave-guard.sh PASS · vault-guard.sh PASS
  confidential-guard.sh PASS · dead-code-guard.sh PASS · docs-claims-guard.sh PASS
  home-contract-guard.sh PASS · language-guard.sh PASS · pkill-guard.sh PASS
  skills-share-guard.sh PASS
```

## What stays unmade

The six PRs are **not closed and nothing was merged** — the seat closes them after the
Allfather's word. `#518` is the only one whose content the branch adds to main; the other
five add nothing that main does not already say, and their branch pointers should be
retired rather than re-opened.
