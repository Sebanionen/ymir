# Hlidskjalf UI — working guide

Ymir's own surface (one of the three things Ymir owns: the UI, the runtime, A2A).
Load this when touching `apps/hlidskjalf`. The design contract is `docs/design.md`;
the tokens are the single source of truth.

## Surfaces

```
surfaces[6]{part,where,note}:
  "SPA",":3888 (vite) / built dist served by the gate","React app; gates: Fleet, Chat, Runes, …"
  "gate API",":3889 (bun apps/hlidskjalf/server/index.ts)","auth + /api/* + serves dist/; static types + caching"
  "login","in-app modal → /api/login → session cookie","user/pass from .env.local HLIDSKJALF_AUTH; Heimdall (oauth2-proxy) is the target"
  "register","in-app modal → /api/register → spends an invite code","bin/engine/ymir-invite.sh mints a limited-use code when nothing is live; argon2id account in state/accounts.json (0600, gitignored)"
  "desktop","apps/hlidskjalf/electron/main.cjs + scripts/electron.sh","single instance + one window (never stack); see the ymir skill assets/desktop.md"
  "tunnel","gjallarhorn → your hostname → :3889","outbound only; `bin/forge/gjallarhorn-tunnel.sh`"
```

Quick rules:

- **One login, one window** — no GitHub hop before Heimdall; auth stays in-window.
- **Gate API protects `/api/*`** and serves the SPA; 401 → `ymir:unauthorized`.
- **No secrets inline** — `HLIDSKJALF_AUTH` from `.env.local`.
- **Electron:** single-instance lock; `openWindow` reuses the live window.
- Raise/repair: `scripts/start.sh`; if the window is gone but ports answer, the
  shell must be restarted (backend ≠ window).

## Where the registries live (2026-09-30, plan 62)

The example registries moved with the rename: **`workspace/` → `registry/`**.

```
registry/projects.yaml.example    # one git{} block per project (host/owner/repo/…/auth)
registry/workspaces.yaml.example
```

The gate API reads `join(ROOT, 'registry/workspaces.yaml')` and `bin/agents/project-git.sh` falls back to
`$ROOT/registry/projects.yaml`; both were rewritten in the same change that moved the templates.

> **The VALUE rename shipped 2026-10-01 (plan 62 item 6).** A project row's `workspace:` was never a
> workspace — it named the **realm** — so the key is now `realm:` in `registry/projects.yaml.example`,
> in `bin/engine/ymir-install.sh`'s seeded registry, and in every row of the operator's home registry (by his
> hand, not by a script). The readers resolve **both** keys through `bin/skuld/registry-lib.sh`: `realm`
> first, `workspace` as a deprecated alias that is **named on stderr** every time it is used
> (`deprecated-registry-key: row "<id>" carries \`workspace:\` …`). `bin/engine/ymir-validate.sh` gained the
> `registry` check: PASS when every row names its realm, WARN naming each row still on the old key —
> never FAIL, because a registry rewrite must not break a reader silently. `--field workspace` on
> `bin/agents/project-git.sh` likewise resolves and says it is `realm`. Never resolve the realm key outside
> `bin/skuld/registry-lib.sh`.

## Location & stack

- App: `apps/hlidskjalf` — **React 19 + Vite + TypeScript**, state via **Zustand**.
- **The app lives in THIS repo** at `apps/hlidskjalf` — it has hundreds of tracked
  files in the monorepo, its origin is the ymir repo, and the home registry
  points it at `repo: apps/hlidskjalf` with posture `direct-PR`. (An earlier
  version of this guide claimed it lived in its own repo (`zerwiz/hlidskjalf`)
  that the monorepo never tracked; that is **stale** and was corrected
  2026-09-30 in the same change that added the Mánagandr gate. `bin/engine/ymir-install.sh`'s
  `apps` step still materializes a checkout at install, but a working checkout is
  the tree.)
- Gate API: `apps/hlidskjalf/server/index.ts` — **Bun + `bun:sqlite`**, read-only,
  bound to the runtime and the smithy trace; Vite proxies `/api` → `:3889`.
- Raise everything with the scripts (do not hand-start each process):

```bash
scripts/start.sh    # SPA :3888 · gate API :3889 · Smíðja visualizer :8437 · Nornir cron · Bifrost bridge
scripts/stop.sh     # lower them all
```

- Verify: `npm run typecheck` (`tsc --noEmit`) and `npm run build` must both be green.
- **Typed surfaces (plan 58 Phase 6):** the fleet card's `interface` is the shared
  **A2A agent-card contract** at `packages/contracts/src/index.ts` —
  `apps/hlidskjalf/src/types.ts` imports `AgentInterface`, and the gate builds the
  same shape in `server/index.ts`; the A2A node
  (`packages/a2a/ratatoskr/server.ts`) builds the card it serves through the same
  contract. Change the contract, never a copy.
- Headless check: render with Playwright/Chrome and assert **0 console errors**.

## Tokens — never hardcode colour

- Canonical tokens: `midgard/design-system/tokens.css`, imported once in
  `src/main.tsx` (Vite `server.fs.allow` grants access outside the app root).
- Style with CSS variables only (`var(--ymir-cyan-1)`, `var(--ymir-bg-2)`, …).
  **Never** write a raw hex in a component or a stylesheet — add a token instead.
- The active **accent** is driven by `--realm-tint` / `--realm-tint-2` /
  `--realm-tint-dim` on `:root`, set per realm via `data-realm` and overridable by
  the user (`state/store.ts` → `applyAccent`). Tenant overrides live in
  `tenantColors`.
- **Fonts** are the cloth's three faces, loaded from Google Fonts in `index.html`:
  Cormorant (display/runes), Newsreader (body), IBM Plex Mono (data), with Noto
  Sans Runic appended to every stack so a rune glyph falls through to the rune
  family.

### The cloth (2026-09-13)

The token *values* are the **carved cloth of the halls** — the landing page's own
palette (`CodeP/ymir-homepage/src/lore.html` `:root`; the hall carries its own
locked copy at `apps/odrerir/src/styles/cloth.css`), so Hlidskjalf, Smíðja and
Sessrúmnir are one look (`docs/design.md` §0/§4.2 is the contract):

```
canvas   bg-0 #0e0c09 · bg-1 #151209 · bg-2 #1a1610 · bg-3 #221d14   (stone)
accent   cyan-1 #c9973f bronze · cyan-2 #7d5f2a bronze-deep
         violet-1 #96a0a8 steel · violet-2 #5f686e steel-dim
lines    steel-1 #2b241a (line) · steel-2 #7d5f2a (brass rule) · chisel #c9973f
text     text-0 #cfc3a9 bone · text-1 rgba(207,195,169,.82) · text-2 #9a8f75 · text-3 #6b6250
state    ok #96a0a8 steel · warn #c9973f · danger #c2584a blood-lit · info #9a8f75
bevel    inset 0 0 0 1px rgba(201,151,79,.12)
```

Rules that hold it honest:

- **The cloth is the default, not a cage** — a user accent/background choice wins
  (`AccentPicker`), and the eight **house/domain seals keep their heraldry**
  (`DOMAINS`), exactly as the landing page keeps its house seals. Chrome is the
  cloth; heraldry is not chrome.
