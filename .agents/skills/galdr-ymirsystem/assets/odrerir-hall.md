# Óðrerir — the Live Hall (apps/odrerir) reference

Purpose: the complete reference for **Óðrerir**, the Ymir fleet's planning glass —
the carved board that reads the machine's real state and renders it read-only:
the tally of the hall, the armed errands dealt one slate at a time, the smiths and
their states, the tickets and the plans.

> The hall is its **own app** under `apps/odrerir`, **built as a Hlidskjalf-type
> app since 2026-09-24 (plan 55)** — React + Vite + TS, the ember hearth, the
> translucent panels, and the halls buttons in the same design as the high seat.
> It was an Astro static board before, and it is one no longer. It keeps its
> **own** Electron window (`--view odrerir`) and its own port `:4322`, so it
> never stacks with Hlidskjalf or Smíðja.

---

## 1. What the hall is

| Thing | Value |
|---|---|
| Norse figure | **Óðrerir** — the cauldron of the mead of poetry, poured live |
| App home | `apps/odrerir` |
| Tech | React 19 + Vite 6 + TS (mirrors `apps/hlidskjalf`; `main` → `electron/main.cjs`) |
| Cloth | the canonical `midgard/design-system/tokens.css` + the hearth (`midgard/design-system/ember.js`, carried in-repo) |
| Boards | the tickets + plans, BOTH in the tickets anatomy (table · filters · bulk · +new · detail sheet); Skuld MCP through this body's gateway door |
| Port | `:4322` (env `ODRERIR_PORT`) |
| Public face | `https://hall.ymir.example.org` (production) |
| Desktop app | `ymir-odrerir` — its own Electron shell, own icon, own `.desktop` |

The SPA (`src/App.tsx` → the EmberBackground + the topbar with the halls
buttons → the boards) builds to `dist/`. The boards read the **record through
THIS BODY's own MCP gateway** (`http://127.0.0.1:8316/mcp/skuld`, port from
`VITE_MCP_GATEWAY_PORT`): the gateway resolves the heart (zerwizserver) at REQUEST
time, so the hall never names the heart and a heart move never moves the hall's
door (plan 51 P6/9c — the same law the harnesses' `mcp-adapter.json` obeys).
The door admits the browser origin (CORS, restored 2026-09-27 and PINNED to the
body's own pages 2026-09-28), so the board reaches it straight from the page —
the road the retired skuld server opened and the gateway had dropped. Only a
loopback origin (127.0.0.1 · localhost · `[::1]`), or one listed in
`MCP_GATEWAY_ALLOWED_ORIGINS`, is admitted; a foreign origin is refused (403).

## 2. Raising the hall

### 2.1 With the whole stack

`scripts/start.sh` raises it in its own stanza (before the Hlidskjalf SPA so a
window never waits):

```
scripts[1]{command,result}:
  "scripts/start.sh","Óðrerir — Live Hall raised (pid <pid>) → http://127.0.0.1:4322/"
```

- If `apps/odrerir/node_modules` is missing it installs once (workspace-aware:
  the root `npm install` hoists; vite arrives by the P3 law).
- A packaged app ships `dist/` and is served with
  `npx --no-install vite preview --port :4322`; a clone runs `npm run dev`.
- Liveness is tracked by `.run/odrerir.pid`, logs to `.run/odrerir.log`.
- Idempotent: already running → "already running" line, no double spawn.
- Missing app dir → `Óðrerir — Live Hall skipped (missing apps/odrerir).`

### 2.2 Standalone (working on the hall itself)

```
hall-dev[4]{command,when}:
  "cd apps/odrerir && npm run dev","hack + watch (vite dev server on :4322)"
  "cd apps/odrerir && npm run build","tsc --noEmit && vite build into dist/"
  "cd apps/odrerir && npm run preview","serve the built dist for a look"
  "cd apps/odrerir && npm run typecheck","tsc --noEmit"
```

`npm install` is required once (`--no-audit --no-fund`).

### 2.3 Its own window

`scripts/electron.sh start --view odrerir` opens the hall in its **own** Electron
app:

```
odrerir[4]{aspect,detail}:
  "identity","ymir-odrerir (class, .desktop, user-data-dir, single-instance lock)"
  "URL","http://127.0.0.1:4322/ (own window, never hosted inside Hlidskjalf)"
  "pid","state/electron-odrerir.pid; log state/electron-odrerir.log"
  "menu","Reload / DevTools / quit (own app menu — no cross-app Sign out)"
```

The hall's Electron binary is resolved by `bin/desktop/electron-lib.sh` (one resolver,
app-local → hoisted → sibling); the app directory passed to Electron is
`apps/odrerir` (its `package.json` `main` → `electron/main.cjs`). The hall has
**no** gate session — a Sign-out link is never shown.

## 3. The boards

- **Tickets** (`src/components/TicketsBoard.tsx`) — the hall's book (plan 43):
  the filterable table (status · priority · assignee) with bulk power and a
  +new door; pressing a row opens the detail sheet with the stat-strip, the
  state march, the assignee's pick and the comments thread. Tools over Skuld:
  `tickets/list|get|create|update`, `comments/list|post`.
- **Plans** (`src/components/PlansBoard.tsx`) — the roadmap, wearing the SAME
  anatomy: a filtered table (id · title · state · rides), a +new plan door
  whose ticket picker lists the living tickets, and a detail sheet with the
  plan's body and the tickets it rides. Tools: `plans/list|get|create`.
- **One layout, one law**: a plan's tickets must exist before the plan does.

## 4. Working on the hall — laws and gotchas

- **The halls buttons** (`src/App.tsx`, `HALLS`) are the high seat's control:
  they raise the other Ymir windows through the Hlidskjalf gate
  (`/api/desktop`). A quiet gate never breaks the board.
- **The cloth is the canonical import**: `src/hall.css` imports
  `midgard/design-system/tokens.css`; the hearth is the carried-in
  `midgard/design-system/ember.js`. No bespoke palette, no generated regions.
- **The Skuld door is env-overridable** (`VITE_SKULD_URL`), defaulting to this
  body's gateway (`http://127.0.0.1:<VITE_MCP_GATEWAY_PORT>/mcp/skuld`, port
  default 8316) — the app never bakes a heart address (plan 51 P6/9c).
