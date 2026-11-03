# The Well — Mimirsbrunn (engram) memory, bridge, and harness wiring

> **Purpose:** Everything an agent must know to operate, extend, or rebuild
> Ymir's memory: the store, the HTTP bridge, the MCP server, the harness
> registrations, the laws, and the UI. The **code is authoritative**; this page
> explains the whole of it.

The well is **Mimirsbrunn**, backed by the validated OSS engine **engdbram**
(`pip install engdbram`) — the *module* it provides is `engram`.

> **The name trap.** PyPI's `engram` is an unrelated *rendering* library
> (mitsuba/drjit/torch). Installing it pulls gigabytes of CUDA wheels and still
> leaves Ymir with no memory engine. The distribution is **`engdbram`**;
> `bin/engine/prereq-ensure.sh engram` installs the right one. It is **one repo-local store** shared by every agent and
every harness. Motto: **drink before you act, water it after** — recall on the
way in, observe on the way out.

---

## 1. Components

| Component | Path | Role |
|---|---|---|
| Store | `$YMIR_HOME/hodd/memory/kaia.engram` | THE single SQLite memory (episodes, facts, entities) — one well, always in the hoard (Rule 04/07); resolved via `hoard_memory_store` (hoard-lib) or the `ENGRAM_DB` override |
| Append log | `.agents/memory/well/episodes.jsonl` | the raw episode log (source of truth for re-seeding) |
| HTTP bridge | `bin/bridge/mimir-bridge.py` (+ `bin/bridge/mimir-bridge.sh`) | the `:4602` face over the engram library |
| CLI | `bin/records/mimir.sh` | operator CLI: `health` `recall` `observe` `timeline` |
| Ingest | `bin/records/mimir-ingest.sh` | drinks a directory into the JSONL well + bridge |
| Gate API | `apps/hlidskjalf/server/index.ts` | `/api/well`, `/api/well/episode`, `/api/mimir/health` |
| UI | `apps/hlidskjalf/src/gates/Well.tsx` + `components/RecallPanel.tsx` | recall panel, timeline, click-to-read |
| MCP server | `engram-mcp` (console script) | stdio MCP: `remember` `recall` `why` `forget` `stats` |

The upstream engine ships a **CLI + MCP stdio server only** — there is no
`engram.server` HTTP module. `bin/bridge/mimir-bridge.py` is Ymir's own face, because
the gate API, `mimir.sh`, and `mimir-ingest.sh` speak HTTP on `:4602`.

`bin/records/mimir-ingest.sh` loads every stored hash once into an associative array, so
dedupe is O(1) per section rather than rescanning the whole store each time (was
O(sections × store)); `bin/records/workspace-rag.sh index` reads the store once and walks
all files in a single Python pass (was a store read + process spawn per file).

**Where ingest reads from.** Its source is the hoard's `docs/business`, and the
hoard root resolves through `bin/vault/hoard-lib.sh` (`$YMIR_HOARD`, else `$YMIR_HOME`,
else `$HOME/Documents/ymirhome`) — the same one default every other script uses, and
never the repo's `hodd/`, which holds only the guard, README and `*.example`
scaffolds (Rule 04).

---

## 2. HTTP bridge (`:4602`)

Raised by `bin/bridge/mimir-bridge.sh --start`; also raised by `scripts/start.sh` and
`bin/time/saga-session-start.sh`, so it is up whenever the stack is up.

```
GET  /health                 -> {status, store, episodes, agents}
GET  /recall?q&k&mode        -> {results:[{score, distance, importance, episode}]}
GET  /recent?limit           -> {episodes:[...]}
GET  /episode?id=<id>        -> {episode:{id, content, timestamp, tags, actors, agent_id}}
GET  /timeline?entity        -> {facts:[...]}
GET  /inspect                -> {store, episodes, agents}
POST /observe {content,...}  -> {id, agent_id, episodes}
```

Mode is `hybrid` (default) | `cosine` | `spreading`. The bridge is **read-all**
by default (an unscoped `Engram`), so recall sees every episode regardless of
which agent wrote it.

---

## 3. MCP for harnesses (the shared well)

