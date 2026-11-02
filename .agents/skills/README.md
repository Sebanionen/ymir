# GUNGNIR — Core Operational Skills

Every reusable task becomes a scripted skill here. Skills are validated in Utgard
before registration, and every skill is named for the myth figure whose role
matches its work (Gungnir naming law).

## Registry (`.agents/skills/`)

Every skill has an **owner agent** (`.agents/agents/<name>.md`): the seat Brokk
dispatches for that work. A skill owned by `brokk` means the primary keeps it in
hand — a dedicated seat is added when the work earns one.

```
skills[29]{skill,does,owner}:
  "galdr-ymirsystem","agent-CLI ergonomics — the master builder/maintainer of the runtime","galdr"
  "tyr-check","the judge — galdr principles + runtime gates","tyr"
  "rules-check-drift","rules-file drift — keeps AGENTS.md true after code changes","tyr"
  "no-mistakes","the clean-PR gate — vendored engine skill: validate, push, PR, CI","brokk"
  "smidja-factory","the smithy — agent factory: roster, phases, envelopes, visualizer (app-provided: cloned by step_apps from its own repo, absent until then)","volundr"
  "hvild-afk","away-mode — supervision of routine wakes and batched escalations","brokk"
  "saga-bearings","bearings — fleet status digest (/bearings) + recap (/ahoy)","saga"
  "muninn-stow","memory — session-knowledge curation, routing, persistence","muninn"
  "jord-projects","projects — registry + delivery posture","jord"
  "urdh-hold","hold lifecycle — decisions held for the Allfather, reconciled","urdh"
  "frigg-consent","consent — ask-user authority gate","frigg"
  "vor-diagnostics","diagnostics — bootstrap + diagnostic reasoning","vor"
  "nornir-schedule","schedule — event sources + quota-aware dispatch","brokk"
  "nsr-compliance","compliance — NorthStar scaffold/audit + the .compliance/ harness","brokk"
  "lifecycle","lifecycle — start/stop/status/smoke-test wiring contract","brokk"
  "gjallarhorn-relay","relay — public replies (X/Discord)","brokk"
  "eindri-homes","worker homes — provisioning and upkeep of Eindri homes","brokk"
  "syn-recovery","recovery — stuck-worker playbook","syn"
  "ymir-host","host ops — self-update, Omarchy desktop, Þjazi backend","brokk"
  "groa-update","the updater shaman — self-update Brokk + every Eindri-home (/updateymir)","groa"
  "herdr-panes","terminal panes — seat/control panes, tabs, workspaces, agents (HERDR_ENV=1)","brokk"
  "ratatoskr-a2a","A2A/MCP mesh — a2abridge + wayofteams; registration","brokk"
  "hamr-adapters","harness adapters — per-harness reference","brokk"
  "pr-ops","pull requests — create, update, check status, request merge","brokk"
  "hnoss-design","design — artifacts via OpenDesign (prototypes, decks, dashboards, image, video)","hnoss"
  "bragi-marketing","marketing — research/crawl (Firecrawl), agentic browser (browser-use)","bragi"
  "bragi-translation","translation — speech→text (whisper.cpp) + text→text (the llama router); carries words between tongues","bragi"
  "elder-home","the keeper — home records: the plan ledger, documentation, and memory (Reginn, the keeper who remembers)","elder"
  "snotra-meeting-outcomes","meeting record — transcript to minutes, decision log, owned actions, per-person briefs, Trello payloads","snotra"
  "vingolf","the assembly hall — who collaborates with the house, the six rungs, the baton shelf, the letter, the ship door","ursula"
  "maestro-video","the video forge — Maestro over REST: t2v, i2v, music, voice, and the provision road for a seat","volundr"
```

The control-plane UI guide is not a standalone skill: **hlidskjalf-ui** and its
hall **Óðrerir** (odrerir-hall) are assets under **galdr-ymirsystem** (the master
builder), loaded from `.agents/skills/galdr-ymirsystem/assets/` — see the galdr router.

Not adopted as standalone skills: `firstmate-coding-guidelines` (folded into Galdr),
`firstmate-orca` / `firstmate-codexapp` (backend reference docs only).

## Skill synthesis rules (Gungnir)

1. Gap identified → write the skill doc + script to `.agents/skills/<name>/`.
2. Validate inside an Utgard container.
3. Register it in this index.
4. **Norse-name every new skill** at synthesis: choose the figure whose role
   matches the work and let the skill inherit that name (`<figure>-<what>`).

Governance: `.agents/skills/galdr-ymirsystem/SKILL.md`; adopted-skill provenance is recorded in
`.agents/skills/galdr-ymirsystem/assets/reference-adoption.md`.