- The **workspace tints** are cloth too: `work` = bronze `#c9973f`, `personal` =
  steel `#96a0a8` (`apps/hlidskjalf/src/data/realms.ts` → `WORKSPACES`, mirrored by the
  `data-realm` fallbacks in `styles/global.css`).
- The **Emblem** (`components/Emblem.tsx`, `midgard/design-system/ymir-mark.svg`)
  is brand, not cloth — it keeps its own colours on the stone.
- The login's GitHub button is a bone plate with a dark rune (the old white/navy
  literal is gone), and the `HallsChooser` cards read real tokens (they used to
  name two tokens that never existed, `--ymir-line`/`--ymir-panel`).
- Role-coloured literals in the stylesheets are now `color-mix(… var(--token) …)`,
  so a token change re-themes them.
- Geometry did not move: radius, spacing and the shell are unchanged by the cloth
  (the carved-slate squaring is still an open question).

## The shell (structural, do not redesign)

- `.shell` grid: `236px rail | 1fr`; rows `56px topbar · stage · stream`
  (the stream height is draggable, persisted in `streamHeight`).
- The **Fleet graph** (`gates/Fleet.tsx`) lays the roster on a 100×100 canvas:
  Brokk as the hub, everyone else in a square-ish grid fan (`cols =
  ceil(sqrt(n))`, pitch ≥ one ring + label) so 20 agents never collide; rings
  carry the house glyph from `DOMAINS[agent.domain]` with a `ymirlabs`
  fallback, and the live cards come from `bin/desktop/hlidskjalf-agents.sh` — which
  reads each figure's `domain:` frontmatter (never a hardcoded `ymirlabs` for
  everyone).
- `.rail` (brand · gates · tenants · status), `.topbar` (realm chip · search ·
  accent · density · trace index · account), `main.stage` (the gate), `.stream`
  (Ratatoskr + Runes, pausable).
- Gates are **deep-linkable** and registered in `apps/hlidskjalf/src/data/realms.ts` (`GATES`) and
  routed in `src/app/Shell.tsx`:
  `#/fleet` · `#/tasks` · `#/well` · `#/runes` · `#/reviews` · `#/processes` ·
  `#/files` · `#/chat` · `#/forge` · `#/profile` · `#/sessions` · `#/trace` ·
  `#/decisions` · `#/stats` · `#/cron` · `#/runtime` · `#/managandr`.

## Rules of the surface

1. **Color-only states are forbidden** — every status carries glyph + colour + text
   (`StatusChip`, `TaskChip`).
2. **Runecoded, not emoji** — use the rune family (runic glyphs fall through to
   Noto Sans Runic inside the Cormorant/mono stacks); never an emoji as an icon.
3. **Every button must act** — no dead controls. Wire to a state change, a modal, or
   a toast.
4. **Motion explains** — 120–240ms, no bounce; honour `prefers-reduced-motion`.
5. **Metrics are IBM Plex Mono, tabular** (`.mono`, `.tabular`).
6. **Metadata per page** — a gate declares its title/description/OG tags in
   `src/data/metadata.ts`; `Shell` applies them on gate/realm change.

## Interaction patterns (modal + toast)

### The Files tree folds, and its folders look like folders (2026-09-24)

`src/gates/Files.tsx` renders the realm tree. The old tree was always fully
flattened: folders had no open/close at all (every click merely selected) and
used a text triangle `▸` as the dir glyph. Now:

- **Fold fold**: each directory except the root starts collapsed; clicking a
dir toggles it (`aria-expanded` reflects the state; the chevron shows ▸/▾).
The tree renders through `visibleFlat`, which walks children only while the
parent is open.
- **Folder icons**: dirs render a folder-shaped inline SVG (currentColor, the
realm tint owns the hue) beside the chevron; files render a document glyph.
- **The selected file stays visible**: on mount, the ancestor chain of the
initially selected file is opened (the tree starts folded, so without this the
selection would hide under closed parents).

- `src/state/ui.ts` exposes `useUI()` → `toast({kind,title,body})` and
  `openModal({variant,title,body,fields,content,onSubmit})`.
- `<Overlay/>` (mounted in `App`) renders the modal + toast host. Variants:
  `confirm`, `form` (fields), `info` (content block, e.g. a diff).
- Any consequential action **must** open a confirm/form modal, mutate the store,
  emit a rune (`pushStream`), and toast the outcome. Reference: `components/PRCard.tsx`
  (Seal / Request changes / View diff).
- Buttons get press feedback from `styles/overlays.css` (`translateY(1px) scale(.97)`).

## State & live data

- `src/state/store.ts` — session, realm, gate, accent, tenant colours, company,
  and data: agents, tasks, runes, stream, recall, processes, reviews, files, chat,
  skills, **smidja** (sessions/stats/decisions/db), **mimir**.
- **Live mode** loads the gate API (`loadLive`); every call degrades on its own and
  has a 10s timeout (`services/api.ts`). Smíðja loads on a **separate track**
  (`refreshSmidja`) so a slow endpoint (e.g. `/api/reviews`) cannot hold its gates
  hostage. `App` polls `refreshSmidja` every 5s.
- Realm switching is **granted**: `setRealm` refuses a realm the session has no
  grant. Tenant boundaries are sacred — never render another tenant's data.
- Persist user prefs to `localStorage` (`ymir.accent`, `ymir.tenant-colors`,
  `ymir.company.*`, `ymir.stream-height`).

## The gate API surface (`/api`, read-only)

`/api/health · /api/me · /api/workspace · /api/agents · /api/tasks · /api/runes ·
/api/well · /api/processes · /api/reviews · /api/files · /api/runtime · /api/cron ·
/api/cron/seats · /api/calendar ·
/api/loaders · /api/checks · /api/settings · /api/stream · /api/mimir …` plus the
smithy trace: `/api/smidja/{health,sessions,sessions/:id,decisions,stats}` and
chat: `/api/chat/history`, `POST /api/chat`.

### The Cron gate — local and server schedules (2026-09-24, plan 54)

The Nornir gate (`src/gates/Cron.tsx`) shows BOTH faces: the LOCAL seat's loop and
the SERVER seats' (whynot · zerwizserver). Two read-only routes feed it:

- **`/api/cron`** — the schedule the LOOP reads, never the repo's template. The
  board once read `<ROOT>/.agents/config`, which ships only `cron.yaml.example`,
  so it painted "0 jobs" while the loop ran the home's real schedule. It now
  resolves as the loop does: `$YMIR_HOME/config/cron.yaml` → repo `cron.yaml` →
  the example (flagged). The answer carries `source`, each job's `role` gate and
  whether it `applies` to this seat's roles (from `bin/fleet/topology.sh`), the fired
  markers (`state/.cron-fired`), and — when stopped — a `why` read from
  `state/cron.log` (e.g. `no live session lock`).