`engram-mcp --db $YMIR_HOME/hodd/memory/kaia.engram` — **unscoped**, so
every harness reads the one well. (A scoped `--agent-id` filters reads to that
agent and would hide the seeded `well` episodes; pass `agent_id` per `remember`
call instead when attribution is wanted.)

| Harness | Config | Notes |
|---|---|---|
| OpenCode (4 accounts: `opencode`, `opencode-rd`, `opencode-work`, `opencode-oczer`) | `<config-dir>/opencode.json` → `mcp.engram` | `{type:"local", command:["engram-mcp","--db",…], enabled:true}` |
| Pi | `~/.pi/agent/settings.json` → `mcpServers.engram` **and** `~/.pi/agent/mcp-adapter.json` + repo `.pi/mcp-adapter.json` (pass `pi --mcp-config .pi/mcp-adapter.json`) | pi-mcp-adapter. **Scope:** `bin/bridge/a2a-mcp.sh install` writes the GLOBAL `~/.pi/agent/mcp-adapter.json`; `install --project` writes the repo's `.pi/mcp-adapter.json` instead and never touches `~/.pi` — use it when Pi is run in other areas. |
| Claude Code | `~/.claude.json` → `mcpServers.engram` | |
| Cursor | `~/.cursor/mcp.json` → `mcpServers.engram` | |
| Codex | `~/.codex/config.toml` → `[mcp_servers.engram]` | args are a TOML array |

**Hard dependency:** `engram-mcp` needs the **`mcp<2`** SDK (mcp 2.x renamed
`FastMCP`→`MCPServer` and breaks engram 1.x/2.x):

```
python3 -m pip install --user --break-system-packages 'mcp<2'
```

---

## 4. Laws

```
well_laws[6]{id,law}:
  1,"No mock data — the well holds only true observations; test writes are purged"
  2,"Drink before you act — recall on the way in; never answer the Allfather dry"
  3,"Water it after — observe a lesson once it lands"
  4,"Hoarded — the store is $YMIR_HOME/hodd/memory/kaia.engram (one well, never a duplicated migrated copy)"
  5,"One well — every harness shares it; scope per-call, never per-server"
  6,"One resolver — the bridge resolves the home through bin/vault/hoard-lib.sh; a private default is refused by bin/gates/guards/defaults-guard.sh (2026-09-24)"
```

Words that *discuss* mock data (docs about removing mocks) are real knowledge
and stay; entries that *are* test/mock are removed.

---

## 5. Operate & verify

```
bin/bridge/mimir-bridge.sh --status          # well[1]{port,status}: 4602,"up"
bin/bridge/mimir-bridge.sh --foreground      # run under a supervising unit (mimir.service)
bin/records/mimir.sh health                   # WARM/COLD + entry count + online
bin/records/mimir.sh recall "sales pipeline"  # semantic recall (bridge) with local fallback
curl -s localhost:4602/health         # {"status":"up","episodes":367,"agents":["well"]}
curl -s 'localhost:4602/episode?id=<id>'   # full memory text
```

Re-seed the store from the JSONL well (idempotent spirit; dedupe by hash):

```
python3 - <<'PY'
import json
from datetime import datetime
from engram import Engram
eng = Engram(path="~/Documents/ymirhome/hodd/memory/kaia.engram", agent_id="well")
for l in open("~/Documents/ymirhome/hodd/memory/well/episodes.jsonl"):
    if not l.strip().startswith("{"): continue
    e = json.loads(l); ts = e.get("timestamp")
    when = datetime.fromisoformat(ts.replace("Z","+00:00")) if ts else None
    eng.observe(e["content"], actors=[e.get("source","well")], tags=e.get("tags",["well"]), timestamp=when)
PY
```

---

## 6. UI

The **Well** gate (`#/well`) shows live metrics (episodes, bridge state from
`/api/mimir/health`) and a real timeline derived from episodes. Each recalled
episode is **clickable** — `RecallPanel` calls `onOpen(id)`, `Well` fetches
`/api/well/episode?id=` and opens the full memory text in a modal. The old
hardcoded timeline is gone.

---

## 7. Troubleshooting

- **MCP recall returns `[]`** → the server is scoped (`--agent-id`); drop it for
  the shared well.
