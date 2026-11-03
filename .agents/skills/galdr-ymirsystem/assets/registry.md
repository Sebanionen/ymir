# Registry — skills, assets, tools, commands (loaded from AGENTS.md)

AGENTS.md loads this when a task needs the live inventories.

## Skills registry (`.agents/skills/`)

```
skills[3]{name,norse,purpose,path,status}:
  "galdr","Galdr","agent-CLI ergonomics + master builder/maintainer",".agents/skills/galdr-ymirsystem/SKILL.md","live"
  "tyr-check","Tyr","the judge — 10 principles + runtime gates",".agents/skills/tyr-check/SKILL.md","live"
  "brokk-craft","Brokk","the forger — generates Galdr-compliant skills in TOON","(planned) .agents/skills/brokk-craft/SKILL.md","planned"
```

The **canonical, complete** skill index is `.agents/skills/README.md` — read it for
the live set. The two removed legacy skills (`galdr-compliance`, `galdr-crafter`)
are superseded by `tyr-check` and the planned `brokk-craft`; their files are gone.

Loading: auto-load from `.agents/skills/` via `opencode.json` →
`skills.paths: [".agents/skills"]`. Use `skill galdr`, `skill tyr-check`.

## Galdr assets (`.agents/skills/galdr-ymirsystem/assets/`)

```
galdr_assets[6]{path,load_when}:
  "assets/README.md","the full asset routing index"
  "assets/principles.md","the 10 CLI design principles (full doctrine)"
  "assets/norse-naming.md","naming law + full component map"
  "assets/brokk-distro-runtime.md","the runtime spec (home, digest, lock, cron)"
  "assets/harness-integration/","per-harness adapters (opencode, pi, claude, cursor, codex)"
  "assets/runtime-compliance.md","runtime acceptance gates + runnable checklist"
```

Galdr scripts: `scripts/toon-check.py` (TOON validation) and
`scripts/compliance-check.sh` (all gates). Run the latter before claiming done.

## Assets inventory

```
assets[9]{asset,path,purpose}:
  "Eindri profiles",".agents/subagents/*.md","Sindri/Bragi/Huginn role profiles"
  "Build tool categories",".agents/skills/galdr-ymirsystem/assets/build-tool-categories.md","tool categories for synthesis"
  "TOON schemas",".agents/skills/galdr-ymirsystem/schemas/toon-schemas.md","schema types for validation"
  "Compliance requirements",".agents/skills/galdr-ymirsystem/assets/runtime-compliance.md","runtime + Utgard gates"
  "PI boot profile",".agents/skills/galdr-ymirsystem/assets/pi-boot/pi-profile.yml","PI harness profile"
  "PI herdr profile",".agents/skills/galdr-ymirsystem/assets/pi-boot/herdr-profile.toml","pane layout / Þjazi"
  "PI dispatch schema",".agents/skills/galdr-ymirsystem/assets/pi-boot/einherjar-spawn.schema.json","dispatch payload"
  "Templates",".agents/assets/templates/*","PRD, env, system-prompt boilerplate"
  "Tool manifest schema",".agents/assets/schemas/tool_manifest.json","tool manifest"
```

## Tools inventory (`.agents/tools/`)

```
tools[8]{tool,path,purpose,status}:
  "tasks-cli",".agents/tools/bin/tasks-cli","AXI task manager (list/view/create/close), TOON","live"
  "tasks-cli.ts",".agents/tools/tasks-cli.ts","TypeScript source","live"
  "yggdrasil.ts",".agents/tools/yggdrasil.ts","worktree CLI harness","planned"
  "hermes_runner.ts",".agents/tools/hermes_runner.ts","realm agent CLI orchestrator","planned"
  "herder.ts",".agents/tools/herder.ts","terminal multiplexer / pane state tracker","planned"
  "vector_db.ts",".agents/tools/vector_db.ts","vector indexing / RAG search","planned"
  "firebase.ts",".agents/tools/firebase.ts","backend provisioning","planned"
  "supabase.ts",".agents/tools/supabase.ts","DB / edge function setup","planned"
```

Usage: `python3 .agents/tools/bin/tasks-cli <command>`. All tools emit TOON.

## Fleet services (`tools/`, deployed by `bin/fleet/fleet-ensure.sh`)

The heart's offices materialize from `tools/` into `~/.fleet` and rise as user
units joined to `ymir.target` (the auto-boot law). The snotra operator commands
(`snotra-capture.sh`, `snotra-transcribe.sh`, `snotra-detect.sh`,
`snotra-mine.sh`, `snotra-ensure.sh`,
`runes-append.sh`) are copied to `~/.fleet` too, so any seat can run the ear
without a repo checkout on its PATH.