- **Ports are sacred:** `:4322` is Óðrerir's alone. Do not move it into a
  Hlidskjalf route or a launcher call — its door is its own window and its own
  topbar buttons.
- **Astro is gone**: no `src/index.html` verbatim page, no `.astro` pages, no
  `astro.config.mjs`, no `check:cloth` — anything that looks for them is
  looking at the old world.

## 5. Files you will touch

```
files[6]{path,what}:
  "apps/odrerir/src/App.tsx","the shell — hearth, topbar, halls buttons, hash views"
  "apps/odrerir/src/hall.css","the cloth: tokens import, glass panels, the boards' anatomy"
  "apps/odrerir/src/components/TicketsBoard.tsx","the hall's book — table · bulk · +new · detail"
  "apps/odrerir/src/components/PlansBoard.tsx","the roadmap — the same anatomy"
  "apps/odrerir/src/skuld.ts","the Skuld MCP client (this body's gateway door, session header)"
  "apps/odrerir/electron/main.cjs","the hall's own window (single instance, no session)"
```

Door plumbing that reaches the hall from other apps: `HALL_URL` in
`apps/hlidskjalf/src/data/metadata.ts` (`localhost|127.0.0.1` → `:4322`, else the
public hall), surface rules in `.agents/skills/galdr-ymirsystem/assets/hlidskjalf-ui.md`
("The Hall door" section), and `systems/snotra/services/cron/hall-snapshot.sh` for the livehall feed if a
board ever needs it again. Everything the hall renders lives under
`apps/odrerir/`.
### The three doors + the raise hinge (2026-09-24, follow-up)
- `#/` is the **hall board** (`LivehallBoard`) — the livehall snapshot
  (`/livehall.json`: tally · smiths · the call · ledger), fail-closed when the
  snapshot is absent. `#/tickets`, `#/plans` are the boards; the topbar links
  are the board · the tickets · the plans.
- The **halls buttons** raise the other windows through the Hlidskjalf gate via
  the vite `/api` proxy (same-origin; `ODRERIR_GATE`, default
  `http://127.0.0.1:3889`) with the desktop-seat marker when the seat is one —
  a direct cross-origin POST is CORS-blocked and dies silent (fixed 2026-09-24).
- The plans board wears the tickets' skin exactly: the same status badges
  (`src/board.ts` — one palette), the same inline +new panel, the same table.

### The book had no door to register a namespace (2026-10-11)
- The server served **`namespaces_list` and no way to add one**, while `tickets_create`
  and `plans_create` both REFUSE an unregistered namespace. So the registry could only be
  extended by hand with `psql` against the heart's Postgres — a door nobody could run, and
  the one gap the Allfather named: *"can we add the namespace thru the mcp?"*
- Now served: **`namespaces_create`** — a slug (2..40, lower-case letters/digits/`-`, folded
  to lower case) and a display name (`about`, 2+). A malformed slug or a thin display name
  is REFUSED **and blocks the agent** (the same blocking law as a bad ticket); registering one
  that already exists is a no-op, not an error; a store refusal is reported verbatim.
- Proven without a heart: the real `server.mjs`, its real handler, with a stub `psql` —
  `tools registered: 16 · has namespaces_create: true`, the bad slug and the thin `about` both
  refused, `Probe-NS` folded to `probe-ns`, and the wire shows
  `INSERT INTO namespaces (name, about) VALUES ('probe-ns', 'Probe Namespace') RETURNING name, COALESCE(about, name)`.

