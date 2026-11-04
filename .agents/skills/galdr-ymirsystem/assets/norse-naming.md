# Norse Naming Law — the complete component map

> Purpose: the single source of truth for Ymir's Norse methodology — the law, every figure in use, the Galdr aett prefixes, the rules for naming new work, and the reject list.

## 1. The law

> **Name every subsystem, component, and process for the figure whose role matches its work.**

Three clauses make the law enforceable:

1. **Name for the role, never the mood.** A component is named for *what it does* — Sága is the seeress because she sees all that happens and therefore owns the session-start digest. Do not name a component after a figure you merely like.
2. **Flavor may season a line; it must never name a subsystem or leak into docs.** Conversational Norse color ("the forge is hot") is permitted in a spoken reply. It is forbidden in file names, subsystem names, commits, briefs, PRs, and any Markdown the runtime or other agents read — including every file in `.agents/skills/galdr-ymirsystem/assets/`.
3. **The operator is the the Allfather, never the imported `captain`.** the Allfather sees all realms from Hlidskjalf; the operator is the one who sits there. Brokk addresses the Allfather directly in every response and never sends a response with zero direct address. Nautical or upstream terms (`captain`, `first mate`, `crew`, `ship`, `treehouse`) are rejected outright — see §6.

The law is restated in four authoritative places; keep them consistent:
`AGENTS.md:6` (SYSTEM MANDATE), `data/operator.md` (Voice), `docs/plans/29-brokk-distro-runtime.md:270-276` (Norse naming law), and this file.

## 2. The operator and the primary

| Figure | Role | Where it lives |
|---|---|---|
| **Allfather**  | The single human operator. Sees all realms from Hlidskjalf; talks only to Brokk. Never a subsystem — an address. | `AGENTS.md:6`, `data/operator.md` |
| **Brokk** | The primary autonomous agent. The smith who keeps the forge hot; the single point of contact, dispatcher, and supervisor. | `AGENTS.md` (header), `opencode.json` → `default_agent: "brokk"`, `.agents/agents/brokk.md` |
| **Ymir** | The platform itself: base host OS, master daemon, the root the whole system is named for. | repository root `$YMIR_ROOT`, `AGENTS.md:24` |

**Addressing rule.** Every Brokk response opens to or includes the Allfather directly ("Allfather, …"). Broken address is a contract violation, not a style preference.

## 3. The complete component map

### 3.1 Platform subsystems (`AGENTS.md:20-46`)

