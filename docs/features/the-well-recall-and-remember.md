# The well — recall and remember

## What it is

**Mimirsbrunn** is Ymir's long‑term memory — the well. It is one store, in the hoard,
that remembers what happened and hands it back when it matters: **drink before you
act, water it after.** Every session can recall decisions, and record what it learned,
so the next session starts smarter than the last.

## What you need

- Ymir installed. The memory engine (engram) is provisioned by the installer /
  `bin/engine/prereq-ensure.sh engram`.

## Do it

```bash
# is the well reachable?
bin/records/mimir.sh health
```

**Recall** — ask before you act:

```bash
bin/records/mimir.sh recall "why did we stop using the old model rail" --k 5
bin/records/mimir.sh recall "vault key design" --mode hybrid   # hybrid | cosine | spreading
```

**Record** — water it after:

```bash
bin/records/mimir.sh observe "Mjollnir never force-merges; Glitnir holds the seal" \
    --tags mjollnir,gate --store semantic --shape decision --task "delivery gate"
```

**The gate says no, sometimes.** Before anything is stored the well asks three
questions: does this change future behaviour, is it a commitment with consequences,
or is it a decision with rationale? If none of the three, the write is **dropped**
and you are told why. That is the feature, not a failure — a memory that keeps
everything cannot be trusted about anything. State which question you are answering
with `--shape behaviour|commitment|decision`, and which shelf it belongs to with
`--store episodic|semantic|procedural`. Secrets are refused outright, and the vault
never enters the well.

**Ask a narrower question** — pick the shelf and the window before you search:

```bash
bin/records/mimir.sh recall "why the write gate" --store semantic --since 2026-10-01
bin/records/mimir.sh recall "smoke test" --tag domain:smoke --k 8
bin/records/mimir.sh recall "the shelf rule" --task "memory policy"   # what this work taught
```

**Correct and retract** — append, never overwrite:

```bash
bin/records/mimir.sh correct <episode-id> "the gate asks three questions, and dedupes first"
bin/records/mimir.sh retract <episode-id> --why "that script moved to bin/smoke_test.sh"
bin/records/mimir.sh why <episode-id>        # the chain, both ways
```

The original stays in the record, annotated void, and recall stops handing it back as
fact. Nothing is ever deleted (Rule 20).

**Let memory forget** — grading, nightly and on demand:

```bash
bin/records/mimir.sh grade            # report: nýr · eldri · forn · safn, and overlaps
bin/records/mimir.sh grade --apply    # decay, annotate duplicates, archive expired, move superseded docs
```

**Is the memory healthy?** — one row: size, last observe, last recall, last daily
entry, last grading run. Eir carries it as the `memory` surface.

```bash
bin/records/mimir.sh memory            # the whole picture
bin/records/mimir.sh memory --line     # one line (what Eir prints)
```

**Walk the timeline** — a thing's history, in order:

```bash
bin/records/mimir.sh timeline --entity vault
```

### The bridge (so agents can recurse)

The engine lives behind a bridge on `:4602`; agents reach it as the `engram` MCP
(recall/observe) rather than shelling out:

```bash
bin/bridge/mimir-bridge.sh --start     # raise the bridge
```

## Notes and limits

- **One well, and it lives in the hoard.** The store is
  `$YMIR_HOME/hodd/memory/kaia.engram` — never in the code tree (Rule 04). Everything
  resolves it through `bin/vault/hoard-lib.sh`.
- **The gate is not advisory.** A dropped write is a normal answer; observe exits 3
  and prints the reason. `--force` bypasses the three questions only, and the record
  shows it was forced. Secrets and confidential material cannot be forced past.
- **Grading never lowers the count.** It annotates and moves; a run that loses an
  episode is reported as a failure. Near-duplicate consolidation is proposed, not
  performed — merging two memories by machine makes a new, invented one.
- **The nightly pass needs a backup first.** `--apply` runs in Nornir's memory job
  only after that night's snapshot succeeded; without it the pass reports only.
- **Recall is not authority.** The well returns what was *recorded*; if it conflicts
  with the code or the operator, the code and the operator win. The well is memory,
  not law.
- **Nothing confidential is watered in.** Vault content never enters the well (Rule 15)
  — a confidential session points `ENGRAM_DB` at the session, not the well (Rule 16).
- With the bridge up, agents should prefer the MCP tools; `mimir.sh` is the same well
  from the shell.

## If it does not work

| What you see | What to do |
|---|---|
| `health` fails | Raise the bridge: `bin/bridge/mimir-bridge.sh --start`; check the engine is provisioned with `bin/engine/prereq-ensure.sh status`. |
| Recall returns nothing | The well is young, or nothing matched — observe a few facts first, or widen `--k`. If you passed `--store`/`--tag`/`--since`, the slice may be empty: retry without the filter to see which. |
| `observe` exits 3 and says "dropped" | The gate refused it. Say which question it answers (`--shape`) or make it a real lesson; a write that commits to nothing is not memory. |
| `memory` says "grading has never run" | `bin/records/mimir.sh grade --apply` (it may also be Eir's `memory` surface, mended with `bin/agents/eir-doctor.sh fix`). |
| An agent cannot recall | The `engram` MCP is not wired for its harness — re‑run the memory surface: `bin/agents/eir-doctor.sh fix` (the `well`/`mcp` surfaces). |


## Codex using a selected WSL well

When Codex runs on Windows and the chosen well runs in WSL, the private Codex
home can contain `hodd/data/codex-well.json`. Set `route` to `wsl`, `distro` to
the installed WSL distribution, and `root`, `home`, and `store` to the Linux
Ymir checkout, private home, and exact database. These values are private and
should not be added to the public Ymir repository. The Codex adapter starts
the selected distribution's user service and verifies the returned store before
each memory call. If the service is unavailable, it reports an error instead of
writing an offline record to the other home. Create an empty sibling file
`codex-well.required` before writing the JSON file: it makes a missing or invalid
configuration fail closed and refuses a non-WSL route. If neither file exists,
the existing local behavior applies. Existing Windows and Linux records are not merged.

Optional string fields `service` and `url` choose a systemd user service and a
loopback HTTP origin. Environment variables override the corresponding fields;
their names and the full contract are in the Codex harness asset. After updating
the plugin, open a new Codex session to load its changed tool code.