### The boards' MCP alignment + the connection chip (2026-09-24)
- **The server's true tool names are underscored, un-prefixed**: `tickets_list`
  · `tickets_get` · `tickets_update` · `tickets_create` · `comments_list` ·
  `comments_post` · `plans_list` · `plans_get` · `plans_create` · `namespaces_list` ·
  `namespaces_create`. The old hall
  (and the first React port) called them with slashes (`tickets/list`) — a name
  the server never served; the boards rang a dead door. The UI calls the true
  names; `bin/desktop/odrerir-mcp-smoke.sh` asserts that alignment (`tools/list`) so a
  rename can never silently orphan the UI.
- **Skuld answers tools/call as SSE** (`event: message` + a `data:` JSON frame);
  the client parses the last data frame, plain JSON otherwise.
- **The connection is VISIBLE**: `src/skuld.ts` publishes a status and the
  boards render the chip (connected / ringing / NOT connected — the cause +
  retry). A dead door looks dead, never like an empty book.
- **Smoke**: `bin/desktop/odrerir-mcp-smoke.sh` is wired into the lifecycle smoke as
  the `boards` row (real initialize + list + get + comments through this body's
  gateway door, with the alignment assert).

### The hall board is the ORIGINAL, carried whole (2026-09-24, the never-simplify law)
- `LivehallBoard` renders the ORIGINAL Astro `<main id="livehall">` verbatim
  (vite `?raw`), injects the original saga payload, and runs the original board
  script — the dealt slate stack with its option cards and recommended marks,
  the freeform word with the 512-byte queue guard, stack navigation, the
  dispatch picker, the carved ledger thread rows, fail-closed render. No
  re-invention: `src/hall/{lh-main.html,lh-saga.json,lh-board.js}` are the
  originals from git history; `lh-scoped.css` is the original kit (cloth +
  livehall.css) scoped to `#livehall`.
- **Law:** a port is never simplified — the original is the contract.
  The tickets' click-detail is proven (CDP): the detail sheet opens with the
  title, the description and the stat-strip.

### The living door + the live feed (2026-09-27 — the React hall reads LIVE again)
- **The wound.** The React port kept the Astro door's default `SKULD_URL =
  http://whynot.<tailnet>.ts.net:8320`. The 2026-09-27 cutover (plan 51 Part 9)
  retired whynot's Skuld unit and moved the record to the heart (zerwizserver),
  so every board call rang a dead seat and the book read empty. The one gateway
  (`bin/bridge/mcp-gateway.sh`, :8316) fronts skuld over the heart — but the gateway had
  no CORS, so a PAGE still could not read it directly.