- **`ModuleNotFoundError: mcp.server.fastmcp`** → mcp 2.x installed; pin `mcp<2`.
- **First `observe` slow (~20–30 s)** → the embedding model is warming; later
  writes are instant.
- **Bridge down / `COLD`** → `bin/bridge/mimir-bridge.sh --start`; on a dev seat the
  mend is `systemctl --user restart mimir.service`; check
  `$YMIR_STATE_DIR/mimir-bridge.log` — runtime state lives in the home the
  operator chose (`hoard_state_dir` via `bin/vault/hoard-lib.sh`), never in the code
  tree: a packaged install replaces its tree on upgrade.

**Portability.** The bridge signals processes through `ymir_kill_matching` from
`bin/fleet/ymir-platform.sh` rather than calling `pkill` directly, because `pkill` is
absent on some MSYS/WSL images (Rule 05, one place knows the difference).

---

## 8. The log is the truth; the engram is derived (2026-10-12)

**Appended — the shape above still holds; this names which artifact carries the
memory across machines.** The fleet's wells had forked: the heart published its
engram and no seat pulled it, while every seat's bridge wrote its own local index.
The law is now explicit.

```
truth[3]{artifact,role,merges_by}:
  "hodd/memory/well/episodes.jsonl","the append log — the durable, unionable record","union (text, hash-deduped)"
  "hodd/memory/kaia.engram","a derived, PER-SEAT index rebuilt from the log","never — export -> union -> reseed"
  "hodd/memory/runes_audit.md","the chained ledger — it has its own fusion process","quarantine + ONE ledger.fusion entry"
```

**Every observe reaches the log.** `bin/bridge/mimir-bridge.py` appends each
observation (full record, hash-deduped) as it writes the store. The bridge is the
one door every harness passes through (`pi`, `opencode`, `claude`, `cursor`, `codex`),
so the log is complete by construction — before this, only `mimir.sh` and
`mimir-ingest.sh` appended, and the log held 5 lines against 101 episodes.

**`bin/records/mimir-log.{py,sh}` — the reconciliation, both ways:**

```
mimir-log[4]{verb,direction,meaning}:
  "export","engram -> log","append every episode the log lacks (hash-deduped)"
  "reseed","log -> engram","observe every record the index lacks (hash-deduped)"
  "union","other -> log","append another log's records we lack — APPEND-ONLY, never a rewrite"
  "verify","both counts","the gap that must be zero"
```

**`bin/time/well-vault-sync.sh`** rides only the log. `--mode push` exports then
publishes it; `--mode pull` exports this seat's memory, unions origin's log, and
re-seeds the local index. `--mode sync` is both. The binary engram is never
git-merged, and a pull that would overwrite a dirty tracked file is *refused* —
so a seat's memory is never lost. Because the whole log rides the vault, **a seat
holds the whole memory with the heart down**, and publishes its own when the heart
returns: the heart is the main port, never a single point of failure.

**One interpreter.** `bin/bridge/mimir-bridge.sh --python` prints the resolved
engram interpreter; `mimir-log.sh` calls it, so the log tool and the bridge never
disagree about which python owns the store.


## The law the well obeys: IT APPENDS (2026-10-17)

**Appended at the Allfather's word:** *"the well must always append only."* The rule
is `RULES/20-the-well-appends.md`; the ward is `bin/records/well-guard.sh`.

```
well_law[4]{rule,meaning}:
  "APPEND, never replace","an episode is written once and stays. No rebuild, no regenerate, no recover-over, no resync in place."
  "A SECOND TRUTH IS A LOSS","two wells fork into a UNION — every record from both is appended. `resync` on a well means append, never overwrite."
  "REPAIR ADDS, IT DOES NOT SUBTRACT","a corrupt store is preserved as found; recovery APPENDS beside the live one; what cannot be read is recorded as a known gap."
  "THE COUNT NEVER FALLS","the episode count and the log's line count are monotonic. A run that lowers either is a failure, not a tidy-up."
```

