## hlidskjalf · unversioned · 2026-11-06 — the near loop: the doors on a screen, and a plans board that read its own ledger

### Why

The near loop (plan 199) names the posture between *in the loop* and *out of it*: the
agent acts and the operator approves. Approving only works if what is blocked on him is
**one list**, and if the dials that decide an agent's outcome are **one read**. Neither
existed. The four dials sat in four files and three shelves — an operator tuned three and
never saw the fourth — and "what waits on me" was scattered across open PRs, the wake
queue, mail drafts and the status shelf, each truthful and each separate.

The same evening exposed a second fault, and it is the worse one: the hall's plans board
said **"no plans cut yet"** while the canonical ledger carried **149 numbered plan files**.
Skuld's `plans_list` is the WRITE door and its table was empty; the board asked the write
door for the read and reported the emptiness as truth.

### What changed

1. **Four gate endpoints** (`apps/hlidskjalf/server/index.ts`), each a carrier over a seat
   door and never a re-implementation of one: `/api/core-four`, `/api/pending`,
   `/api/context`, `/api/plans`. Memoised — 30 s for the dials and the ledger, 15 s for the
   two live questions. A door that cannot answer returns an `error` **object**, so the
   screen paints an unread card instead of a zero (the 2026-10-23 fault).
2. **A hang in the gate, found and fixed.** The first version read the doors through the
   gate's shared `runAsync`, which awaits `new Response(proc.stdout).text()`. A door that
   starts its own child — `core-four.sh` asks `bin/model/catalog.sh` — can leave the pipe
   open after `timeout` kills the shell, so that read **never returns**: the endpoint hung,
   and `memoAsync`'s in-flight map then handed the same dead promise to every later caller.
   `/api/core-four` was measured hanging past 68 s. The door read is now spawned directly
   with a bounded race (`11 s`) and its own cache key; a stuck pipe returns *"did not answer
   in time"*. Measured after the fix: cold `4.35 s`, warm `0.001 s`.
3. **The panel** — Óðrerir `#/near`, three blocks: *the four dials*, *what waits on you*
   (each card naming its shelf), *working now* (agents, panes, trees in flight).
4. **The plans board fallback** (`PlansBoard.tsx`): Skuld first; when it answers with no
   rows — or does not answer — the board reads `/api/plans`, and the panel head says which
   door answered (`skuld · the book` / `the ledger · N files`). A ledger plan's **state** is
   the ledger's own `README.md` index cell, as `bin/gates/plan-audit.sh` holds it; the body's
   `Status:` line is the fallback; neither means `undeclared`. `old-plans/` is skipped by
   name — its numbers repeat the living ones, and a retired plan shown as live is a lie.

### The card anatomy is reused, not invented

The page is a **sibling** of `zerwiz/pi-durable-news-agent`'s browser client rather than a
new language: title · category chip · score + confidence · source + age · two actions
(open · dismiss). Its components are Vue, so they are **not** imported — `CardView.tsx`
re-implements the five shapes (`headline`, `brief`, `signal_alert`, `fact_check`,
`hype_watch`) behind one interface, and the three shapes it does not implement fall back to
`brief` exactly as that app's own registry falls back for an unknown component. One
component renders a pending item, a dial, an agent and a tree.

**jev is vendored, not rewritten** (`apps/odrerir/src/vendor/jev/`, MIT, Copyright (c)
2026 IndyDevDan, upstream `273b79b`): `types.ts` + `policy.ts` — the HFS vocabulary,
`rankHfs`, the label threshold, `suspectCombo`, `attentionScore`, the confidence `gate`.
`client.ts` (network + key), `ledger.ts` (`node:fs`), `command.ts` and `mock.ts` (a test
double — no mock ships) are deliberately not taken; `VENDOR.md` says why.

### The doors themselves

`bin/seat/core-four.sh`, `pending.sh`, `context.sh` are **not this change's work**. They
were authored on the sibling branch `feat/near-loop-doors` (`8aa77248`, checked out in the
main tree) and are **not on `main`**, so this branch carries them **unmodified** in order
that the panel could be built and proved standalone. When both branches land they are the
same bytes. The three endpoints that branch also wrote were re-written here over the fixed
door read, so that branch and this one touch the same region of `index.ts` and will want a
human merge — the Allfather's, not an agent's.

### Files

- `apps/hlidskjalf/server/index.ts` — `seatDoor()` (bounded read, own cache key),
  `planState()` / `tidyState()` / `ledgerIndex()` / `ledgerRoot()` / `planLedger()`, the four routes.
- `apps/odrerir/src/components/NearBoard.tsx` — the `#/near` screen; each block fills as its
  own door answers, so one slow door cannot blank the page.
- `apps/odrerir/src/components/CardView.tsx` — the one card interface and the five shapes.
- `apps/odrerir/src/components/PlansBoard.tsx` — the ledger fallback and the door chip.
- `apps/odrerir/src/App.tsx` — the `near` view and its door in the top bar.
- `apps/odrerir/src/hall.css` — the card anatomy in the hall's cloth (no new palette).
- `apps/odrerir/src/vendor/jev/` — `types.ts`, `policy.ts`, `LICENSE`, `VENDOR.md`.
- `bin/seat/{core-four,pending,context}.sh` — carried unchanged from `8aa77248`.
- `docs/features/near-loop.md` + its catalogue entry; this note.

### Verified (measured on this seat)

- `apps/odrerir`: `npm run build` → `tsc --noEmit` 0 errors, vite built. `apps/hlidskjalf`:
  `npm run build` green.
- The gate raised on `:3899`: `/api/core-four` `200` (cold `4.35 s`, warm `0.001 s`),
  `/api/context` `200`, `/api/pending` `200`, `/api/plans` `200` — `count: 149`, states read
  from the index (`97 opened · 16 proposed · 14 undeclared · 9 in progress · 5 open …`).
- Headless Chromium against the built hall (`#/near`): **16 cards**, shapes `headline ·
  brief · signal_alert`, chips `model · window · prompt · tools · decision · pi · worktrees`,
  actions `open · dismiss`, **0 console errors**.
- `#/plans` with Skuld silent: **149 rows**, chip `the ledger · 149 files`, 0 console errors
  — where the board previously said "no plans cut yet".
- `bash bin/records/weave-features.sh --check` → `FEATURES.md is current (171 entries)`.

### Owed, and named

- **No jev classification has been run**, so every card's score slot reads *Not ranked yet*.
  The vocabulary and policy are vendored and wired; the classifier pass is not, and a made-up
  score would be worse than the honest blank.
- The **pending door prints whole source lines**: one status file's vocabulary line and two
  rows of a quoted list arrive as "decisions". The door is not this change's to rewrite; it
  is the next one's.
- **Working now shows `no task named`** for every pane: the agents connector returns the pane
  and its state but not the errand's task.
- The `feat/near-loop-doors` overlap in `index.ts` above, when both land.

## CHANGE LOG

- **2026-11-06** — changelog section added at the merge so RULES/46 can read it.