- **`/api/cron/seats`** — one ssh round-trip per server seat (BatchMode,
  `ConnectTimeout=3`, host aliases `whynot` and `server` from `~/.ssh/config`),
  returning reachable/running/pid/roles plus how many of the schedule's jobs that
  seat's roles run. Read on demand, machine-local — never carried through the
  synced home (plan 51 rule 1). The seat list defaults to whynot + zerwizserver
  and is overridable with `YMIR_CRON_SERVER_SEATS="seat:sshhost …"`.

Never render a bare zero: an absent schedule names the missing path, a stopped
loop names its reason, an unreachable seat names the ssh failure.

### The Mánagandr gate — the read calendar (2026-09-30, plan 60)

The seventeenth gate (`#/managandr`, id `managandr`, label `Mánagandr`, glyph
`ᛅ`) is a **read** month reckoning — no create, edit, delete, invite or move
exists in it, because the verb is ABSENT, not disabled. It is a month grid:
week day-columns, an hour gutter in **the machine's timezone** (`Date` local
methods — never a hardcoded offset or zone), a now line on today's column, `‹ ›`
month navigation and a `⟨ Today ⟩` return, and four lane toggles.

- **`/api/calendar`** (new, read-only, under the same `/api/*` auth — 401
  without a session) reads the reader's rolling cache
  (`$YMIR_HOME/hodd/state/calendar/cache.json`, written by `tools/calendar/reader.mjs`;
  `MANAGANDR_CACHE` overrides the path, `MANAGANDR_CALENDAR_TTL_SECONDS` the
  freshness window) and answers exactly
  `{ as_of, state: "ok"|"unknown"|"absent", events: Event[] }` with
  `Event = { id, title, start, end|null, allDay, cancelled, calendarId }`
  (plus `attendees` when the cache carries it). **A missing cache and an empty
  calendar never answer the same**: `absent` names Phase 0 (no consent), `unknown`
  names an unprovable freshness, `ok` is fresh — and a fresh cache with no events
  in the *visible* month says so rather than drawing a blank grid.
