# The near loop — what is blocked on you, and the four dials

## What it is

The near loop is the operator's screen between *in the loop* and *out of it*. It
answers two questions on one page:

- **What is blocked on me?** — the open PRs, the wake queue, the mail drafts and
  the decisions the record itself marks as his.
- **What are this agent's four dials?** — the model, the window and both
  compaction thresholds, the prompt surfaces in force, and the tool count by
  source.

In the loop you prompt and wait. Out of the loop a trigger acts and you read the
outcome. **Near the loop the agent acts and you approve** — which only works if the
approving is one glance instead of five shelves.

It lives in **Óðrerir, the live hall** at `#/near`.

## What you need

- Ymir installed, and the gate API up (`:3889`).
- The three seat doors on the checkout:
  `bin/seat/core-four.sh`, `bin/seat/pending.sh`, `bin/seat/context.sh`.
- The hall raised for the screen itself: `scripts/start.sh` raises Óðrerir on
  `:4322`.

## Do it

Open the hall and follow the **the near loop** door in the top bar — or go
straight to it:

```
http://127.0.0.1:4322/#/near
```

The page reads four doors and paints three blocks. Every card names where its
fact came from, and every card has exactly two actions: **open** (the raw answer
from the door) and **dismiss** (hide it from this view — it changes nothing in the
record).

Ask a door yourself, without the screen:

```bash
bin/seat/core-four.sh            # the four dials
bin/seat/pending.sh              # what waits on him
bin/seat/context.sh              # this session's context
bin/seat/pending.sh --json       # the same, for a machine
```

And through the gate, for anything that speaks HTTP:

```bash
curl -s localhost:3889/api/core-four   # the four dials
curl -s localhost:3889/api/context     # this session
curl -s localhost:3889/api/pending     # what waits
curl -s localhost:3889/api/plans       # the plan ledger, read as files
```

## The plans board

The hall's plans board (`#/plans`) reads **Skuld** first — Skuld is the **write**
door, where a plan is created. When Skuld answers with no rows, the board reads
the **ledger** through `/api/plans` instead: one numbered file per plan, under
`$YMIR_HOME/svartalfaheim/<realm>/projects/ymir/plans/`.

That fallback exists because a board that said *"no plans cut yet"* while the
ledger carried every plan as a file was the bug. The board says which door
answered — `skuld · the book` or `the ledger · N files`.

Each plan's **state** is the one in the ledger's own `README.md` index row (the
last cell), as `bin/gates/plan-audit.sh` holds it; a plan with no index row falls
back to its own `Status:` line, and a plan that declares neither is shown as
`undeclared` rather than guessed. The retired `old-plans/` shelf is not read: its
numbers repeat the living ones.

## Notes and limits

- **It reads; it does not act.** Nothing on this page approves, merges, sends or
  starts work. *Dismiss* hides a card from your view only.
- **Scores are jev's.** The cards carry the Hype · Facts · Signal vocabulary
  vendored from `pi-durable-news-agent` (MIT). No classification has been run for
  these items yet, so a card says **Not ranked yet** instead of inventing a
  number.
- **A door that cannot answer says so.** Each block fills on its own, so one slow
  door never blanks the page; a failed door paints an *unread* card naming the
  door and the reason.
- **Working now is read, never started.** The agents and panes come from the
  gate's own `/api/agents`; the trees from `git worktree list`.

## If it does not work

| What you see | What to do |
|---|---|
| A block says *did not answer* | Run that door by hand — `bin/seat/core-four.sh --json`; the card names the door in its source. |
| The dials card shows `unset` | The harness settings name no model; check `~/.pi/agent/settings.json`. |
| The window is `—` | The model is not in the seat's registry and not in the catalog — `bin/model/catalog.sh --has <provider>/<model>`. |
| The plans board is empty | The ledger is empty or `YMIR_PLANS_DIR` is wrong; check `$YMIR_HOME/svartalfaheim/*/projects/ymir/plans/`. |
| `#/near` shows the old three doors | The hall is serving a stale `dist/` — rebuild: `cd apps/odrerir && npm run build`. |