- **The repair (one door, one resolver).** `src/skuld.ts` rings THIS BODY's
  gateway — `http://127.0.0.1:${VITE_MCP_GATEWAY_PORT:-8316}/mcp/skuld` — and
  `VITE_SKULD_URL` overrides the whole door. The app names no heart; the gateway
  resolves it at request time. The gateway engine
  (`tools/mcp-gateway/server.mjs`, v1.1.0) admits the browser origin again
  (preflight `OPTIONS` → 204 + `access-control-allow-origin`), restoring the road
  the retired skuld server opened (`b0c1569`, "Skuld's CORS opened for the
  browser"). `bin/bridge/mcp-gateway.sh` carries the same note.
- **The saga sample, honestly cleared.** The hall board (`#/`) clears its "Not
  connected — this board is the saga's sample" note only when `/livehall.json`
  answers with a feed (`src/hall/lh-board.js:506`). `systems/snotra/services/cron/hall-snapshot.sh` writes
  `public/livehall.json`, but a build bakes that file into `dist/` and a
  packaged install (gitignored snapshot) carries none — so the note could stand
  forever. `vite.config.ts` now serves that file from disk on EVERY request in
  dev and preview (`ymir-livehall-feed`): the feed is whatever the snapshot job
  last wrote, `cache-control: no-store`; absent → 404 → the board keeps the
  saga's tale, never invented rows.
- **Knobs:** `VITE_MCP_GATEWAY_PORT` (build-time, default 8316 — the gateway's
  own `MCP_GATEWAY_PORT` default); `VITE_SKULD_URL` overrides the whole door.
- **Deploy note:** the engine change reaches the body's running door by
  restarting it — `systemctl --user restart mcp-gateway` (the unit runs
  `bin/bridge/mcp-gateway.sh serve` from the tree).
- **Smoke:** `bin/desktop/odrerir-mcp-smoke.sh` defaults to the gateway door and parses
  the gateway's plain-JSON `tools/list` as well as the heart's SSE frame; the
  lifecycle `boards` row now probes the gateway's `/health` (a loopback door,
  not another seat's name).

### The door is PINNED, and the feed lives in both shapes (2026-09-28 — Forseti's rework)
Forseti's review of #239 (`$YMIR_HOME/state/eindri-reports/odrerir-live-door-review.md`)
held the seal with three items; this section records the mend.
- **The CORS hole (F2).** The engine answered `access-control-allow-origin: *`,
  always `access-control-allow-private-network: true`, with no origin gate — and
  127.0.0.1 is mixed-content-exempt, so ANY visited page could read and WRITE the
  record (well · bolthorn · skuld). The false invariant ("the gateway binds
  127.0.0.1, so only this body's own pages can reach it") said otherwise. The
  engine (v1.2.0) now PINS the admitted set: any loopback origin, plus
  `MCP_GATEWAY_ALLOWED_ORIGINS`; a foreign Origin is refused with **403 before
  the method gate** (not merely denied CORS — a simple request can carry a JSON
  body without a preflight). `access-control-allow-private-network` is removed
  and the origin is echoed, never `*`. A request with no Origin is a native MCP
  client and is admitted.
- **The packaged feed (F1).** `systems/snotra/services/cron/hall-snapshot.sh` now writes the snapshot to
  `public/livehall.json` AND, when the app carries a `dist/`, to
  `dist/livehall.json`. A clone is served by `vite dev`/`vite preview` through
  the `ymir-livehall-feed` plugin (public/, request time); a packaged seat has
  no `vite.config.ts` and is served by `vite preview` from `dist/` — where the
  job's write now lands. The served feed is the job's last write in BOTH shapes.
- **The knob name (F3).** This asset now names `VITE_MCP_GATEWAY_PORT` (the
  app's build knob, `src/skuld.ts:24`) in every row; the gateway's own
  `MCP_GATEWAY_PORT` stays the server-side default the build knob mirrors.

### The board's kit never reached the bundle (2026-10-11, found diagnosing odrerir/1)
- `src/hall.css` ended with `@import "./hall/lh-scoped.css";` — and CSS requires
  `@import` to precede every other statement, so PostCSS **dropped it** and the
  original board's kit (108 lines of `#livehall` rules, carried under the
  never-simplify law) never reached the output. The board rendered with markup and
  no styling, while `tsc --noEmit && vite build` passed — a build that passes is not
  a hall that works.
- Measured: built CSS **11,021 → 33,627 bytes**, `#livehall` occurrences **0 → 199**,
  the postcss warning gone.
- The kit is now imported by JS in `src/main.tsx` (Vite's way to order stylesheets),
  placed AFTER `./hall.css` so the scoped kit keeps the cascade position it was
  written for.
- **When adding CSS here, do not use a trailing `@import`.** A file-level `@import`
  is only legal at the top; for a kit that must win, import it from the JS.

---

## 6. The near loop — `#/near` (2026-11-06, plan 199)

A fourth door in the top bar: `#/near`, the operator's screen for the posture between
in-the-loop and out-of-it. Three blocks, each read-only and each filled **independently**,
so one slow door never blanks the page:

```
near_blocks[3]{block,what,door}:
  "the four dials","model · window + both compaction thresholds · prompt surfaces in force · tools by source","/api/core-four + /api/context"
  "what waits on you","open PRs · the wake queue · mail drafts · his decisions — every card names its shelf","/api/pending"
  "working now","the agents and panes standing, and the trees in flight","/api/agents + /api/worktrees"
```

**The card anatomy is reused, not invented.** The page is a sibling of
`zerwiz/pi-durable-news-agent`'s browser client (MIT): title · category chip · score +
confidence · source + age · two actions (open · dismiss). That client is **Vue** and nothing
of it is imported; `src/components/CardView.tsx` re-implements the five shapes
(`headline` · `brief` · `signal_alert` · `fact_check` · `hype_watch`) behind ONE interface, so
a pending item, a dial, an agent and a tree all render through the same component. An
unimplemented shape falls back to `brief`, as that app's own registry does.

**jev is vendored for the HFS vocabulary** — `src/vendor/jev/` (`types.ts` + `policy.ts`,
MIT, Copyright (c) 2026 IndyDevDan, upstream `273b79b`), with `VENDOR.md` naming what was
taken and what was refused (its network client, its `node:fs` ledger, its CLI, its mock).
**Never write an HFS policy here**: the categories, the thresholds, `rankHfs` and
`suspectCombo` are jev's. No classification has been run for these items, so a card says
**Not ranked yet** — an invented score is worse than an honest blank.

Laws that hold it honest:

- **It reads; it does not act.** *Dismiss* hides a card from the view only.
- **A door that fails paints an *unread* card** naming the door and the reason.
- The cloth is `hall.css` as everywhere else: the card block uses `--hall-*` and `--ymir-*`
  tokens only. **No new palette, no raw hex.**