| Subsystem | Norse figure | Role | File / path |
|---|---|---|---|
| Master platform root | **Ymir** | Base host OS, master daemon | `$YMIR_ROOT` |
| Primary agent | **Brokk** | Main autonomous worker; forge-master | `AGENTS.md`, `opencode.json`, `.agents/agents/brokk.md` |
| Sub-agent worker | **Eindri** | Isolated sandboxed worker ("the one who runs the errand") | `.agents/subagents/*.md`, `bin/agents/einherjar-spawn.sh` |
| Eindri specialist — code | **Sindri** (smith) | Code synthesis, refactoring, development | `.agents/subagents/developer.md` |
| Eindri specialist — content | **Bragi** (skald) | Content, SEO, social, marketing campaigns | `.agents/subagents/marketer.md` |
| Eindri specialist — research | **Huginn** (sage) | RAG, web search, analysis, knowledge discovery | `.agents/subagents/researcher.md` |
| Git worktree manager | **Yggdrasil** | Branch isolation, zero-collision parallel edits | `.agents/tools/yggdrasil.ts` (planned), `.yggdrasil/<id>/`, `bin/agents/einherjar-spawn.sh` |
| Docker execution sandbox | **Utgard** | Ephemeral container execution barrier | `.agents/sandbox/Dockerfile.utgard`, image `utgard-runner:latest` |
| Reverse proxy / gateway | **Bifrost** | HTTP routing, external traffic ingress | platform services |
| OAuth / security | **Heimdall** | Authentication guardian | platform services |
| Cloudflare tunnel | **Gjallarhorn** | Outbound encrypted tunnel | platform services |
| User dashboard | **Hlidskjalf** | Observability, monitoring, control panel | `apps/hlidskjalf` |
| Web file browser | **Skrymir** | Web-based file explorer | platform services |
| Multi-tenant domains | **Svartalfaheim** | Scoped tenant workspaces | `svartalfaheim/<realm>/` |
| Global shared workspace | **Midgard** | Cross-tenant shared repos & assets | `midgard/` |
| Inter-agent A2A bus | **Ratatoskr** | A2A 1.0 backbone: agent cards, task lifecycle, Redis queue | `.agents/bus/protocol.ts` |
| Vector DB & memory | **Mimirsbrunn** | Long-term memory, embeddings, vector store | `.agents/memory/mimirsbrunn.db` |
| Audit trail | **Runes** | Append-only system audit ledger | `bin/records/runes-append.sh`, `workspace/memory/runes_audit.md` |
| Issue-to-PR pipeline | **Mjollnir** | Autonomous bug-fix and PR creation | `.agents/github/webhooks/issue_listener.ts` |
| Process health monitor | **Valhalla** | PM2/Docker process supervisor | platform services |
| Skill synthesis engine | **Gungnir** | Dynamic skill creation & validation | `.agents/skills/` |
| Agent ergonomics standards | **Galdr** | TOON output, 10 design principles, skill synthesis | `.agents/skills/galdr-ymirsystem/` |
| MCP/A2A composition | **Hermóðr** | MCP vertical (agent→tools) + A2A horizontal (agent↔agent) | `.agents/skills/galdr-ymirsystem/assets/pi-boot/herdr-profile.toml` (pane layout) |
| Software smidja | **Smíðja** | Repeatable agent+code pipeline: rosters, bounded phases, typed envelopes, retries/acceptance, trace | `.agents/skills/smidja-factory/` |
| Smíðja orchestrator | **Völundr** | The master smith who runs Smíðja — the smidja's Kaia (Kaia's seat inside the smidja) | `.agents/skills/smidja-factory/skills/volundr/` |
| Meeting ear (capture · transcribe · minutes) | **Snotra** | The wise one, mistress of counsel — the minutes-maker; hears the meeting, keeps the record | `systems/snotra/services/ear/snotra-capture.sh`, `systems/snotra/services/ear/snotra-transcribe.sh`, `systems/snotra/services/ear/snotra-ensure.sh`, `tools/snotra/`, `tools/mill/systemd/snotra.service` |
| Meeting room (our own hall) | **Þing** | The assembly, the law-meeting — a hall of our own (MiroTalk P2P fork on whynot) where the ear knows the room, the participants, and the moment it began | `zerwiz/mirotalk` (fork), deployed `~/thing/mirotalk` on whynot (unit `thing.service`) |

### 3.1b Machine agents — two agents per host, each named by the law

**No agent is named Brokk (Rule 44).** Brokk is the counsellor's ROLE; every host names both of its
agents, and every agent declares **house · fleet · machine · Allfather**.