**Why it is law, not preference — the incident:** on **2026-10-07** the store was
malformed (`btreeInitPage() error code 11`). It was preserved by hand and salvaged
with `sqlite3 .recover`, which keeps only the pages it can read: **134 episodes became
98 — 36 lost.** Sixteen were later restored from `git` (the 2026-09-28 blob); twenty
(date-range 2026-10-04..06) existed nowhere else. **Nothing noticed for ten days** —
the store had shrunk by a third and the loss rode the vault. The missing ward, not the
missing tooling, is what this asset and Rule 20 make impossible to repeat.

**What is permitted:** appending; appending a fork's missing records (the log union);
restoring a lost episode from git or another seat (with provenance tags); annotating an
episode — a tag — without touching its content; removing an episode from a **derived**
index (a vector row, an FTS row) while the record stays.
**What is forbidden:** deleting an episode; rebuilding the store from a subset;
restoring an older snapshot *over* a newer one; `git checkout` of the binary store over
a live one; a "merge" that picks one side.

**The ward (`bin/records/well-guard.sh`):**

```
well-guard[3]{verb,what,exit}:
  "check","episode count and log lines against the checkpoint, junk content (empty or `undefined`), episodes with no vector","1 on any loss, junk or unindexed row; 1 when the store cannot be read at all"
  "record","roll the checkpoint forward AFTER a passing check","1 when the check fails (never records a loss as the new normal)"
  "--self-test","build a temp well, record, check, remove one episode, prove the ward bites","0 when the ward bites"
```

A row declared void by an appended correction (tag `void:…`) is counted as *recorded*,
not as junk — the record keeps it, the ward does not nag about it, and the episode is
excluded from the vector index so it cannot be recalled as fact.

Eir composes it as the `well` surface, so a loss is reported the next time anyone
diagnoses the house; `check` rides `record` after a passing run, so the checkpoint
follows a healthy well forward.


## The policy: gate · types · provenance · corrections · forgetting (2026-10-26, plan 136)

**Appended.** The store, the bridge and the log above are unchanged — what changed is
that the well now has a *practice* written in code. A memory that accepts everything,
keeps nothing worth trusting, and one never pruned becomes noise, and noise is the
enemy of recall. Five faces, one module:

| Component | Path | Role |
|---|---|---|
| **Policy** | `bin/records/mimir-policy.py` | the gate, the type route, the provenance record, the correction chain, the grading pass — **stdlib only**, so it answers with the bridge down and the engine unimportable |
| **CLI** | `bin/records/mimir.sh` | `memory` · `observe` · `recall` · `correct` · `retract` · `why` · `grade` · `policy` (plus the old `health`/`timeline`) |
| **Session recall** | `bin/records/mimir-recall-today.sh` | the opening recall, keyed to the day's stated topic (called by Sága) |
| **Test** | `.agents/tests/well-policy.test.sh` | 21 checks on a **throwaway** well: gate drops/keeps, types, dedupe, scoping, chain, grading, health |
| **Ward** | `bin/records/well-guard.sh` | unchanged — it already counts `void:` rows as recorded, not junk |

### 1. The gate — three questions before anything is stored

```
gate[3]{question,why}:
  "does this change future behaviour?","a lesson, a rule, a documented workflow — the memory that pays for itself twice"
  "is this a commitment with consequences?","a promise, a debt, a deadline — what the next hand is owed"
  "is this a decision with rationale?","what was chosen and why — the one thing a later self cannot reconstruct"
```

A write that answers **none** is **dropped**, and the drop is the answer (HTTP 200,
`stored: false`, with the reason). A gate is not a warning. The questions are answered
by **declared shape** (`shape=behaviour|commitment|decision`, a claim the writer makes
and the record keeps) or by signal words (`SIGNALS` in the policy) — never by a model.
Two hard refusals sit before the questions: **secret-shaped content** (Rules 15/24) and
the **vault / confidential / restricted** privacy classes (Rules 15/16). `--force`
bypasses the questions and is recorded as forced in the provenance.

The write path then **canonicalizes** dates to ISO-8601 and clocks to 24-hour, resolves
`today/yesterday/tomorrow` to absolute dates (a memory that says "yesterday" is
unreadable the day after), canonicalizes names (`Deck`, `deck ` → `deck`), collapses
whitespace, and reports every change it made. Then it **deduplicates** — byte-for-byte
by hash, and near-duplicate by content-word Jaccard ≥ 0.85 — and **scores** by novelty
(unlike the rest of the well) and relevance (overlap with the stated `task`), which
becomes the salience when the caller did not state one.

