## records · 2026-11-06 — the well's index was malformed; its memory was whole, and the log proved it

### Why
Session start on heimdall reported `well bridge: not up` and the door answered
`[ymir-well] the well did not answer (0): fetch failed`. The bridge log named the real fault, and it was not a
bad launch:

```
sqlite3.DatabaseError: database disk image is malformed
  bin/bridge/mimir-bridge.py:193 → engram/core.py:163 migrate(...)
```

`PRAGMA integrity_check` on `hodd/memory/kaia.engram` (2,564,096 bytes, mtime 2026-11-06 04:32) reported
corrupt tree pages — page 26 cells pointing at pages 702–734, which do not exist in a 313-page file. The store
could not be opened at all, so every reader of the well — the bridge, the session digest, `ymir_recall` — was
blind. Found while the Allfather was reading the failed `herdr update`, not by any ward: `well-guard` had not
been checked since 2026-10-17.

### The law this file lives under
`RULES/20-the-well-appends.md`. The engram is DERIVED. The append log
`hodd/memory/well/episodes.jsonl` is the truth, and the bridge writes every observe to it before the index
(`bin/bridge/mimir-bridge.py` §"the append log … is the source of truth for re-seeding"). So the repair is a
**rebuild of the index from the log**, never a salvage of the store, and nothing is deleted.

### Proof that nothing was lost, taken before anything moved
- `sqlite3 kaia.engram ".recover"` into a throwaway copy (`/tmp/sal`) yielded **112 episodes**, every one of
  them present in the log by content hash (sha256 of content, the same digest `bin/records/mimir-log.py:56`
  uses) — **zero store-only episodes**, so the corrupt file held nothing the log lacked.
- The log held **218 lines / 210 unique hashes**, i.e. **98 episodes the store no longer had at all**.
- All 218 lines parse as JSON: `ok 218 bad 0`.

### Mend
1. **Preserved, not deleted.** The corrupt store and its sidecars moved aside inside the hoard:
   `hodd/memory/well/stale-kaia-corrupt-20261106T1313Z.engram` (+ `-shm`, `-wal`). The hoard gained a
   `.gitignore` rule so a preservation copy can never be swept into the vault's commits.
2. **A fresh index.** `bin/bridge/mimir-bridge.sh --start` recreated `hodd/memory/kaia.engram` through
   `engram`'s own `migrate`; `--status` answered `4602,"up (local)"`.
3. **Re-seeded from the log.** `bin/records/mimir-log.sh reseed` → `observed=210, already=8` in 55 s
   (the 8 are the log's duplicate-content lines; dedupe is by hash).
4. **The junk row, voided not erased.** One pre-existing episode carried the literal content `undefined`
   (`a71e4316-…`, agent `well`, 2026-10-03) — a caller that serialised a missing field. It was tagged
   `void:junk-untyped-caller` + `archived:2026-11-06` through the bridge's own `annotate()`, the only edit
   Rule 20 permits. The content is untouched; it simply leaves recall.
5. **Checkpoint rolled forward.** `bin/records/well-guard.sh record` → `210 episodes, 218 log lines`, from a
   checkpoint of `121 episodes, 100 log lines` (2026-10-17).

### Proven
- `bin/records/mimir-log.sh verify` — `log 210, engram 210, missing_from_log 0, missing_from_engram 0`.
- `bin/records/well-guard.sh check` — `whole (210 episodes, 218 log lines)`, junk `0`, unindexed `0`.
- `GET /health` — `episodes: 210`, `stores {episodic 164, semantic 16, procedural 30}`, `healthy: true`.
- `bin/records/mimir.sh recall "the well was rebuilt from the append log"` — `retrieval: bridge`, five scored
  episodes. The semantic index answers, not the lexical fallback.

### Owed / found on the way
- **The ward is not on a schedule.** A store can rot for 20 days with every door blind and no alarm; the
  checkpoint lives in the hoard's ignored `state/` and nothing runs `check` on a cron row. It belongs in Nornir.
- **The repo's `state/well-guard.json`** still reads the 2026-10-17 checkpoint; the live one is the hoard's.
  Two checkpoint files that disagree is exactly the stale-map fault RULES/07 forbids.
- **A void tag does not ride the log.** `reseed` dedupes by content hash, so a re-seed of a wiped store
  resurrects the junk row without its `void:` tag. Durable remedy is a log line carrying the void, or the
  gate refusing `undefined` at write time — the second is the real fix.

### Appended — the write door was broken too, and the rebuild hid it
The rebuild restored recall, and a probe then found that **no write reached the index at all**:

```
POST /observe → {"error": "Engram.observe() got an unexpected keyword argument 'provenance'"}
```

`bin/bridge/mimir-bridge.py:_write` calls the engine with `provenance=` and `quarantined=`, and the installed
engine is **engram 2.2.1** (the operator's user site-packages, installed 2026-10-02), whose
`observe()` takes only `content, actors, tags, salience, emotional_valence, timestamp`. So every write through
the door raised, `bin/records/mimir.sh` fell back to its offline path, and memory kept arriving **in the log
only** — the well was read-only in practice, and `GET /health` looked healthy because it counts what is stored.
`bin/records/mimir-log.py` had already learned this lesson for re-seeding ("ask the signature instead of
assuming a release — 2026-11-01"); the bridge had not.

One paragraph observed through the CLI before the mend left the store at 210 and the log at 219 —
`mimir-log.sh verify` named it: `missing_from_engram 1`. That phantom is what the log-first design is for:
`mimir-log.sh reseed` observed it (`observed 1, already 218`) and `verify` returned `211, 211, 0, 0`.

**Mend, written but not shipped:** `bin/bridge/mimir-bridge.py` now probes `inspect.signature(eng.observe)`
and passes only the keywords the engine declares, exactly as the log tool does. Proven on a throwaway well
(`ENGRAM_DB=/tmp/wp/probe.engram`, port 4699, its own log): `stored: true`, id returned, `episodes: 1`. The
probe server and its scratch store were stopped and removed; the live store was never touched by the test.

**Not shipped, deliberately:** the patch sits uncommitted in the hall tree, because opening a PR is the
Allfather's word and he already has #536 open. The running unit therefore still serves the old code — and from
an **older tree**: `mimir.service` runs `/home/heimdall/ymir-runtime/bin/bridge/mimir-bridge.py` (a separate
clone, `main` at `9ab27599`, 2026-11-02), while the session and this note live in `/home/heimdall/ymir`
(detached at `49ced55e`). Two trees, one door: a fix landed in the hall does not reach the unit, and a fix
landed in the runtime is erased by the next pull. That divergence is the fault to name before anything else is
mended here.

### Appended — this rides the PR now
The Allfather gave his word on 2026-11-06: the bridge patch ships as a pull request, cut from `origin/main`
(`43d934ac`) in the Yggdrasil worktree `well-bridge-signature`, branch `yggdrasil/well-bridge-signature`.
The hall tree's copy is reverted to the shipped state once the branch exists, so one fix lives in one place.
The running `mimir.service` is pointed at the hall's bridge by a systemd drop-in until this merges; the
drop-in is removed the day it lands, so the unit returns to the installed tree.

## CHANGE LOG

- **2026-11-06** — Carved. The corrupt index, the salvage proof, the re-seed from the append log, the void of
  one `undefined` row, the checkpoint roll. Appended the same day: the write door's `provenance` fault, the
  patch, the scratch-well proof, and the note that it ships as a pull request while `mimir.service` runs a
  separate checkout. Correct by appending a dated section; never rewrite the account above.