```
fleet[9]{service,source,unit,port,role}:
  "well-mcp","tools/well-mcp/server.ts","well-mcp.service","8317","heart + dev door"
  "ratatoskr","packages/a2a/ratatoskr/server.ts","ratatoskr.service","8301","heart"
  "mill-worker","tools/mill/worker.sh","mill-worker.service","—","heart"
  "embed","(llama-server)","embed.service","8500","heart/forge with the model"
  "cards","(cards-root)","cards.service","8318","all"
  "skills-mcp","packages/mcp/skills/server.mjs","skills-mcp.service","8319","heart + dev"
  "skuld","tools/tickets-mcp/server.mjs","skuld.service","8320","heart"
  "snotra","tools/snotra/server.mjs","snotra.service","8321","heart (read-only minutes)"
  "snotra-detect","systems/snotra/services/ear/snotra-detect.sh","snotra-detect.service","—","CAPABILITY: any seat with a microphone (the ear's watch; never the heart)"
```

## OpenCode commands

```
commands[8]{command,purpose}:
  "/create-plan","create detailed implementation plans iteratively"
  "/fixes-bump","bump version across project files"
  "/fixes-create","create fix note entry"
  "/implement-plan","implement approved plan phase-by-phase"
  "/rules","display/manage coding rules"
  "/standup","generate daily standup entries"
  "/ticket-create","interactive ticket creation"
  "/validate-plan","validate plan before implementation"
```

## Brokk commands — the Eindri wake bridge (control)

```
commands[5]{command,purpose}:
  "bin/agents/eindri-watch.sh","the bridge's door: arm/retire/list/reconcile a when-source per smith (Norns' loom)"
  "bin/agents/eindri-seen.sh","bridge condition: has the smith reported? (report file, or herdr left working)"
  "bin/agents/eindri-acclaim.sh","the push path: file the report/status, mark the ONE shared ledger (bin/agents/eindri-wake-lib.sh), append the durable wake queue + desktop note; the worker's own terminal act"
  "bin/agents/eindri-handoff.sh","the handoff failsafe: sweep undelivered reports/questions into the wake queue, idempotent on the shared ledger (run on re-arm and on the 06:45 cron row)"
  "systems/snotra/services/cron/hall-snapshot.sh","the planning feed: real system state -> public-safe livehall.json for the Óðrerir Hall"
```

## The marketing stack doors (provisionable — one stack, any computer)

`bin/desktop/ymir-marketing-stack.sh up|status|down|doors` stands Mautic + Postiz +
Activepieces (+ optionally Forgejo) on ANY computer — same OSS engines the
server runs, env-driven, ports virtualized, secrets in the home, never inline.
The Allfather's server stack (zerwizserver) and the public doors agents reach:

```
marketing_doors[6]{service,door,reach_note}:
  "Mautic (email automation)","mautic.zerwiz.org -> server 127.0.0.1:8001","list building + campaigns; agent-carved via the local provisioned stack when the public door is closed"
  "Postiz (social publishing)","postiz.zerwiz.org -> server 127.0.0.1:4007","schedule X/LinkedIn/insta; queue per site"
  "Activepieces (workflow)","activepieces.zerwiz.org -> server 127.0.0.1:8080","event->post flows; meetup booked -> thread scheduled"
  "Forgejo (git · issues · PRs)","forgejo.zerwiz.org -> server 127.0.0.1:3030","the local git forge: issues->PR loop lives here"
  "SearXNG (search)","searxng on the server","private search for research (Bragi)"
  "Grafana","grafana on the server :3003","fleet + stack observability"
```

An agent (Bragi for marketing, Sindri for git) provisions the stack locally for
any user with `bin/desktop/ymir-marketing-stack.sh`; the server stack is the Allfather's
live one. Public-door exposure on the server is tunnel-driven (cloudflared) —
mend the door layer on the server, not in the tree.

## Maintaining this

- **Owner:** Brokk. **Loaded by:** `AGENTS.md`. **Mirror:** `.agents/skills/galdr-ymirsystem/assets/registry.md`.

## The smithy's books (critical, and easy to miss)

`apps/smidja-factory/cookbooks/` (9) and `apps/smidja-factory/skills/` (9) are the specification for the
Smíðja: how a run is launched, what a roster is (`roster.yaml`, teams in `stacks:`), how a prompt is
written, how a chain is composed, and what an install needs. They sit **inside an app**, so no inventory
of `bin/` will ever surface them — read them before touching the smithy.
Law: `RULES/36-the-run-is-visible.md` · detail: `assets/smidja.md`.
## Inventory executable classification (2026-11-03)

`bin/gates/inventory.sh` derives executable status from Git index mode `100755`, not host `os.access(X_OK)`. It reads `git ls-files --stage -z` so whitespace in tracked paths is preserved. Directory walks use an explicit relative POSIX path sort key, avoiding Windows case-folded Path ordering. Filesystem permission changes must not alter the generated public register when the index is unchanged.

`tests/test_inventory_git_mode.py` runs the actual generator in a small Git repository, inverts working-tree executable bits without changing index modes, and checks complete output stability, data/tool classification, whitespace paths and case-sensitive row ordering. Run it on Windows and Linux when changing inventory classification. Regenerate the full registers only after all intended source changes are staged.

The generator writes explicit UTF-8 with LF newlines on every host. The real-generator regression asserts LF output on Windows and Linux. Previously generated register data was retained exactly, with Git text normalization changing CRLF to LF only.