### 2. Three typed stores — the shelf is chosen at write time

```
stores[3]{shelf,holds,example}:
  "episodic","an event in time","'ran the smoke test at 09:00, it passed'"
  "semantic","a stable fact or preference","'the well lives in the hoard; there is one well'"
  "procedural","an instruction or workflow","'step 1: raise the bridge, then run the smoke test'"
```

The shelf is inferred from the text (workflow markers → procedural, rule/fact markers →
semantic, else episodic) or declared by the caller, then **stamped as a tag**
(`store:semantic`). Tags, not a new column: every existing reader — the CLI, the UI, the
MCP server, a `grep` on the log — sees the shelf without being taught a new field.

### 3. Provenance — what rides with the words

```
provenance[6]{tag,means}:
  "src:<name>","the hand that wrote it (canonicalized)"
  "scope:<name>","the reach — house by default"
  "conf:<0..1>","how sure the writer was"
  "privacy:<class>","public | internal | private (untrusted marks the episode quarantined)"
  "retain:keep|season:<days>|ephemeral","when it may be archived"
  "task:<slug>","the work it belongs to, when one was stated"
```

The engine's own `provenance` column holds only its three words
(`('user','tool','external')` — it raises on anything else, measured, not guessed) and
`quarantined` marks content written after the writer had read untrusted material. The
rich record rides in **tags** because the engine refuses the rest, and `bin/records/mimir-log.py`
carries both through `export`/`reseed` so a re-seed restores the words **and** the trust.

### 4. Scoped recall — the shelf before the search

`GET /recall` takes `store=`, `tag=`, `since=`, `until=`, `agent_id=` and builds the
**slice** from the store first; the similarity search then ranks only what is already on
it. A **voided** episode is never returned (that is what a correction is *for*), and an
**archived** one only with `include_archived=1`. If the vector index has not caught up,
the tail of the answer is filled by word overlap **inside the same slice**, so "not
indexed yet" and "never recorded" stop being the same lie.

```
bin/records/mimir.sh recall "the write gate" --store semantic --since 2026-10-01
bin/records/mimir.sh recall "smoke test" --tag domain:smoke --k 8
```

### 5. Correction and retraction — append, chain, never erase

```
bin/records/mimir.sh correct <episode-id> "<what is true now>"
bin/records/mimir.sh retract <episode-id> --why "it moved to bin/smoke_test.sh"
bin/records/mimir.sh why <episode-id>          # the chain, both ways
```

The replacement carries `corrects:<original>` (or `retracts:<original>`, or
`consolidates:<original>`), and the **original gains one tag**, `void:<replacement>`. Its
content is never touched. This is Rule 20: *repair adds, it does not subtract* — and the
ward already treats a `void:` row as recorded rather than junk. Never `forget()`: the
engine's `forget` hard-deletes, which is exactly what the well must not do.

### 6. Continuous forgetting — grading is a pass, not a quarterly event

`bin/records/mimir.sh grade [--apply]` — run nightly by
`bin/time/nornir-job-memory-housekeeping.sh` (Nornir, `@heart 00:15`), report-only when
the night's backup failed.

```
grades[4]{grade,meaning,action}:
  "nýr","changed or read in the last 14 days","the live edge — nothing to do"
  "eldri","still in play, not of late","nothing to do; it is not stale, it is quiet"
  "forn","old: superseded, or long unread, low weight","a consolidation candidate; REPORTED, never merged by a script"
  "safn","archived on purpose","read on purpose, never by accident"
```

