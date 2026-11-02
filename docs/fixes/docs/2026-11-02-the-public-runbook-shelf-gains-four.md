# The public runbook shelf gains four — runtime, harnesses, platforms, gates

**Date:** 2026-11-02 · **Component:** docs

The private shelf (`$YMIR_HOME/hodd/docs/runbooks/`) grew today with `runtime.md`, `harnesses.md` and
`platforms.md`. The **public** shelf had eight pages — models, agents, agent-permissions, updates-and-migrations,
secrets-and-hoard, worktrees-isolation, a2a, realm-onboarding — and none of them covered anything this day changed.

Added here, written for an operator with no knowledge of any particular machine (no hostnames, no seat names, no
private paths — Rule 04):

- **`runtime.md`** — the pinned checkout, `bin/engine/runtime-deploy.sh`, `runtime-pinned-guard`, and the four
  faults we actually hit (missing dependency closure, a unit rewritten back to the working tree, the wrong
  interpreter, a calendar that will not answer).
- **`harnesses.md`** — the nine harnesses plus Zed, the descriptors in `.agents/harnesses/`, the two install verbs,
  and the table that matters before anyone writes a transcript reader: **three storage shapes across five
  harnesses** (jsonl tree · flat jsonl · sqlite), with the exact paths.
- **`platforms.md`** — Linux real, macOS and Windows by hosting Linux, the installers and manifests, the six
  portable verbs, the ratchet, and the safe order for routing a caller.
- **`gates-and-wards.md`** — what twelve wards refuse, how to add one (including the one-list rule), and what to do
  when one is red: read its message, run it on `main`, never hand-edit a register, and treat a flickering ward as a
  bug in the ward.

The index (`docs/runbooks/README.md`) now names twelve pages.

**Why this matters more than another audit.** Every fault found today was found by somebody who knew where to look.
A runbook is what makes the next person able to look.
