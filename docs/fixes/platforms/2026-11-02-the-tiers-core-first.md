# The tiers — not every device runs every capability, and the core is what everyone runs

**Date:** 2026-11-02 · **Component:** platforms / installer · **At the Allfather's word:** *"all users might not
run all features that gimle can do. like if they have a fleet or not. if they have a server or not. ymir home and
basis ymir runtimes and templetes, extentions to pi, packets to opencode and other agent harnesses and logic are
the improtant."*

## What was wrong

RULES/05 and RULES/25 both answer *"does it work on this device?"*. Neither answers *"should this device have it
at all?"* — so the installer asks every user a fleet question to give them a personal one: `--role
heart|forge|dev|hand` is required, and a host with no role declared is SKIPped (`add "$id" SKIP "no role
declared"`). A person who wants an agent with a home, memory and a set of principles is being asked about the
heart's role to get one.

## What changed

RULES/25 gains a dated section defining four tiers and the law that follows from them:

- **0 · core** — the home, the baseline runtime (POSIX shell + python3 + git), the templates and principles, the
  skills, and the harness integrations (Pi extensions, the OpenCode package, the Claude Code / Codex / Cursor
  shims). Needs nothing but a shell, python3 and git.
- **1 · desk** — launchers, themes, voice, window rules, placement, crash sense.
- **2 · suite** — Gimlé: the gate and its applications.
- **3 · fleet** — roles, the heart's doors, A2A grants, dispatch.

And three demands: tier 0 installs and passes its gates on a machine with nothing else; a higher tier is a named,
gated addition that reports SKIP with its reason; the installer and updater are profile-aware
(`--profile core|desk|suite|fleet`, defaulting to `core`), with `--role` demoted to what it is — a fleet detail.

## Measured, before the change

```
installer flags today       --role  --skip-engines  --skip-services  --no-desktop
a host with no role         SKIP "no role declared — pass --role … or bin/skuld/role.sh set"
pi extensions shipped       12 (+ lib, constellation, excalidraw, logretta)
opencode surface            .opencode/{agents,plugins,package.json}
harness dirs                .pi .opencode .claude .codex .cursor
scripts that need a fleet   33
scripts that need a suite   9
core size                  574 shell doors · 32 skills · 56 python modules
```

So the core is already the largest and most portable part of the tree; what is missing is the *word* for it, and
a flag that installs it without asking about anybody's server.

## Still owed

The flag itself — `--profile` — with the role question only asked inside tier 3. Tracked as Phase 7 of plan 160.
