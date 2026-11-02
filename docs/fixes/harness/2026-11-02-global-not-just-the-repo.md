# Global, not just inside the checkout — the measurement behind the law

**Date:** 2026-11-02 · **Component:** harness / install · **At the Allfather's word:** *"ymir should not just work form
booting agents with in ymirs repo/folder. ymir should work globally over the users computers."*

## What was measured

```
global_state[5]{what,state}
  "the command","global — ~/.npm-global/bin/ymir → @zerwiz/ymir/bin/ymir.js, 0.1.53"
  "Pi capabilities","ABSENT — ~/.pi/agent/extensions/ holds .ymir-root and .ymir-seat and no extension"
  "Pi contract","ABSENT — no ~/.pi/AGENTS.md"
  "OpenCode / Claude / Codex contracts","present — ~/.config/opencode/AGENTS.md, ~/.claude/CLAUDE.md, ~/.codex/AGENTS.md"
  "capabilities in every harness","only from .pi/extensions/ and .opencode/plugins/ INSIDE the checkout"
```

Two causes under it: the published npm package carries **five** entries in `.pi/extensions/` where the tree carries
twelve or more, and **486 scripts** resolve the repository root through `BASH_SOURCE`, which is right inside a
checkout and wrong behind a symlink — so a `~/.local/bin` install of the doors would break them the way the moved
shelf broke Skírnir's twenty-four roots.

## What changed

RULES/25 gains a third dated section: a capability is installed only when it answers from a **neutral directory**
(`$HOME`, `/tmp`); the root resolves through realpath once; **every** harness gets the contract *and* the capabilities
in its own global dir; and the updater re-verifies the global set rather than only the checkout.

Plan 161 gains **Phase 8**: `ymir_root_from` in the platform shim, the whole capability set installed globally (Pi
included, with `~/.pi/AGENTS.md`), a package that ships the same set, Gróa re-verifying it, and `ymir doctor` proved
from `$HOME` and `/tmp`.

## Still owed

Phase 8 itself — the shim function, the 486 rooted scripts, the global writes, and the proof.