- **The lanes compose from what the house already serves** — no second data path:
  reckoning → `/api/calendar`; Nornir → `/api/cron` + `/api/cron/seats` (the
  collision hairline: a marker on the hour a job lands inside a meeting — hollow
  planned, filled ran, blood missed; a job's run-state is provable only for the
  seat that runs it, so every other firing stays planned, never a false missed);
  Smíðja → `/api/smidja/sessions` + each session's phases (a thin rail per run, a
  block per phase, a blood edge on a refused gate); well → `/api/well` (density,
  one tick per episode, brightness by `score`) with the supersede days from
  `/api/mimir/health.superseded_dates` (timestamps only — never a fact's text).
- **Wards:** no payload, no episode `content`, no event location/attendees as
  free text is drawn or cached — counts, spans, statuses, tags, salience, costs
  and verdicts only; colours are `var(--ymir-*)` tokens, never a raw hex. The
  calendar cache lives in the hoard state; the app reads it and never writes.
- Verified: `npm run typecheck` and `npm run build` green; a headless Chromium
  run of `#/managandr` (desktop seat) renders 0 console errors, with the real
  cache showing its events, an all-day chip, the collision hairlines and the read
  modal (title · span · attendees · source id · Open in Google Calendar).

`POST /api/chat` resolves the chosen model against the operator's Pi catalog and
tries **every** engine that advertises it (LM Studio `:1234`, the llama.cpp
router `:8080`, Bifrost `:4603`), never only the first — a dead engine falls
through to a live one. Recall reads `.agents/memory/well/episodes.jsonl`
directly, so restoring that file revives the chat's memory without a restart.

### The EmberBackground hearth (the shared fire)

The animated glow behind the shell, the login, and Sessrúmnir's chat comes from
**one** hearth, not four copies: `midgard/design-system/ember.js` (`startEmbers`),
with Sessrúmnir's `ember-background.tsx` as its React port. Both draw the same
embers + haze, respect reduced-motion, and — since the Sep 17 mend — re-seed
via **ResizeObserver on the container**, not just `window.resize`: a split pane
or toggled sidebar changes the chat column's size without a window resize, and a
canvas that sized itself once at a stale dimension never shows the fire. The
shared module watches the host; the port watches its parent; re-seeding fires
only when the measured size actually changed (never per-frame).

**The hearth warms from the floor (2026-09-23).** The haze pools — the soft glow
that reads as the fire — were seeded in a band a fraction down from the top
(`y: H * 0.3 + rand * H * 0.7`). On the landing's short hero that read as "the
whole hero"; in a tall chat column it put the glow's upper edge a third down, so
the hearth appeared to start a third up while the ember dots rose from the
bottom. The seed is now anchored to the bottom edge —
`y: H - rand * min(H * 0.28, 240)` — in every copy (`midgard/design-system/ember.js`,
Sessrúmnir's `ember-background.tsx` / `EmberBackground.tsx` / `assets/ember.js`,
and the Óðrerir, Hlidskjalf and Smíðja visualizer copies), so the one fire rises
from the floor everywhere.

### The gate API reads cheaply (added 2026-09-16)

The gate reads append-only ledgers (Runes, the well's `episodes.jsonl`, masterplan
orders) and probes live runtime scripts on every request. Both grow without bound,
so the hot readers are memoised and the probes now run off the event loop:

- `runAsync()` — read-only subprocess probes via `Bun.spawn` (was `spawnSync`,
  which could block the single Bun event loop for up to 12s); results cached ~3s
  and concurrent callers share one in-flight spawn. Sync `run()` stays for
  **mutating** actions only (`setupRun`, `workspaceProvision`).
- `memo()` — `orders`, `runes`, `smidjaStats`, `chatRecall` are cached (2–3s), so a
  request never re-parses the whole ledger or well.

Measured: `/api/checks` 442ms → 4ms warm; `/api/runtime` 312ms → 5ms warm;
20 parallel `/api/runes` in 8ms.

**Ports are environment-driven.** The SPA (Vite) and the gate API read
`HLIDSKJALF_PORT` (default `3888`) and `HLIDSKJALF_API_PORT` (default `3889`);
`scripts/start.sh` passes the API port to the server as `PORT`, and the visualizer
uses `SMIDJA_VIZ_API_PORT`. A deployment should use 5-digit ports (the Quadlet/
Compose examples publish `38888`/`38889`/`54370`) to avoid colliding with other
services on a shared host; the defaults are unchanged for bare local dev. The SPA
bind host is `HLIDSKJALF_HOST` (default `127.0.0.1`); inside a container set it to
`0.0.0.0` so the published port reaches it, and pin the host-side publish to
`127.0.0.1` so the surface stays private.

## Smíðja in the UI

The smithy's trace (its own `smidja/smidja_data/smidja.db`) is rendered by four gates:

| Gate | Route | Reads |
|---|---|---|
| Sessions | `#/sessions` | every run, status, tokens/cost — **Open visualizer** + **Refresh** |
| Trace | `#/trace` | the selected run: phase lanes, events, agent sessions |
| Decisions | `#/decisions` | failures clustered by diagnosis/model |
| Stats | `#/stats` | token/cost breakdown, cache, providers |

**Open visualizer** opens `VISUALIZER_URL` (`src/data/metadata.ts`, default
`http://127.0.0.1:8437`) — Smíðja's own Vue trace UI, served by the smithy's Bun
API on the same port (`scripts/start.sh` raises it). Details: `assets/smidja.md`,
`docs/lore.md` §XIII.

## Agents, skills & mythological naming

- The Forge gate (`src/gates/Forge.tsx`) creates/edits **Eindri** and **skills**,
  and reads/edits the smithy's prompts. The skill list shows each skill's own
  text: the name + aett rune on the head row, and the description line
  underneath (`forge-item-desc`, dimmed until hover) — the description comes
  from the live `/api/skills` index, truncated to 240 chars by the gate API.
- Naming law: `src/data/mythology.ts` maps a craft/capability → the Norse figure
  whose myth matches it (smith→Sindri, skald→Bragi, sage→Huginn, judge→Tyr,
  forger→Brokk …). Skills take an **aett** prefix.
- New skills are validated in Utgard before production (Gungnir, W0007).

## Identity

- Mark: `midgard/design-system/ymir-mark.svg` (served `public/ymir-mark.svg`), used
  for login/rail logo and favicon. OG image: `public/og.png` (1200×630), source
  `public/og.svg`. Rebuild the PNG with headless Chrome if the SVG changes.

## The desktop apps (Electron)

`Hlidskjalf` and `Smíðja` each run as their own Electron app (`electron/main.cjs`,
launched by `scripts/electron.sh start --both`).

**Window placement.** The apps open on a **non-primary** display when one is
attached (the Allfather keeps the dashboards beside his work) and on the primary
otherwise. All geometry is in **logical** units — Electron's `screen` API returns
physical ÷ scale, and Omarchy commonly runs a fractional scale (e.g. a 1920×1200
panel at 1.5 is a 1280×800 logical desktop), so a 1440-wide default is clamped to
the work area rather than overflowing it. `YMIR_DESKTOP_DISPLAY` overrides the
choice: `other` (default) · `primary` · an index.

**Identity.** Never track an Electron app by the pid returned from
`.bin/electron` — that is a node shim which *spawns* the real binary, so the pid
is wrong and a second launch stacks on the first. Identify it by its own command
line (the per-view `--user-data-dir` is stable), which is what `electron.sh` does.

**One class per app, and the install proves it (2026-09-24).** Each surface
presents its own window class — `ymir-hlidskjalf` · `ymir-smidja` ·
`ymir-odrerir` · `ymir-sessrumnir` — decided once in `app_class`
(`bin/desktop/app-lib.sh`), set by the Electron mains (`app.setName(APP_SLUG)` +
`appendSwitch('class', APP_SLUG)`). The `.desktop` `StartupWMClass`, the
generated Hyprland rule, and the launchers must all name the same string; they
once did not (`CLASS_sessrumnir="sessrumnir"` vs the app's `ymir-sessrumnir`,
which made every Ymir key seem to open one app). The desktop step of
`bin/engine/ymir-install.sh` runs `bin/desktop/desktop-verify.sh` before any window is claimed
and after the raise (`--live`), so a misrouted or unopenable surface is a loud
FAIL, never green.

**GUI.** On a small-VRAM iGPU the Wayland `--type=gpu-process` can die with
`amdgpu: Not enough memory for command submission` (SIGSEGV, not an OOM). The
effective policy is one decision in `bin/host/graphics-lib.sh`: a shared-memory
integrated device beside a discrete one (a hybrid — i915 exposes no
`mem_info_vram_total`, so Intel is classified by presence, GTT read where amdgpu
exposes it) defaults the shells to software rendering. `YMIR_DESKTOP_DISABLE_GPU`
remains the override: `1` forces software, `0` forces the GPU path. The sense
snapshots record the policy (`bin/host/omarchy-sense.sh observe`, `gpu_policy`) so the
next decision is evidence-based.

## The live tail (Snotra) — one chip, three routes

`systems/snotra/services/ear/snotra-live.sh` transcribes this machine as you speak and writes the
words into a document under `$YMIR_HOME/hodd/life/meetings/`. **The UI is a front for
that script and never a second pipeline**: it calls the script and reports what the
script says. No transcription, slice timing or engine discovery is re-implemented in
`apps/hlidskjalf/`.

```
live[4]{part,where,note}:
  "control","src/components/SnotraLive.tsx, in src/app/Topbar.tsx beside HallsSwitcher","one chip; a form modal for the name; the readout panel below it"
  "routes","server/index.ts","GET /api/snotra/live · POST …/start · POST …/stop"
  "client","src/services/api.ts","gateApi.liveStatus / liveStart / liveStop"
  "styles","src/styles/shell.css","`.snotra-live*`, tokens only"
```

**The fact that decides the design: `stop` is SLOW.** It joins every slice into one WAV,
re-transcribes the recording, asks the rail for a summary, writes the minutes and
carves a Rune — *minutes* on a one-hour meeting. So `POST …/stop` **spawns the script
detached and answers `{closing:true}` at once**; the surface polls until the script
reports itself stopped. A browser that waits minutes on that POST times out and looks
broken while the work is fine.

- **`closing` outranks the script's own `stopped`.** The script silences ffmpeg in its
  first seconds, so `status` alone would say "stopped" while the minutes are still
  being written. The gate holds a `liveClosing` latch (cleared when the detached child
  exits) and says `closing` — *"closing the book…"* in the surface.
- **The latch also refuses a second `start`** while a drain is in flight: a race the
  script's own probe cannot see, because the drain is the gate's detached child.
- **One ear at a time.** `start` returns the script's refusal **verbatim** (HTTP 409),
  including which ear is busy. Never surface a generic error the operator cannot act on.
- `start` is bounded (`timeout 20`) and may block — it returns once the capture is
  alive. `stop` may NOT.
- **Poll only while listening or closing** (3 s). Idle never polls: a readout that
  polls forever is a readout that never sleeps.
- **No tail running is a state to say**, never an empty panel drawn as truth. Every
  status carries glyph + colour + text; the glyphs are runes (`ᛟ` listening, `ᛪ`
  idle/stop, `ᛃ` closing), never emoji.
- **Transcript content is private.** The document stays in the hoard; only these three
  authenticated routes read it, for the operator. Never write transcript text into the
  repo, a fixture, a log or a PR body.

No new GATE was registered for this — a topbar control plus a panel is the surface the
ask needed, and a gate is a bigger surface than "simple" is worth. Should a gate ever
be added, it must be registered in `GATES` (`apps/hlidskjalf/src/data/realms.ts`), routed in
`src/app/Shell.tsx` and declared in `GATE_META` (`src/data/metadata.ts`).

## Verification

```bash
cd apps/hlidskjalf
npm run typecheck        # tsc --noEmit
npm run build            # must be green
# headless: render the gate and assert 0 console errors (Playwright/Chrome)
```

## Maintaining this

- **Owner:** Brokk. **Router:** `.agents/skills/galdr-ymirsystem/SKILL.md`.
- **Mirror:** `.agents/skills/tyr-check/assets/hlidskjalf-ui.md`.
- When the shell, tokens, gates, or the gate API change, update this asset and
  `docs/design.md` together.

### The agent path the Fleet gate reads (2026-09-17)

`server/index.ts` decides whether a figure is *registered* by testing for its
profile in the OpenCode agent directory. That directory is **`.opencode/agents/`
— PLURAL**, which is what OpenCode actually loads. The singular
`.opencode/agent/` was never read by the harness, so twenty correct symlinks sat
in a directory no loader opened and the gate reported figures unregistered while
the tree held them all. Any code that resolves an agent profile must use the
plural path; the loader (`bin/seat/valknut-load.sh`) migrates a legacy singular dir
forward and binds the plural one.

## Domains, not houses (Rule 01/03)

The eight Labs are **domains (Greinar)** — the knowledge axes — not houses. A
**house is a company** (WayOf). In the UI the eight render as an agent's
**domain** (`agent.domain` via the `DOMAINS` map in `apps/hlidskjalf/src/data/realms.ts`); the
Forge picker is labelled **Domain**. `svartalfaheim/<company>/companies/` holds
the house card(s); the eight domain cards live under `.../domains/`.

### The GPU-process crash on a shared-memory iGPU (fixed 2026-09-12)

Symptom: both dashboards appear and work, while `coredumpctl` fills with SIGSEGV
cores from `electron --type=gpu-process`, and the kernel logs `amdgpu … Not enough
memory for command submission` immediately before each one. The window survives
because only the **GPU process** dies; Electron retries it, then falls back.

Cause: an iGPU has a small VRAM carve-out and backs the rest with system RAM
(GTT). A local model served on that same iGPU can hold several GiB of GTT, after
which the driver fails the desktop's command submissions. Electron's error path
dereferences NULL — a segfault at a constant offset, not memory corruption.

`scripts/electron.sh` now decides for itself: `igpu_vram_small()` reads
`/sys/class/drm/card*/device/mem_info_vram_total` and switches the dashboards to
software rendering when the carve-out is under `YMIR_IGPU_VRAM_SMALL_MIB`
(default 2048). `YMIR_DESKTOP_DISABLE_GPU=1` forces software, `=0` forces the GPU
path. Verified: with the fix the amdgpu submission errors stop and the
gpu-process runs SwiftShader instead of the hardware path.

If the crash returns, check GTT before anything else — `mem_info_gtt_used` on the
render device, next to whatever is serving a model on that GPU.

### The login surface carries no operator name

The in-app login (the gate shows it; there is no browser prompt) renders its
fields from the server template in `apps/hlidskjalf/server/index.ts`. Neither the
placeholder nor any default may name the operator: the field says `username`, and
the password comes from `HLIDSKJALF_AUTH` in `.env.local`, never inline. A
hardcoded name here is both a leak into the public tree and wrong for any other
operator — `bin/gates/guards/public-guard.sh` exists to catch exactly that class of mistake.

**The gate must actually receive it.** `scripts/start.sh` loads `.env.local`
(mode `0600`, gitignored) into the environment before raising the gate, because
the bun process reads `process.env.HLIDSKJALF_AUTH` and nothing else was loading
it — so a credential set by `bin/engine/ymir-setup-auth.sh` never took effect, and an
empty `GATE_AUTH` makes the gate treat every request as authenticated. After
setting a credential, restart the gate: `scripts/stop.sh; scripts/start.sh`.

### One login, and it is the one with the lore (2026-09-12)

There used to be **two** ways in, and the second was a mistake:

| | what it was | fate |
|---|---|---|
| `components/LoginModal.tsx` | the gate's login, beside the saga panel | **kept** — the only login |
| `app/Login.tsx` | a mock identity picker (`MOCK_IDENTITIES`), "Mock · Heimdall W0028 pending", demo mode | **deleted** |

The mock was wrong in a way that mattered: `App` rendered it as the fallback
whenever the store had no session, so a *correct* sign-in could land on a screen
offering a hardcoded identity — the operator's own name and email among them. The
demo scaffolding went with it (`demo` flag, `setApiDemo`, `data/mock.ts`,
`enterDemo`/`signIn`, the fake chat reply that claimed the well was seeded), and
with it every branch that could invent data in a live session.

What replaced it:

- **One session shaper.** `services/auth.ts` exports `sessionFor(login)` — the
  gate decides *who*, the UI only shapes what it renders. `App` calls
  `gateApi.session()` at boot and establishes the session from the login the gate
  reports; `establishSession(login)` replaced `signIn`/`enterDemo` in the store.
- **A GitHub door on the same gate.** `LoginModal` carries *Continue with GitHub*
  → `GET /api/auth/github`, which returns the authorize URL when
  `GITHUB_CLIENT_ID`/`GITHUB_CLIENT_SECRET` are set, and the exact reason when
  they are not. The callback (`/api/auth/github/callback`) exchanges the code,
  reads `/user`, and then **requires an account for that login** — accounts come
  from an invite, so GitHub never becomes an open door.
- **A 401 still re-locks.** `noteUnauthorized` is the only thing the demo switch
  was suppressing, and it survives without it.

Verified: `tsc --noEmit` and `npm run build` green, and the served SPA renders the
lore login with the invite affordance and no baked-in identity.

### Accounts and invites — how someone else gets in (added 2026-09-12)

One operator owns an instance. `HLIDSKJALF_AUTH` is that operator. Everyone else
enters through an **invite code**: registration is closed unless a live code is
presented, and a code carries its own ceiling, so a shared link cannot quietly
become an open door.

```
POST /api/register {username,password,invite}   → 201 + session   (403 when refused)
POST /api/login    {username,password}          → 200 + session   (operator OR account)
GET  /api/session                               → {authed,login,registration}
GET  /api/invites                               → {invites,accounts}   (authed)
```

- **Store:** `apps/hlidskjalf/server/accounts.ts` owns accounts and invites.
  `SESSIONS` is a `Map<token,login>` — a session knows *who* it is, and
  `/api/me` reports that login, never a hardcoded one.
- **Where it lives:** `~/.config/ymir/accounts.json`, mode `0600`
  (`YMIR_CONFIG_DIR` overrides, for tests). Machine state, never in the repo.
- **Passwords:** `Bun.password` argon2id via `Bun.password.hash/verify`. The
  plaintext is never written; only the hash lands.
- **The operator's own tool:** `bin/engine/ymir-invite.sh {mint,list,revoke,where,ensure}`.
  `ensure` mints only when nothing is live, so the installer stays idempotent.
- **The UI:** `LoginModal` offers "I have an invite code" **only while
  `/api/session.registration` is true**. A spent or revoked code removes the
offer, because the gate is what decides — the surface merely reports it.
- **Refusals are spoken:** the gate's own sentence ("that invite code has been
  used up") is carried to the caller by `services/api.ts` (`errorText`), so the
  login surface says what is actually wrong instead of a bare status.

### Speed-starts inside the apps (added 2026-09-12)

Each app's own UI can raise the other one — `POST /api/desktop {view}`, valid for
`hlidskjalf` and `smidja`. Both servers implement it by calling
`scripts/electron.sh start --view <view>`, the same launcher the Omarchy key
bindings use, so there is **one** way to raise a Ymir window: it raises the app
when it is already up, and starts it when it is not. The visualizer finds the
checkout by walking up to the directory holding `scripts/electron.sh`, so it
works wherever the app is served from.

**rename sweep (2026-09-12).** The `galdr` -> `galdr-ymirsystem` rename corrected a stale path reference inside `apps/hlidskjalf/server/index.ts` as well; behaviour unchanged.

### The gate's default realm is `wayof` (2026-09-12)

Three places in `apps/hlidskjalf/server/index.ts` defaulted to the retired name
`way-of` (the fleet event realm, the reviews realm, and a seeded lint review).
They now default to `wayof`, matching `svartalfaheim/README.md`: one company
container, no person realms. A retired realm name in a default is not cosmetic —
it sends an event to a directory the platform does not have.

### Reviews now reads real pull requests (added 2026-09-13)

`/api/reviews` built exactly one synthetic card (`id: 'lint'`, `number: 1`,
"Brokk lint gate") from the lint + compliance checks — it **never read a pull
request**, so a delivered change had no Glitnir card and Mjollnir's PR leg had
nowhere to land. `reviews()` now first lists the repo's **open PRs** via
`gh pr list --json …` (mapping `statusCheckRollup` to the card's checks; a
failing check sets `state: 'changes'`), then appends the lint + compliance card
(now `number: 0`). Real PRs lead the list; the compile-and-lint card stays.
The review surface's operator copy now names the **Allfather** throughout — the
seal prompt, the rune emit string, the "awaiting the Allfather" tile, and the
gate comment — retiring the imported `captain` term.

### Glitnir tells the whole truth (2026-09-24 audit)

Four gaps closed in one pass:

- **`approved` is now reachable**: `gh pr list --json … reviewDecision,mergeable`
  feeds the card state — GitHub `APPROVED` + green checks lands on
  `state: 'approved'` (the seal button's true prerequisite); CI failing lands on
  `changes`; a draft stays `open`.
- **The tiles count REAL PRs**: "Open PRs / Approved / CI failing" count `number
  > 0` cards only — the Brokk lint + compliance gate card (`number: 0`) is a
  gate, not a pull request, and no longer inflates the count.
- **A dead GitHub read is shown, never swallowed**: `reviews()` returns
  `{ cards, ghError }`; the Reviews gate renders the gh error above the cards.
- **The repo is explicit and the board refreshes**: `gh pr list --repo` derives
  from the origin remote with the documented default `zerwiz/ymir` (so a
  packaged install with no `.git` still reads PRs), and the store refreshes the
  cards on a 30s beat (`refreshReviews`) — a PR that opens after the page loads
  appears without a reload.

### One seat, three halls (added 2026-09-13)

- **Post-login chooser** (`src/components/Halls.tsx`): `App.tsx` shows it once
  after the gate admits the session — three cards explaining Hlidskjalf, Smíðja,
  and Sessrúmnir, each raising its hall.
- **Switcher**: `Halls.tsx` also exports `HallsSwitcher` (three rune buttons),
  which replaces the lone Smíðja speed-start button in the Topbar. Smíðja's own
  topbar and Sessrúmnir's menu carry matching switchers; all route through the
  gate's `/api/desktop`, which now raises Sessrúmnir too (`bin/desktop/sessrumnir-launch.sh`).
- **Search box**: `.topbar .search` `min-width` was 120px — narrower than the
  text "Search work workspace…", so the placeholder clipped. Raised to 280px;
  the input may shrink (`min-width: 0`).
- **One login, Sign out everywhere — verified live, never a file.** The gate is
  the one authority: a session is an in-memory `token → login` map, handed out as
  the httpOnly `ymir_session` cookie. There is **no bearer on disk** and **no
  header credential** (`X-Ymir-Session`/`Bearer` are rejected): a persisted token
  is a credential at rest any local process could replay, and a session read from
  a file is "logged in when you are not". A gate restart ends sessions (nothing
  revives one). Other surfaces verify live: the Smíðja visualizer server forwards
  the browser's cookie to the gate's `/api/session`; Sessrúmnir, having no gate
  cookie, shows a Sign-in link rather than claiming a session. Sign out clears the
  cookie and the in-memory token (shell menu; AccountMenu).
- **The GitHub door is offered only when it can open**: `/api/auth/github`
  returns 503 when no OAuth app is configured, so `/api/session` now carries
  `github: !!(GITHUB_CLIENT_ID && GITHUB_CLIENT_SECRET)` and `LoginModal` renders
  the "Continue with GitHub" button (and its `or` divider) only when true. The
  password door (`HLIDSKJALF_AUTH`) is always present. Configure GitHub with
  `bin/engine/ymir-setup-auth.sh github`.

Rule: a Hlidskjalf code change updates this asset in the same pass — the
compliance gate (`assets/governed assets current`) fails otherwise.

### The Hall door — one button out of the three halls (added 2026-09-13)

The **Óðrerir Live Hall** (the fleet's carved stone/bronze board; now its own
app at `apps/odrerir`, migrated from `~/CodeP/ymir-homepage` on 2026-09-15) is
**not** one of the gate's three apps but it IS its own desktop app since the
migration. The gate raises Hlidskjalf/Smíðja/Sessrúmnir (`/api/desktop` →
`scripts/electron.sh`); Óðrerir is raised with them by `scripts/start.sh` on
`:4322`, opens in its own window via `scripts/electron.sh start --view odrerir`
(native app identity `ymir-odrerir`), and its in-app door is a plain anchor in a
new tab — **never** a launcher call.

- **Where:** `app/Topbar.tsx` carries it beside `HallsSwitcher` — `.hall-btn`, the
  rune **Othala (ᛟ)** plus "To the Hall", tinted with the active realm accent so
  it reads as the same chrome as the chips around it. Styled in `styles/shell.css`
  (tokens only, no raw hex), press feedback in `styles/overlays.css`.
- **The hall app:** `apps/odrerir` — an Astro board (the Óðrerir Live Hall) that
  serves `:4322` and reads `public/livehall.json`, written by
  `systems/snotra/services/cron/hall-snapshot.sh` (planning glass; public-safe). Its own Electron shell:
  `apps/odrerir/electron/main.cjs`, raised by `scripts/electron.sh --view odrerir`.
- **Target rule — one rule for all of Ymir's apps:** `HALL_URL` in
  `src/data/metadata.ts`. `window.location.host` starting with `localhost` or
  `127.0.0.1` → `http://localhost:4322`; any other host → the public
  `https://hall.ymir.zerwiz.org`. `VITE_HALL_URL` overrides it, exactly as
  `VISUALIZER_URL` does. Each app computes this inline — the Vite builds are
  separate, so there is no shared module to hang it on.
- **Same door** in the Smíðja visualizer's topbar and in Sessrúmnir, so every
  app's chrome has one way to the Hall.
- Verified: both branches of the rule in both apps (headless Chromium DOM probe),
  `tsc --noEmit && vite build` green, 0 console errors; `apps/odrerir` builds
  standalone and the hall answers `:4322` from `scripts/start.sh`.

## Packaging (Amendment C)

Each app ships as its own published package under the `@zerwiz` scope (the scope
that already carries `@zerwiz/ymir`) — `@zerwiz/hlidskjalf`, `@zerwiz/odrerir`,
and `apps/hlidskjalf/package.json` carries the metadata that makes that legal:
`license`, `repository`, `publishConfig.access: public`, a `files` surface, and
`prepack` where a build exists (never `prepublishOnly`: a build must not be able
to veto a publish, and neither must a documentation gate).

Two facts worth keeping:

- **The APK is not in the tarball.** `apps/hlidskjalf/dist/ymir.apk` (~13.6 MB)
  is built for Android, not for npm; `files` excludes it with `!dist/*.apk`.
  Including it took the package from 1.3 MB to 14.5 MB — npm is not an APK
  distribution channel.
- **`private: true` is the safety catch.** It stays set until the Allfather
  publishes deliberately, so no accidental `npm publish` can push a half-built
  artefact to a public registry.

Measured with `npm pack --dry-run --ignore-scripts` (see the app's `files` for
the exact surface).

## The two doors — web logs in, the desktop seat does not

There is **one** login surface (`LoginModal` → `POST /api/login`), and it belongs
to the **web** door. The desktop shell (Electron) is a local, trusted seat and is
never asked to log in.

The mechanism is deliberately narrow, because a marker a client can send is not
proof of anything:

- the Electron preload exposes `window.ymirDesktop = { desktop: true }`;
- the SPA sends `x-ymir-surface: desktop` on every request, and
  `?surface=desktop` on the SSE stream (EventSource cannot set headers);
- the gate (`server/index.ts`) honours that marker **only when the request
  arrives over loopback** — `REQUEST_IP`, recorded per request from Bun's
  `server.requestIP(req)`, because Bun's `Request` carries no socket. A remote
  web caller can send the header and still be refused.

Verified both ways: `GET /api/session` without a cookie is `authed:false` and
`/api/orders` is 401; the same calls with the marker from 127.0.0.1 are
`authed:true` (login = the operator) and 200.

### The launcher icons are re-cut, never stale (2026-09-23)

The SVGs carry the design (stone + rune + tint); the launcher icons are
**rasterised copies**, and they go stale the moment the design moves — the
electron icons for Hlidskjalf and Óðrerir were still **blue**, and
`ymir-icon.png` was a **grayscale** relic. `bin/desktop/design-icon.sh raster` re-cuts
every app icon from its own `public/icon.svg` (rsvg-convert, else magick):

- hlidskjalf → `electron/icon.png` (512), `public/apple-touch-icon.png` (180);
- odrerir → `electron/icon.png` (512), `public/apple-touch-icon.png` (180);
- sessrumnir → `resources/icons/icon-{16…512}.png` + `icon.png` +
  `public/apple-touch-icon.png` (180) + the `.ico` files;
- smidja → `apps/smidja-factory/apps/visualizer/desktop/icon.png` (512);
- the Ymir emblem (**algiz** on stone) → `hlidskjalf/public/ymir-icon.png`, and
  the smithy's icon → `hlidskjalf/electron/smidja-icon.png`.

Run it whenever the design or a glyph changes; it is idempotent and writes
nothing else.

### The Fleet names why it is empty (2026-09-27)

An empty board had four different causes and the surface showed one silent
`0/0`: the roster was read (`live`), the gate refused the request
(`unauthorized`), the connector answered with an error (`unreadable`), or the
gate did not answer at all (`offline`). The board now names the cause:

- `services/api.ts` throws `GateError` (HTTP status preserved) instead of a bare
  `Error`, so a caller can tell a 401 from an unreachable gate.
- `state/store.ts` exports `AgentsStatus`, derives it for the roster call
  (`agentsFailureStatus`: 401 → `unauthorized`, another `GateError` →
  `unreadable`, else `offline`), and exposes it; every other endpoint still
  degrades on its own.
- `gates/Fleet.tsx` reads it and prints the one honest line — `gate
  unauthorised`, `roster unreadable`, `gate offline`, or `no agents standing`
  when the gate answered and the roster is truly empty — with a matching chip
  and an empty-fleet panel.
- The roster path is **absolute and read from the repo root**: both
  `bin/desktop/hlidskjalf-agents.sh` and its server copy resolve `REPO_ROOT` (git) and
  export `ROSTER_DIR="$REPO_ROOT/.agents/agents"`; `/api/agents` runs the
  connector with `cwd: ROOT` and `ROSTER_DIR: AGENTS_ALT`, and treats an empty
  connector array as **no data**, falling through to the roster rather than
  painting an empty fleet.

Rule: a Hlidskjalf code change updates this asset in the same pass.
### The mobile shells — PWA, Android, iOS (2026-09-27)

Hlidskjalf reaches a phone three ways, all the same web app:

- **PWA.** The SPA carries `manifest.webmanifest` (`display: standalone`),
  `sw.js`, `apple-touch-icon.png`, and a theme-color, so Safari's *Add to Home
  Screen* installs it. A secure context (HTTPS) is required for the service
  worker; `tailscale serve --bg <port>` or the tunnel supplies one.
- **Capacitor shells.** `apps/hlidskjalf/android` (existing) and
  `apps/hlidskjalf/ios` (added 2026-09-27) wrap the web app for the stores. Both
  are thin and read `YMIR_SERVER_URL` (default `http://127.0.0.1:3888`) at
  `cap sync` time; with `cleartext:false` an operator points them at their HTTPS
  host with no code change. iOS builds require macOS + Xcode and are produced on
  a Mac, never here — `ios/` is scaffolded, not built.

### Þráðr — the terminal in the high seat (2026-10-23)

The high seat can carry a **real shell**, not a picture of one. `src/components/Terminal.tsx`
draws with **xterm.js** — the emulator VS Code uses — and the other end is a pty on the gate
(`node-pty`), so `herdr`, `vim` and anything else with a TTY behaves as it does in a terminal
window. A panel that only printed text would not be a terminal; a terminal that runs in the
browser with no pty is a log viewer wearing a shell's clothes.

- **Three packages, declared.** `@xterm/xterm`, `@xterm/addon-fit` and `@xterm/addon-web-links`
  are dependencies of `apps/hlidskjalf/package.json`. They were imported but **never declared**,
  which is the fault this section exists to prevent: `tsc --noEmit` could not resolve them, so
  `npm run build` failed and **the whole SPA bundle failed with it** — the gate was dark for a
  reason that had nothing to do with the gate. Any import the component gains is declared in the
  same change; `bin/desktop/app-build.sh hlidskjalf` is the proof, and it is what
  `bin/forge/npm/npm-pretest.sh` runs before a tarball is packed.
- **The status door.** `/api/terminal/status` reports the seat's real state:
  `enabled` follows `YMIR_TERMINAL=1`, `remoteAllowed` follows `YMIR_TERMINAL_REMOTE=1`,
  with `maxPerUser` (`YMIR_TERMINAL_MAX_PER_USER`, default 2) and `idleTimeoutMs`
  (`YMIR_TERMINAL_IDLE_MS`, default 900000). When it is off, `reason` says so in words —
  *"disabled: YMIR_TERMINAL is not 1, and this gate holds no pty"* — because a blank black
  rectangle is indistinguishable from a hang. The panel once called this route before it
  existed and printed `terminal status 404` where a capability belongs (plan 93).
- **The socket owns the shell.** The panel opens a WebSocket to `/api/terminal`; unmounting
  closes it and the gate kills the pty on close, so a closed tab is never a shell running
  unattended. A refusal from the gate is **shown**, never swallowed.
- **The cloth.** Colour comes from the app's own CSS variables (`--bg`, `--fg`, `--ember`), so
  the terminal wears the hall's palette instead of a foreign one.

Rule: a Hlidskjalf code change updates this asset in the same pass — and a component's imports
are part of that change, not an afterthought of the install.

### Skírnir speech entry — local assistant, separate from Snotra (2026-11-02)

The skirnir gate (Skírnir – Tala) is first in GATES and has its own metadata and
Topbar entry. The existing SnotraLive Start listening control retains meeting/
room recording semantics. The new page uses explicit consent plus getUserMedia
only on a user click, then MediaRecorder for one question (30-second capture
cap). Finish stops every track before upload; Stop and unmount close tracks,
abort browser requests/playback and DELETE the owned pending turn.

server/voice.ts implements /api/skirnir/voice/status and GET/POST/DELETE
/api/skirnir/voice/turns/:id. Real peer loopback, local host, same Origin,
no forwarded requests and local-operator eligibility are required. An unrelated
signed-in account cannot become owner through this route. No browser API key or
engine URL is needed. The existing trusted local browser gets its operator
session label; remote authentication is not relaxed.

The native file adapter, installed Whisper/Kokoro and existing skirnir.py own
transcription, approved knowledge, refusals and speech. SKIRNIR_HOME selects the
private profile; SKIRNIR_VOICE_TMP selects temporary audio; SKIRNIR_PYTHON selects
the interpreter. Engine URLs must be loopback. English has Kokoro speech;
Swedish is input transcription plus text-only output, never English phonetics
labelled Swedish. Escalation is suppressed for this local voice channel, so it
opens no external messaging road. Backend turn state is memory-only; temporary
audio is separate from the Snotra record shelf and is removed after processing.

The Vite API proxy uses a keep-alive HTTP agent: its default forced Connection:
close reset native Windows audio uploads. It never retries failed audio as if
it succeeded. voice-preview.ps1 starts only isolated loopback API/UI processes,
with separate gate state, no production key read and no main deployment.

Tests: server/voice.test.ts (peer/origin/owner boundaries, invalid uploads and
stop-before-upload tombstone) and tests/voice.e2e.mjs (real prerecorded input,
real existing answer/Kokoro, synthetic browser capture, track release, pending
turn cancellation and Swedish text-only mode). Browser tests require fake-device
and prerecorded-input flags and must never capture a physical microphone.
Operator guide: docs/features/talk-to-skirnir.md.
### Update — app-scoped F8/Escape and genuine Swedish speech

This supersedes the temporary Swedish text-only mode in the preceding section.
The focused Skirnir page owns F8 (start through visible consent; next F8 finishes
and submits) and Escape (cancel capture, pending turn or playback). Repeats,
modified combinations, editable typing, hidden pages and unfocused apps are
ignored. No system-global shortcut exists. Labels explain the scope beside
the controls; F8 never bypasses checkbox or browser microphone permission.

English speech is pinned to American female Kokoro af_nicole and its returned
adapter metadata is checked. Swedish uses Microsoft Bengt sv-SE through the
private file contract, not Kokoro: SKIRNIR_SWEDISH_DIR defaults to the home's
hodd/state/runtime/skirnir-swedish; installation.json.executable records the
verified default PowerShell 7.6.5 path. SKIRNIR_SWEDISH_PWSH and
SKIRNIR_SWEDISH_SCRIPT are documented overrides. Version 5.1 is never a fallback.
The gate writes UTF-8 answer text into its private turn directory, invokes the
contract with -TextPath/-OutputPath, verifies Bengt/culture/24kHz/mono/PCM16
metadata, and returns the genuine WAV. Cancellation and cleanup own the turn,
not the shared engines. Public source carries no account/package-specific path.

skirnir.py --language sv localizes greeting, permitted-fact inventory and honest
refusal before its existing gate/audit. It does not invent translations of
approved facts: missing verified Swedish wording produces a spoken limitation.
The voice-local channel refuses delivery/learning/research action branches, so
no external action is hidden behind an assistant answer.

Final proof: 11 passing synthetic browser checks with zero uncaught browser
errors: consent/no capture on load, F8 consent, typing exclusion, actual file
chain, Nicole identity, F8 capture/repeat/finish, Escape track release, Escape
pending cancellation, genuine Swedish ASR -> permitted Swedish answer -> Bengt
WAV, Escape Swedish playback, and browser errors. Additional key policy tests
cover modifiers, hidden/unfocused pages and every pending state. Root independently
confirmed the consent gate with getUserMedia forbidden and zero physical capture
attempts, then opened the ordinary local browser for the operator. Earlier
Swedish-disabled concern during status loading is superseded, not home drift.
### Swedish installer contract update — integrity and independent recognition

swedish-voice.ts now reads the private installation.json executable, arguments
and script_sha256. It validates the file-only flag shape, substitutes only the
UTF-8 input/WAV output placeholders and checks actual script bytes against the
recorded SHA-256 immediately before invocation. Env overrides do not bypass
that integrity check. No account/package path is hardcoded into public source.
Three focused contract tests cover exact manifest invocation, tampered/missing
hash and unexpected flags; a real synthetic Swedish file round trip on an
isolated ephemeral port passed. The 11 passing F8/bilingual browser results were
preserved rather than rerun. The owned preview API was reloaded only at active=0;
its UI, browser and shared engines remained running.

Independent Swedish Whisper recognition succeeds semantically but has observed
word-form and proper-name errors (svenskt -> svensk, Skirnir -> skinir). Neither
these tests nor the operator guide promise perfect ASR. The existing local
F8/Escape scope, Nicole/Bengt routes and no-microphone automation boundary hold.
### Rendered availability refresh — pending is not unavailable

The Skirnir client now distinguishes unconfirmed Swedish capability from an
actual negative status response. Before completion it says kontrollerar röst,
not röst ej tillgänglig. Status refreshes on focus/visibility; Kontrollera röster
performs an explicit read. While Swedish availability remains unconfirmed, a
visible idle page rechecks every five seconds, deduplicating reads and cleaning
up timers/listeners on unmount. None of these paths requests microphone access.
The existing SKIRNIR_HOME/preview-home routing was not changed: current server
status already reported both voices available.

The targeted tests/swedish-selection.e2e.mjs proof uses the actual running UI,
no media permission and forbidden getUserMedia. It verifies the rendered enabled
Svenska · Bengt selection, an actual prerecorded Swedish request, real permitted
Swedish answer and browser-decoded Microsoft Bengt WAV, with zero physical
capture attempts and zero uncaught errors. This is fresh rendered UI proof,
not an inference from API speech=true, and does not rerun the broad voice suite.