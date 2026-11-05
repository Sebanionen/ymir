# Subsystem docs — the book to read before you touch a path

> Written 2026-10-23 after a night of missed critical information: the authoritative documentation for
> several subsystems lives **inside an app** (`apps/*/SKILL.md`, `AGENTS.md`, `cookbooks/`, `skills/`,
> `docs/`, `references/`), so no inventory of `bin/` will ever surface it, and nothing in the contract
> sent a hand to it. Twice in one night a claim was made from the tree that the subsystem's own book
> contradicted.

**Ask the door, do not remember:** `bin/records/where.sh <path or topic>`.

```
subsystems[12]{path,entry,canonical,books,doors,missing}:
  "hodd/docs/collaboration/** (home)","docs/features/fleet-wire.md","docs/features/collaborator-door.md","# the home shelf: the doors register, the fleet-wire runbook, the onboarding sheet (in $YMIR_HOME)","plans 154 · 158 · 184 · 192","the public MCP face for a collaborator tenant (plan 192 §9)"
  "apps/smidja/** | apps/smidja-factory/** | .agents/skills/smidja-factory/**","apps/smidja-factory/SKILL.md","apps/smidja-factory/AGENTS.md","apps/smidja-factory/cookbooks/ · apps/smidja-factory/skills/ · apps/smidja-factory/docs/ · apps/smidja-factory/references/","bin/desktop/smidja-{board,bootstrap,observe}.sh · scripts/electron.sh smidja","scripts/smidja (launcher: rosters/team/doctor) · roster.yaml (stacks:) · justfile · tests/local-models/"
  "apps/hlidskjalf/**","docs/features/the-thread.md",".agents/skills/galdr-ymirsystem/assets/hlidskjalf-ui.md","docs/features/ · docs/design.md",".pi/extensions/ymirhome.ts · bin/desktop/app-build.sh","—"
  "apps/odrerir/**","docs/features/the-rooms.md",".agents/skills/galdr-ymirsystem/assets/odrerir-hall.md","docs/features/","bin/desktop/app-build.sh","—"
  "apps/sessrumnir/**","docs/features/open-on-the-right-display.md","docs/features/the-seat-name.md","docs/features/","scripts/electron.sh","—"
  "bin/engine/**",".agents/skills/galdr-ymirsystem/assets/installation.md",".agents/skills/galdr-ymirsystem/assets/brokk-distro-runtime.md","RULES/05-platforms.md · RULES/25-agnostic-by-construction.md","bin/engine/**","—"
  "src/ymir_runtime/** | bin/agents/einherjar-spawn.sh | bin/agents/eindri-start.sh",".agents/skills/galdr-ymirsystem/assets/brokk-distro-runtime.md","AGENTS.md","RULES/08-delivery-gate.md · RULES/02-agents.md","bin/seat/herdr-run.sh","—"
  "bin/records/mimir* | bin/bridge/mimir-bridge.py",".agents/skills/galdr-ymirsystem/assets/memory-well.md","RULES/20-the-well-appends.md","docs/features/","bin/records/mimir.sh","—"
  "bin/time/nornir-* | config/cron.yaml*",".agents/skills/galdr-ymirsystem/assets/nornir-jobs.md","docs/features/the-clock.md","docs/features/","bin/time/nornir-cron-start.sh","—"
  ".pi/** | .opencode/** | bin/seat/valknut-load.sh",".agents/skills/galdr-ymirsystem/assets/harness-integration/README.md","RULES/13-pi-extensions.md","docs/features/","bin/seat/valknut-load.sh --check","—"
  "tools/**","tools/snotra/DOORS.md","docs/features/the-library-of-records.md","docs/features/","bin/gates/doors.sh","—"
  "docs/features/** | FEATURES.md","RULES/14-features.md","docs/features/README.md","docs/","bin/gates/guards/features-guard.sh","—"
  "bin/mail/**","bin/mail/README.md","docs/features/gna-the-one-mail-desk.md","bin/mail/tests/test_gna.py · plan 116 §15–§16 (plan ledger)","bin/mail/addresses.sh --check · bin/mail/inbound-test.sh · bin/mail/gna_desk.py --honesty · bin/time/nornir-job-gna-mail.sh --check","—"
  "bin/records/library.sh | RULES/34 | RULES/35","RULES/34-the-record-has-a-shape.md","RULES/35-the-research-is-kept.md","docs/features/the-library-of-records.md","bin/records/library.sh self-test","—"
```

**A `missing` cell is a fact, not a footnote:** the book names a door or a file that this tree does not
have. That is a ticket (`hodd/docs/tickets/`), never a reason to improvise the thing the book describes.