| Agent | What it is | Where its name lives |
|---|---|---|
| **seat primary** | works INSIDE Ymir on that host (the figure whose role matches the seat's work) | `hodd/identity/seats.yaml` → `seats.<host>.primary` |
| **machine agent** | the operator's agent that keeps that COMPUTER alive and working | `hodd/identity/seats.yaml` → `seats.<host>.machine_agent` |

**Rules for naming either one.** State the role in one sentence, choose the figure whose mythic role
is that sentence; never reuse another host's name; never name an agent `brokk`; if the Allfather has
not sealed one, the render says **unnamed** — never an invention. The renderer is
`bin/seat/seat-surface.sh` (it refuses a roster that names an agent `brokk`), run by **install and
every update**. **The roster itself is private** and lives in the operator's home, never in this
repository (Rule 04).

### 3.2 Brokk distro runtime components (`docs/plans/29-brokk-distro-runtime.md:270-297`)

These are the figures the port actually wired into `bin/` and the harness adapters. This table is the authoritative runtime map; `brokk-distro-runtime.md` describes their behavior.

| Component | Norse figure | Why this figure | Concrete file(s) |
|---|---|---|---|
| Operator | **Allfather** | The one who sees all realms from Hlidskjalf | (address only) |
| Primary agent | **Brokk** | The smith who keeps the forge hot | `AGENTS.md`, `opencode.json`, `.agents/agents/brokk.md` |
| Sub-agent worker | **Eindri** | "The one who runs the errand" | `.agents/subagents/*.md`, `bin/agents/einherjar-spawn.sh` |
| Session-start digest | **Sága** | The seeress who sees all that happens | `bin/time/saga-session-start.sh`, `bin/time/saga-sessionstart-run.sh` |
| Daily briefing (same seeress, dated) | **Sága** | The daily seeing | `bin/time/nornir-job-daily-briefing.sh` |
| Watch / supervision | **Sýn** | Watchful sight; guards the turn boundary | `bin/pi/syn-watch-arm.sh`, `bin/gates/guards/syn-turnend-guard.sh`, `.pi/extensions/syn-turnend-guard.ts`, `.opencode/plugins/syn-watch-arm.js`, `.opencode/plugins/syn-turnend-guard.js` |
| Watch wake messenger | **Gná** | Frigg's rider who carries word | `.pi/extensions/gna-pi-watch.ts` |
| Digest process supervisor | **Vörðr** | The warden who holds the child | `.pi/extensions/lib/vordr-sessionstart-supervisor.mjs` |
| Operational wire | **Rödd** | The voice between Allfather, Brokk, and Eindri | `bin/agents/rodd-operational-input.sh`, `.pi/extensions/lib/rodd-operational-input.ts`, `.opencode/plugins/lib/rodd-operational-input.js` |
| Session lock | **Gleipnir** | The impossible chain that binds one session | `bin/vault/gleipnir-lock-lib.sh` → `state/.lock` |
| Harness detection | **Hamr** | The shape a being wears | `bin/fleet/hamr-harness.sh` |
| Worker spawn | **Einherjar** | The chosen who are gathered to fight | `bin/agents/einherjar-spawn.sh` |
| Worker brief | **Erindi** | The errand given to a worker | `bin/agents/erindi-brief.sh` → `data/<id>/brief.md` |
| Worker-state reconciliation | **Vör** | Awareness of what is | `bin/records/vor-crew-state.sh` |
| Scheduled jobs (the fate-spinners) | **Nornir** | The fates who govern time | `bin/time/nornir-cron-start.sh`, `bin/time/nornir-job-*.sh`, `config/cron.yaml` |
| Memory housekeeping | **Muninn** | The raven of memory (remembers and prunes) | `bin/time/nornir-job-memory-housekeeping.sh` |
| External observation | **Huginn** | The raven of thought/observation | `bin/time/nornir-job-observer.sh` |
| Git sync | **Yggdrasil** | The world-tree kept in order | `bin/time/nornir-job-git-sync.sh` |
| Audit ledger | **Runes** | The carved record | `bin/records/runes-append.sh`, `workspace/memory/runes_audit.md` |
| Session wake drain | **Sága** | The seeress who sees the queue | `bin/time/saga-wake-drain.sh` → `state/.wake-queue` |
| Arm-path seatbelt | **Sýn** | Guards the arm command | `bin/gates/checks/syn-arm-pretool-check.sh` |
| Directory seatbelt | **Sýn** | Guards the working directory | `bin/gates/checks/syn-cd-pretool-check.sh` |
| Invariant seatbelt | **Sýn** | Guards the load-bearing invariants (lock, markers, Runes, machinery, secrets, registries) | `bin/gates/checks/syn-guard-pretool-check.sh` |
| Updater shaman | **Gróa** | The völva who renews — fast-forwards Brokk and its homes, then mends forward | `bin/agents/groa-update.sh` (alias `bin/agents/brokk-update.sh`), `.agents/skills/groa-update/` |
| Doctor / healer | **Eir** | The goddess of healing — diagnoses every surface, then mends the broken | `bin/agents/eir-doctor.sh` |

### 3.3 The Galdr skill family

| Skill | Norse | Role | Path |
|---|---|---|---|
| `galdr` | Galdr | AXI incantation standards — ergonomic CLI for agents | `.agents/skills/galdr-ymirsystem/SKILL.md` |
| `tyr-check` | Tyr | The judge — validates tools/skills/docs against the 10 Galdr principles | `.agents/skills/tyr-check/SKILL.md` |
| `brokk-craft` | Brokk | The forger — generates new Galdr-compliant skills in TOON | (planned) `.agents/skills/brokk-craft/SKILL.md` |
| `galdr-compliance` | (legacy) | Superseded by `tyr-check` — removed | — |
| `galdr-crafter` | (legacy) | Superseded by `brokk-craft` — removed | — |

### 3.4 Figure reuse — one name, two roles

Some figures legitimately carry both a *platform subsystem* and a *runtime job* that serves it. This is intentional, not a collision; disambiguate by file path, never by inventing a second figure.

| Figure | Role A (subsystem) | Role B (runtime job) |
|---|---|---|
| **Yggdrasil** | worktree manager (`AGENTS.md:30`) | `bin/time/nornir-job-git-sync.sh` (keeps the tree in order) |
| **Sága** | session-start digest (`bin/time/saga-session-start.sh`) | 07:00 daily briefing (`bin/time/nornir-job-daily-briefing.sh`) |
| **Huginn** | Eindri research specialist (sage) | external observer job (`bin/time/nornir-job-observer.sh`) — the raven of observation |
| **Runes** | append-only audit ledger | the ledger head is titled `# YGGDRASIL Audit Trail` (see §5) |

**Vör vs Vörðr are distinct.** **Vör** (`bin/records/vor-crew-state.sh`) is awareness of a worker's current state. **Vörðr** (`.pi/extensions/lib/vordr-sessionstart-supervisor.mjs`) is the warden that supervises the digest child process. Never collapse them to one spelling.

## 4. Galdr aett prefixes (`SKILL.md:288-301`, `AGENTS.md:127`)

New Galdr-family skills inherit one of eight aett (family) prefixes, each bound to a domain. The prefix comes from the domain, not from taste.

| Aett prefix | Domain | Examples in use |
|---|---|---|
| `galdr-` | incantation / chant standards | `galdr`, `tyr-check` |
| `val-` | hall / health | `valhalla` |
| `skyr-` | giant / file scope | `skrymir` |
| `bifr-` | bridge / gateway | `bifrost` |
| `heimd-` | gate / guard | `heimdall` |
| `gjallar-` | horn / signal | `gjallarhorn` |
| `mimir-` | memory / wisdom | planned |
| `yggd-` | tree / worktree | planned |

Naming form: `<aett>-<verb|noun|adjective>`, e.g. `mimir-recall`, `yggd-branch`. The aett table lives in `SKILL.md:288-301` and `assets/build-tool-categories.md`; keep both in sync when an aett gains its first real skill.

## 5. Rules for naming a new component

1. **Find the role first.** State, in one sentence, what the component *does*. Choose the figure whose mythic role is that sentence.
2. **Check for reuse before inventing.** If the work belongs to an existing figure's domain, extend that figure's files rather than minting a name (e.g. a new Sýn guard is a `bin/syn-*.sh`, not a new god).
3. **Prefer a runtime file over a platform subsystem.** Runtime components are `bin/<figure>-<verb>.sh`, harness adapters are `.<harness>/…/<figure>-…`, and private state is `state/<id>.*`. Platform subsystems are reserved for the named systems in `AGENTS.md:20-46`.
4. **Keep the suffix honest.** `-lib.sh` = source-safe library; `-start.sh` / `-spawn.sh` / `-brief.sh` = entry points; `-job-*.sh` = a Nornir job; `-guard.sh` / `-check.sh` = a seatbelt.
5. **Add the figure to this file and to the plan table.** A name that is not in §3 does not exist. Add a row and, if it is a runtime component, add it to the corresponding plan table.
6. **Do not rename shipped paths to chase a better myth.** Renames break harness adapters and recorded `state/*.meta`. Append a note instead; a fresh name is a new file.
7. **Never let flavor name anything.** A spoken "the forge is hot" is fine; a file named `hot-forge.sh` is not.

## 6. Reject list

These terms must never name a Ymir subsystem, file, config key, environment variable, or documented component.

### 6.1 Imported terms (from the upstream distro and elsewhere)

| Rejected term | Why | Norse replacement |
|---|---|---|
| `captain` | Imported nautical operator title | **Allfather** |
| `first mate` / `firstmate` | Upstream project name; provenance only | **Brokk** (the primary) |
| `second mate` / `secondmate` | Upstream isolated-home concept | **eindri-home** (realm/home scope) |
| `crew` / `crewmate` | Imported worker terms | **Eindri** (worker), **Einherjar** (the spawn act) |
| `ship` / `shipping` (as subsystem names) | Nautical metaphor | **Smíðja** / **Mjollnir** as appropriate |
| `SSSF` / `sssf` | Upstream project name; provenance only | **Smíðja** (the smithy) |
| `treehouse`, `worktree pool` (as a subsystem) | Imported OSS engine name | **Yggdrasil** (Norse shell over treehouse) |
| `sandcastle` (as a subsystem) | Imported OSS engine name | **Utgard** (Norse shell over sandcastle) |
| `FM_HOME`, `FM_*`, `fm-*` | Upstream env/file prefix | **`BROKK_HOME`, `BROKK_*`, `<figure>-*`** |
| `calm` | Upstream presentation mode; deferred, not ported | (not named; presentation theming deferred) |
| `harness-adapters`, `bootstrap-diagnostics`, `supervision-protocols` (as skill names) | Upstream skill names | Galdr aett name or runtime file |
| `lavish`, `gh-axi`, `chrome-devtools-axi` (as Ymir names) | Upstream tooling names | reuse the OSS tool; do not rename into Ymir |
| `stow`, `backlog-handoff`, `fleet-sync` | Upstream skill names | Galdr aett name |
| `zellij`, `orca`, `cmux`, `codex-app` (as Ymir backend names) | Upstream spawn backends not ported | **tmux** / **herdr** only |

### 6.2 Collision and ambiguity names

| Rejected name | Why | Correct choice |
|---|---|---|
| `agent` | Generic; collides with Cursor's legacy alias and countless tools | detected structurally in `bin/fleet/hamr-harness.sh`, never named |
| `MainThread` | Runtime-internal Cursor marker, not a figure | never named |
| `Vordr` (unaccented, for Vör) | Collides with **Vörðr** (the warden) | `vor-crew-state.sh` = Vör; `vordr-*` = Vörðr |
| `Yggdrasil` for the audit ledger | Collides with the worktree manager | **Runes** (the ledger head string is legacy; see below) |
| `Huginn` for a new observer *and* the research specialist | Already dual-role | keep both; disambiguate by path |
| `syn` for the session digest | Collides with Sýn (the watcher) | **Sága** (`saga-*`) owns the digest; `syn-*` owns the watch |
| `saga` for a watcher | Inverse of the above | Sýn owns watch; Sága owns seeing/digest |
| `valhalla` for cron | Collides with the process supervisor | **Nornir** owns the schedule; Valhalla supervises processes |
| `ratatoskr` for the queue | Ratatoskr is the A2A bus; Redis is the queue engine | keep the split stated in `AGENTS.md:86` |
| `smidja` / `smidja` / `smidja` (as a Ymir subsystem name) | Imported upstream project name; provenance only | **Smíðja** (the workshop); its orchestrator is **Völundr** |
| `Smíðja` / `Smidjan` for the **platform** | The platform is the body | **Ymir** is the platform; **Smíðja** names only the smithy (the workshop inside it) |

### 6.3 Legacy strings — RESOLVED (2026-09-11)

All three legacy strings below were corrected in the same working session; the history is
kept only so the migration is traceable. New tooling must still not reproduce any of them.

- ~~`bin/records/runes-append.sh:101` seeds the ledger with `# YGGDRASIL Audit Trail`.~~ **Fixed:** now `# RUNES Audit Trail` (append-only history preserved).
- ~~`AGENTS.md:231-244` (`PI / FIRSTMATE INTEGRATION (W0031)`) uses imported terms.~~ **Fixed:** the section is now §PI PRIMARY BOOT using Hamr, Einherjar, Yggdrasil, and the `rodd` operational schema.
- ~~`.pi/extensions/README.md` says the other adapters are "not yet wired".~~ **Fixed:** the README now lists OpenCode, Claude Code, Codex, and Cursor as wired (Grok unimplemented).

## Maintaining this

- **Owner:** Brokk. **Source of truth:** `AGENTS.md:6` (mandate) and `docs/plans/29-brokk-distro-runtime.md:270-297` (runtime table).
- **Add a row** in §3 whenever a new component ships, with its real path. Add an aett row in §4 when an aett gains its first skill.
- **Add a reject row** in §6 the moment an imported or colliding name is encountered, before it can spread.
- **Audit periodically:** `grep -rniE 'captain|firstmate|crew|treehouse|sssf|fm-' --include='*.sh' --include='*.ts' --include='*.js' --include='*.json' --include='*.md' bin .pi .opencode config data .agents docs/plans | grep -v Brokk-to-norse` should return only provenance citations in `porting-upstream-to-norse.md` and the legacy strings listed in §6.3.
- **Never rewrite §3.2 paths without updating `brokk-distro-runtime.md`**, which cites the same files.

## 7. Later runtime & worker figures (2026-09-11)

```
runtime_figures[7]{figure,role,path}:
  "Ró","calm presentation (hides chrome; /ro)","`.pi/extensions/ro.ts` + `lib/ro-*.ts`, `state/ro` (env `YMIR_RO`)"
  "Skuld","supervision branch (routine wakes; /skuld-model)","`.pi/extensions/skuld-branch-supervision.ts` + `lib/skuld-branch-*.ts`, `config/skuld-branch-*`"
  "Valknut","repo-local loader (binds agents into each tool)","`bin/seat/valknut-load.sh`"
  "Mímir","Eindri planner (architecture, sequencing)","`.agents/agents/mimir-planner.md`"
  "Forseti","Eindri reviewer (QA, acceptance; changes nothing)","`.agents/agents/forseti-reviewer.md`"
  "Snotra","Eindri documenter (docs, changelogs)","`.agents/agents/snotra-documenter.md`"
  "Kvasir","Eindri scout (recon; changes nothing)","`.agents/agents/kvasir-scout.md`"
```

### 7.1 Binding and watch figures (lore §XVI)

```
runtime_figures[3]{figure,role,path}:
  "Gleipnir","Session lock — binds one session, one reins","bin/vault/gleipnir-lock-lib.sh, bin/agents/brokk-lease.sh"
  "Skuld","Branch outcome tracker — sees the future of every branch","bin/skuld/skuld-branch-outcome.sh, bin/skuld/skuld-branch-prompt.sh"
  "Valknut","Load mechanism — assembles agent config at boot","bin/seat/valknut-load.sh"
```

### 7.2 Diagnostics and brief figures (lore §XVII)

```
runtime_figures[2]{figure,role,path}:
  "Vor","Diagnostics — bootstrap + crew state","bin/records/vor-crew-state.sh, vor-diagnostics skill"
  "Erindi","The errand — task brief format","bin/agents/erindi-brief.sh"
```

### 7.3 Shape-changer and consent figures (lore §XVIII)

```
runtime_figures[2]{figure,role,path}:
  "Hamr","Shape-changer — harness adapter","bin/fleet/hamr-harness.sh, hamr skill"
  "Frigg","Consent gate — ask-user authority","frigg-consent skill"
```

### 7.4 Earth and decision-hold figures (lore §XIX)

```
runtime_figures[2]{figure,role,path}:
  "Jörð","Earth goddess — project registry","jord-projects skill"
  "Urðr","Allfather-hold lifecycle","the `urdh` skill (assets/decisions.md, assets/hold.md)"
```

### 7.5 Recovery and away-mode figures (lore §XX)

```
runtime_figures[2]{figure,role,path}:
  "Sýn","Stuck-worker recovery","syn-recovery skill, syn-turnend-guard.sh, syn-watch-arm.sh"
  "Hvíld","Away-mode — idle supervision","hvild-afk skill, saga-wake-drain.sh"
```

### 7.6 Update and relay figures (lore §XXI)

```
runtime_figures[2]{figure,role,path}:
  "Ymir","Self-update mechanism","the `ymir` skill (assets/update.md)"
  "Gjallarhorn-relay","Public relay — X/Discord","gjallarhorn-relay skill, gjallarhorn-notify.sh"
```

### 7.7 Nornir array figures (lore §XXII)

```
runtime_figures[2]{figure,role,path}:
  "Nornir","Process→event sources + quota dispatch","the `nornir` skill"
  "Nornir","Process→event sources + quota dispatch","the `nornir` skill"
```

### 7.8 Database and toolchain figures (lore §XXIV-XXV)

```
runtime_figures[2]{figure,role,path}:
  "Wyrd","Workspace RAG database","bin/records/wyrd-db.sh, bin/records/workspace-rag.sh"
  "Toolchain","Unified entry point for all Ymir operations","bin/gates/toolchain.sh, justfile"
```

### 7.9 Veil and gate figures (lore §XXVII)

```
runtime_figures[2]{figure,role,path}:
  "The Veil","Anti-hallucination gate — nothing passes without well evidence","kaia-veil gate"
  "Glitnir","Human review gate — every PR/merge/deploy needs approval","glitnir gate"
```

## 7. Organisation (Rule 01/03) — house, domain (Grein), Eindri

- **House = company** (WayOf). Never a field of knowledge.
- **Domain = Grein / Greinar** — the eight Labs are *domains*, not houses.
- **Eindri = specialists**; each names its domain and craft.
- In code: `DOMAINS` / `DomainId` / `DomainDef`; agents carry `domain`.
- Full law: `RULES/01-domains.md`, `RULES/02-agents.md`, `RULES/03-houses.md`.

### 7.3 Local-model operation (2026-09-12)

```
runtime_figures[1]{figure,role,path}:
  "Vog","local models on this machine — the scales: which engine, how to wire the runtime to it, and how to weigh it honestly","`.agents/skills/galdr-ymirsystem/assets/local-models.md`, `.agents/skills/galdr-ymirsystem/scripts/bench-one.sh`"
```

**Vog** is the scales. The capability that puts a local model on the balance and
reads its true weight — prefill, decode, peak device memory, and the context it
actually survives — rather than trusting a specification. It is named for the
*role*: an instrument, in the same pattern as Mjollnir (hammer), Gungnir
(spear), Gleipnir (chain), and Valknut (knot).

**Vog weighs, Hodd keeps.** Vog measures on the machine; the results are private
to that machine and go to the Hoard (`hodd/docs/vog/`, Rule 04). Vog is not a
figure of judgement (that is Týr, and Forseti reviews) and never names a model's
worth — only what it measurably does.

## 8. Reserved figures (claimed, not yet built)

A figure reserved here is spoken for: do not use it for other work. Add a row
the moment a reservation is made, and move the row into §3 or §7 when the
component ships.

```
reserved[1]{figure,role,path,claimed}:
  "Máni","the calendar — who counts the months: the Nornir schedule and the Hlidskjalf calendar view","bin/nornir-* calendar surface + apps/hlidskjalf calendar","2026-09-12"
```

**Máni** is reserved deliberately and must not be spent elsewhere. Máni is the
measurer of *time* — he counts the months and governs the course of the moon —
which is exactly the role of a calendar: the schedule that Nornir keeps and the
calendar the Allfather reads in Hlidskjalf. Do not use it for benchmarking or
for anything that merely reports a rate per second.
