# The OpenCode package that never shipped — plan 109 died on an unmerged branch

**Date:** 2026-11-02 · **Component:** harness · **At the Allfather's question:** *"we have build the opencode packets
before. where did they go? why dont they ship with ymir now?"*

## What was found

Plan 109 (`109-opencode-v2-plugin-integration.md`) built precisely what he remembered: an **OpenCode V2 plugin with
twenty Ymir tools and two commands**, ported from the Pi set —

`ymir_recall · ymir_remember · ymir_errand · ymir_heal · ymir_update · ymir_note · ymir_plan · ymir_push ·
ymir_daily · ymir_find_home · ymir_place · ymir_import · ymir_structure · ymir_find · ymir_index ·
ymir_secret_keys · ymir_layout · subagent · ymir_well · ymir_dellingr`

plus the `gna-watch-arm` and `subagents` commands, a `step_opencode_v2_plugin` install step in
`bin/engine/ymir-install.sh`, a redeploy check in `bin/agents/groa-update.sh`, and an audit at
`.agents/skills/galdr-ymirsystem/assets/harness-integration/opencode-audit.md`.

**It never reached main.** The carrying commit `b97f11ed` is an ancestor of `fix/the-gate-parses` and
`backup/the-gate-parses-2026-10-23` only; `git merge-base --is-ancestor b97f11ed origin/main` answers no. The install
step and the plugin shelf left with the branch.

What ships on main today is the older guard set — `.agents/harness/opencode/plugins/` and `.opencode/plugins/`:
`saga-sessionstart · syn-cd-check · syn-pretool-check · syn-turnend-guard · syn-watch-arm`. **Five guards, no
tools.** So an OpenCode user today gets the supervision wire and none of the house's capabilities.

## Why it matters beyond one package

This is the second instance of one fault in a single day: work that was *built* and *tested* but whose delivery was a
branch rather than a merge. The first was the Gimlé desk, which ran ahead of the tree on the heart. The rule that
covers both is Rule 08 (delivery is by PR) read the other way round: **a branch is not a delivery, and "we built it"
is not "it ships".**

## What changed

RULES/13's 2026-11-02 section now demands that the extensions/plugins and the instruction file each harness reads are
written into the user's own home on install **and re-verified on update**, with a probe that fails when the user's
global agent and the house's shipped one disagree. Plan 161 gains **Phase 0**: recover plan 109's plugin, shelf and
install step from `fix/the-gate-parses`, land them on main, and prove the twenty tools answer under OpenCode before
any new parity work starts.

## Still owed

Phase 0 of plan 161 — the recovery itself.
