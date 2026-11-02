# Plan 109's OpenCode plugin, recovered from the branch it died on

**Date:** 2026-11-02 · **Component:** harness

## What was wrong

Plan 109 built an **OpenCode V2 plugin with twenty Ymir tools and two commands** — the parity the Allfather
remembered — and it never reached `main`. The carrying commit `b97f11ed` is an ancestor of
`fix/the-gate-parses` and its backup branch only. The install step went with it, so an OpenCode user got the
supervision guards and none of the house's capabilities.

## What changed

`b97f11ed` is cherry-picked onto `feat/opencode-v2-plugin-recovered`, which restores:

- `.agents/harness/opencode/plugins/ymir-tools.ts` — the twenty tools and two commands, ported from Pi;
- `.agents/harness/opencode/plugins/{package.json,tsconfig.json,lib/}`;
- `.agents/skills/galdr-ymirsystem/assets/harness-integration/opencode-audit.md`;
- `step_opencode_v2_plugin` in `bin/engine/ymir-install.sh`.

And two corrections the recovery needed:

1. **The install step was gated on the `dev` ROLE** — `role_gate opencode_v2_plugin dev`. A harness integration
   is tier 0 (RULES/25, 2026-11-02): it now gates on `have opencode`, so any seat with OpenCode on it gets the
   plugin, and a seat without OpenCode reports a clean skip.
2. **Gróa never re-deployed it.** `bin/agents/groa-update.sh` now re-checks the harness contracts
   (`bin/seat/harness-contract-install.sh --check`) and re-copies `ymir-tools.ts` into
   `~/.config/opencode/plugins/` when the tools changed — so an update reaches the user's own harness.

## Still owed

Loading the plugin under OpenCode and proving the twenty tools answer (plan 161 Phase 0's acceptance), and the
same parity for Claude and Codex hooks (Phase 3).