What `--apply` does, in order: **decay** every episode's importance by recency and
access frequency (the engine's own `run_decay`, called **unscoped** — a scoped instance
only rescored its own keeper's rows, measured); **annotate** exact duplicates `void:`
against the copy that stands; **archive** episodes whose retention rule expired
(`retained:ephemeral`, `season:<days>`); and **move a document** to `hodd/reference/`
**only when the document itself declares `superseded_by:`** — a guess is not a reason to
move a record, and the runes, the operator record and the learnings are never moved. The
episode count is checked before and after: **a run that lowers it is recorded as a
failure** (Rule 20), never as a tidy-up. Near-duplicate overlaps are *reported* as
candidates: a summary written by a machine is an invented fact, so consolidating them is
a keeper's act.

### 7. The memory row — what Eir reports

`bin/records/mimir.sh memory [--line|--json|--check]` measures the practice, not the
port: **well size**, **last observe**, **last recall** (from the access log — the bridge
flushes it after every recall), **last daily entry**, **last grading run**, and how the
three shelves divide. Eir's `memory` surface is `mimir.sh memory --check`; it is red when
the store is unreadable, holds nothing, has not been written to in 30 days, has not been
graded in 45, or is accumulating with no daily entry for a week. `fix` raises the well and
runs the grading pass; it will not invent a daily entry.

### 8. The opening recall — drink before you act

Sága's `RECALL` section calls `bin/records/mimir-recall-today.sh`, which asks about the
day's **stated** topic — `$STATE/.session-topic` (one line), else the newest bullet in
today's daily log, else the newest open forge order — scoped by the last 14 days. No
topic, no guess: it says so and prints how to state one. The answer ends with the law:
*recall is memory, not authority.*

### 9. The operator record stays true (a practice, not a script)

`$YMIR_HOME/hodd/data/operator.md` is read at every session start. When a preference,
working style or standing rule **changes**, rewrite and prune it **in the same pass** —
never append a contradiction below the old claim. A stale preference makes the next hand
confident about something that is no longer true, which is worse than silence. This one
cannot become a script (it needs judgment about what still holds), so it is written here
as law for the keeper: *when a preference moves, the operator record moves with it, and
the moved claim is deleted, not layered.*

---

## 6. Two roads, one well (2026-10-28)

The bridge was one command with one road, so the well was dark on every `hand`: `--start` resolved an
interpreter, tried `import engram`, and exited 1 — and a clean skip in `prereq-ensure.sh` had been counted
as a pass (RULES/25's 2026-10-28 section is the correction).

**One verb, the role's own road.** `bin/bridge/mimir-bridge.sh --start`:

| What the box can do | What `--start` does | What it prints |
|---|---|---|
| `import engram` works | serves the engine, as before | `4602,"<store>","started"` |
| no engine, ssh reaches the heart | raises the door (`bin/records/well-door.sh up`: `4602` HTTP + `8317` MCP) | `4602,"door","borrowed from the heart"` |
| no engine, no door | refuses with the repair | `no local engine under <py>, and the door to the heart did not answer` / `help: bin/records/well-door.sh status` |

`--status` names the road: `up (local)` when this box owns the process (pid file alive), `up (door)` when
something else serves the port, `down` when nothing does. `--stop` closes a borrowed door through
`well-door.sh down`, so no ssh forward outlives the well it served.

**The door's own honesty.** `bin/records/well-door.sh status` probes BOTH ends per port and says which of
four states it is in — `answering`, `not raised (heart listens)`, `forward up, but NOTHING behind it`,
`silent both ends`. A forward with nothing behind it is the silent door this house has been burned by.

**Never a second table.** The heart is `YMIR_HEART` (default `zerwizserver`) and `WELL_HEART_HOST` (default
`127.0.0.1` behind it) — configuration, resolved (Rule 07). The store stays one file in the hoard on the
heart; a hand holds no second well.

**Proof:** `.agents/tests/well-door.test.sh` (6 assertions — borrowed door, owned process, silent port, and
the named refusal). How-to for a person: `docs/features/the-well-on-every-role.md`.

## Memory health across platform and borrowed boundaries (2026-11-02)

`mimir.sh memory` queries the active bridge through the policy's `memory --bridge
<url>` path. The serving process owns the SQLite file and WAL; a WSL or borrowed
client must not substitute its own local file as evidence of the server's health.
JSON identifies `measurement=bridge`, or `local-file` when offline. Bridge errors
and incomplete policy records fail closed; the server's `healthy=false` remains
an exit-1 check. This changes no memory content or storage format.

Validation: `bin/records/test_mimir_bridge_health.py`, policy self-test, and shell
syntax. Operator instructions: `docs/features/the-well-on-every-role.md`.
