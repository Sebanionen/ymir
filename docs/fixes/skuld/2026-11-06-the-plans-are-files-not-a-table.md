## skuld · unversioned · 2026-11-06 — the plans are files, and the door was reading an empty table

**Measured on the heart, 2026-11-06.** `plans 0` in the `skuld` database — against **275 plan files** on the ledger's
shelves. `skuld_plans_list` answered `(no plans)`. The native `skuld_plan` tool read the files and answered ~156 rows from
the same shelf, so two surfaces existed: one true (the files) and one empty (the table), and the MCP — the surface the
Óðrerir board and any collaborating agent reaches — was the empty one.

**Why it happened, in one line of doctrine.** Fix note `agents/0.1.80` ruled that the ledger is the home's and is *not
re-implemented in Skuld*. The door then grew a `plans` table beside it, and nothing ever wrote to it: `plans_create` was
reachable, correct, and never called, because a plan is opened as a FILE (`bin/records/plan.sh`, the `ymir_plan` door).

**What changed.**

```
change[4]{surface,today,why}:
  "plans_list","reads the ledger's shelves and answers `plans[222]{number,namespace,status,file,title}`","the row a reader needs is already in the file's first lines; a table only repeats it"
  "plans_get","one plan, by number: its file, status, and the opening of its body","the file IS the plan — pointing at it is honest, copying it is not"
  "plans_pending","the plans whose own first lines say proposed, drafted, open or awaiting","'waiting on him' was a status list in a table; it is a fact in the text"
  "plans_create","REFUSES, and names the one door that writes a plan","Rule 06: a record is appended and carried; a table is not a record (plan 210 §6)"
```

The reader is its own module — `tools/tickets-mcp/ledger.mjs` — so it can be proved with **no client and no SDK**:

```
node tools/tickets-mcp/ledger.mjs             # plans[222]{…}  → exit 0
node tools/tickets-mcp/ledger.mjs --pending   # only the ones that wait his word
```

The namespace is `realm/project` for the ledger (`whynotproductions/ymir`) and `hodd` for the home's own shelves — the
shelf path's `projects/` and `thoughts/` are scaffolding, never a namespace.

**The block, told the truth.** `blocks_status` now answers with the reason, **which three verbs it stops**
(`tickets_create` · `tickets_update` · `namespaces_create`) and who may lift it, on one line. This corrects a belief the
house held all day: the block never stopped `plans_create` or `comments_post`, so it was never the explanation for the
empty table — a gate that claims more than it does is worse than no gate (plan 210 §10).

**Left deliberately, and named.** The Óðrerir board's blocked-state chip (`apps/odrerir/src/skuld.ts`) is not in this
change: the door now answers with a shape the board can render, but the board's build is its own app and its own errand.
Identity, tenant and the door's token (plan 210 P2–P4) are untouched: `agentOf()` is still the literal `brokk`, so nothing
here should be read as multi-tenancy.

**Proved by:** `node --check` on both files; the ledger module answering **222 plans** against the same home that the table
called empty; `bin/gates/guards.sh` on the branch; registers current after `bin/gates/registers.sh generate`.

## CHANGE LOG

- 2026-11-06 · the MCP's plan tools read the ledger through `ledger.mjs`; `plans_create` refuses the second store and
  names the door; `blocks_status` names the verbs a block really stops.
