#!/usr/bin/env python3
"""mimir-bridge.py — the HTTP face of the well (Mimirsbrunn / engram, :4602).

The upstream engram engine ships a CLI and an MCP (stdio) server, but the rest
of Ymir — the gate API, `bin/records/mimir.sh`, `bin/records/mimir-ingest.sh`, the session
start — speaks a small HTTP contract on 127.0.0.1:4602. This bridge is that
face: a long-lived HTTP server wrapping the `engram` library over one
`.engram` store.

Endpoints:
  GET  /health                 -> {status, store, episodes, agents, last_*}
  GET  /recall?q&k&mode        -> {results:[{score, distance, importance, episode}], slice}
       also: store=, tag= (repeatable), since=, until=, agent_id=, include_archived=1
  POST /observe {content,...}  -> {id, stored, gate, store, tags}
  POST /correct {original_id, content,...} -> {id, corrects}
  POST /retract {original_id, why}         -> {id, retracts}
  GET  /grade?apply=0|1        -> the continuous forgetting pass (report by default)
  GET  /timeline?entity=       -> {facts:[...]}
  GET  /inspect                -> {episodes, agents, store}

WHAT IS NEW (plan 136). A write is now a DECISION: the gate in
`bin/records/mimir-policy.py` asks whether it changes future behaviour, is a
commitment with consequences, or is a decision with rationale, and drops what
answers none. It then canonicalizes, deduplicates, scores by novelty and task
relevance, types the episode (episodic · semantic · procedural) and stamps its
provenance (source, scope, confidence, privacy, retention) as tags the whole
house already reads. Recall is scoped BEFORE it searches: a recency, type and
tag slice is built from the store, the similarity search runs inside it, and a
voided or archived episode is never handed back as fact. Corrections and
retractions APPEND and chain by id (Rule 20) — nothing is erased.

No secrets here; the store is in the hoard. Stdlib only (plus the engine).
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import sqlite3
import threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parents[2]   # the repo root (bin/bridge/<file>) is 2 up


def _policy():
    """The well's policy — ONE module, shared with the CLI and the grading pass.

    `bin/records/mimir-policy.py` is stdlib-only on purpose (the gate must work
    when the engine cannot be imported), so loading it by path here costs nothing
    and keeps two copies of the law from drifting apart."""
    path = ROOT / "bin" / "records" / "mimir-policy.py"
    spec = importlib.util.spec_from_file_location("mimir_policy", path)
    if spec is None or spec.loader is None:  # pragma: no cover - a broken tree
        raise RuntimeError(f"the memory policy is missing at {path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


policy = _policy()


def _ymir_home() -> Path:
    """The operator's home: env -> the recorded choice -> the ONE documented
    default. The default is owned by bin/vault/hoard-lib.sh (Rule 07); this mirrors
    its record file so a hand-started bridge resolves the same home."""
    env = os.environ.get("YMIR_HOME")
    if env:
        return Path(env).expanduser()
    cfg = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
    try:
        rec = (cfg / "ymir" / "home").read_text().strip().splitlines()[0].strip()
        if rec:
            return Path(rec).expanduser()
    except (OSError, IndexError):
        pass
    return Path.home() / "Documents" / "ymirhome"


# The well is ONE memory and it lives in the hoard — never in the tree and
# never in a migrated copy. The shell bridge passes ENGRAM_DB; this default
# (hoard | legacy-local) keeps a hand-started bridge honest either way.
_home = _ymir_home()
STORE = Path(os.environ.get(
    "ENGRAM_DB",
    str(_home / "hodd/memory/kaia.engram")
)).expanduser()
HOST = os.environ.get("MIMIRSBRUNN_HOST", "127.0.0.1")
PORT = int(os.environ.get("MIMIRSBRUNN_PORT", os.environ.get("ENGRAM_PORT", "4602")))
DEFAULT_AGENT = os.environ.get("ENGRAM_AGENT_ID", "kaia")

# --- the append log (the source of truth for re-seeding) ---------------------
# The engram is DERIVED; the JSONL log is the durable, append-only, unionable
# record it is rebuilt from. That only holds if EVERY observe reaches the log.
# The bridge is the one door all harnesses pass through (pi, opencode, claude,
# cursor, codex), so the append lives here. Hash-deduped, never rewritten.
LOG = Path(os.environ.get(
    "ENGRAM_LOG",
    str(STORE.parent / "well" / "episodes.jsonl"),
)).expanduser()
_log_lock = threading.Lock()
_log_state: dict = {"sig": None, "hashes": set()}


def _log_hashes() -> set:
    """The content hashes already in the log, reloaded when the file moves.

    Another writer (mimir.sh, mimir-ingest.sh) may append between our calls, so
    the file's (mtime, size) is the signal to re-read rather than trust a stale
    in-memory set."""
    try:
        st = LOG.stat()
        sig = (st.st_mtime_ns, st.st_size)
    except OSError:
        sig = None
    with _log_lock:
        if _log_state["sig"] != sig:
            found = set()
            try:
                for line in LOG.read_text(encoding="utf-8", errors="replace").splitlines():
                    line = line.strip()
                    if not line.startswith("{"):
                        continue
                    try:
                        h = json.loads(line).get("hash")
                    except Exception:
                        continue
                    if h:
                        found.add(h)
            except OSError:
                pass
            _log_state["sig"] = sig
            _log_state["hashes"] = found
        return _log_state["hashes"]


def append_log(content: str, actors, tags, salience, importance, agent: str, when,
               extra: dict | None = None) -> bool:
    """Append one full episode to the log; False if it was already there.

    `extra` carries the gate's decision and the provenance record, so a re-seed
    from the log restores the typed, deduped, gated episode — not a bare text."""
    digest = hashlib.sha256(content.encode("utf-8")).hexdigest()
    hashes = _log_hashes()
    with _log_lock:
        if digest in hashes:
            return False
        moment = when or datetime.now(timezone.utc)
        rec = {
            "timestamp": moment.isoformat().replace("+00:00", "Z"),
            "source": agent,
            "actors": list(actors or [agent]),
            "tags": list(tags or ["well"]),
            "content": content,
            "salience": salience,
            "importance": importance,
            "agent_id": agent,
            "hash": digest,
        }
        rec.update(extra or {})
        try:
            LOG.parent.mkdir(parents=True, exist_ok=True)
            with LOG.open("a", encoding="utf-8") as fh:
                fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
        except OSError:
            return False
        hashes.add(digest)
        try:
            st = LOG.stat()
            _log_state["sig"] = (st.st_mtime_ns, st.st_size)
        except OSError:
            _log_state["sig"] = None
        return True


from engram import Engram  # noqa: E402  (after env is read)

_pool: dict[str, Engram] = {}
_lock = threading.Lock()


def engine(agent: str | None) -> Engram:
    """One Engram instance per agent scope (writes are scoped at construction)."""
    key = agent or "__all__"
    with _lock:
        if key not in _pool:
            _pool[key] = Engram(path=str(STORE), agent_id=agent)
        return _pool[key]


def flush_access(eng: "Engram") -> None:
    """Write a recall into the access log, now.

    The engine BUFFERS retrievals and flushes in bursts, so a long-lived bridge
    would forget that it had ever been asked — and the health row's "last recall"
    and the grading pass's "by access frequency" both read that log. Measured
    2026-10-26: four recalls left `access_log` empty while `last_recall` read
    "never". Public-first, private as a fallback, a clean no-op on a newer engine.
    """
    for holder in (eng, getattr(eng, "_store", None), getattr(eng, "store", None)):
        fn = getattr(holder, "flush_access_log", None) if holder is not None else None
        if callable(fn):
            try:
                fn()
                return
            except Exception:  # noqa: BLE001
                continue


def layers():
    """What the well actually holds, layer by layer - the record a UI reads."""
    out = {"facts": 0, "facts_active": 0, "facts_superseded": 0, "entities": 0,
           "edges": 0, "reflections": 0, "last_reflection": None, "vec_index": 0}
    try:
        con = sqlite3.connect(f"file:{STORE}?mode=ro", uri=True)
        for key, sql in (
            ("facts", "select count(*) from facts"),
            ("facts_active", "select count(*) from facts where superseded_at is null"),
            ("facts_superseded", "select count(*) from facts where superseded_at is not null"),
            ("entities", "select count(*) from entities"),
            ("edges", "select count(*) from edges"),
            ("reflections", "select count(*) from reflections"),
            ("vec_index", "select count(*) from vec_episodes_rowids"),
        ):
            try:
                out[key] = int(con.execute(sql).fetchone()[0])
            except Exception:
                pass
        try:
            out["last_reflection"] = con.execute(
                "select max(finished_at) from reflections").fetchone()[0]
        except Exception:
            pass
    except Exception as e:
        out["error"] = str(e)
    return out


def count_episodes() -> int:
    try:
        con = sqlite3.connect(f"file:{STORE}?mode=ro", uri=True)
        try:
            return int(con.execute("select count(*) from episodes").fetchone()[0])
        finally:
            con.close()
    except Exception:
        return 0


def ep_json(e) -> dict:
    tags = list(e.tags or [])
    return {
        "id": e.id,
        "content": e.content,
        "timestamp": e.timestamp.isoformat() if e.timestamp else None,
        "actors": list(e.actors or []),
        "agents": list(e.actors or []),
        "tags": tags,
        "salience": e.salience,
        "importance": e.importance_score,
        "agent_id": getattr(e, "agent_id", None),
        # The three facts a keeper needs in order to TRUST a row: what kind of
        # memory it is, whether a later entry voided it, and whether it was
        # archived on purpose. A void never leaves the record; it leaves recall.
        "store": policy.store_of(tags),
        "voided": policy.is_void(tags),
        "archived": policy.is_archived(tags),
        "provenance": getattr(e, "provenance", None),
        "quarantined": bool(getattr(e, "quarantined", False)),
    }


def _rows(where: str = "", params: tuple = (), limit: int = 0) -> list[dict]:
    """Episodes straight from the store, filtered in SQL. This is the SLICE that
    scoped recall searches inside — measured before the similarity search runs,
    so a keeper's question is answered from its own shelf, not the whole house."""
    sql = "select id, content, timestamp, tags, actors, agent_id, importance_score from episodes"
    if where:
        sql += f" where {where}"
    sql += " order by timestamp desc"
    if limit:
        sql += f" limit {int(limit)}"
    out: list[dict] = []
    try:
        con = sqlite3.connect(f"file:{STORE}?mode=ro", uri=True, timeout=3)
        con.row_factory = sqlite3.Row
        try:
            for r in con.execute(sql, params):
                rec = {k: r[k] for k in r.keys()}
                for key in ("tags", "actors"):
                    if key in rec:
                        try:
                            rec[key] = json.loads(rec[key] or "[]")
                        except Exception:
                            rec[key] = []
                out.append(rec)
        finally:
            con.close()
    except Exception:
        return out
    return out


def build_slice(stores=(), tags=(), since=None, until=None, agent=None, task=None,
                include_voided=False, include_archived=False) -> list[dict]:
    """The scope, chosen BEFORE the search: recency, memory type, tag, keeper.

    `include_voided`/`include_archived` default off, and that is the point: a
    retracted episode must not come back as fact, and an archived one is read on
    purpose, not by accident."""
    where, params = [], []
    if since:
        where.append("timestamp >= ?")
        params.append(_iso(since))
    if until:
        where.append("timestamp <= ?")
        params.append(_iso(until))
    if agent:
        where.append("agent_id = ?")
        params.append(agent)
    # The TASK is a shelf of its own: episodes written with a `task:` are the ones
    # that belong to that work, so "what did I learn on this?" is a filter and not
    # a hope that the words happen to match.
    if task:
        tags = tuple(tags) + (f"task:{policy.canonical_actor(task)}",)
    rows = _rows(" and ".join(where), tuple(params))
    keep: list[dict] = []
    for r in rows:
        rt = r.get("tags") or []
        if not include_voided and policy.is_void(rt):
            continue
        if not include_archived and policy.is_archived(rt):
            continue
        if stores and policy.store_of(rt) not in stores:
            continue
        if tags and not all(any(t.lower() in (x or "").lower() for x in rt) for t in tags):
            continue
        keep.append(r)
    return keep


def _str(value) -> str | None:
    """A timestamp as a plain string for JSON — the policy hands back whatever
    sqlite returned, which may be a datetime."""
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.isoformat()
    return str(value)


def _iso(value) -> str:
    """One timestamp shape for a SQL comparison: ISO-8601 with a Z."""
    text = str(value).strip()
    for fmt in ("%Y-%m-%d", "%Y-%m-%dT%H:%M", "%Y-%m-%dT%H:%M:%SZ"):
        try:
            return datetime.strptime(text, fmt).replace(tzinfo=timezone.utc).isoformat()
        except ValueError:
            continue
    return text


def lexical_rank(query: str, rows: list[dict]) -> list[dict]:
    """Fill the tail of a scoped recall when the vector index has not caught up.

    A memory written seconds ago is in the store and not yet in the semantic
    index; returning "nothing" for it would make "not indexed yet" and "never
    recorded" the same lie."""
    words = policy.tokenize(query)
    scored = []
    for r in rows:
        content = str(r.get("content") or "")
        if not words:
            scored.append((0.0, r))
            continue
        overlap = len(words & policy.tokenize(content)) / len(words)
        if query.lower() in content.lower():
            overlap += 0.5
        if overlap > 0:
            scored.append((overlap, r))
    scored.sort(key=lambda x: x[0], reverse=True)
    return [r for _, r in scored]


def correction_chain(episode_id: str) -> dict:
    """Who voided this, and what this voids — the chain, read back by id.

    A correction never overwrites: the replacement carries `corrects:<original>`
    (or `retracts:`/`consolidates:`) and the original carries `void:<replacement>`.
    So the record answers "what did we believe, and what do we believe now" with
    both halves still standing."""
    mine = _rows("id = ?", (episode_id,), limit=1)
    voided_by = policy.values_in(mine[0].get("tags") or [], "void") if mine else []
    # Everything that NAMES this episode: a replacement says `corrects:<id>` and
    # also `voids:<id>`; so the chain is read from the replacements' own tags.
    rows = _rows("instr(coalesce(tags,'[]'), ?) > 0", (f":{episode_id}",))
    replaced_by, retracted_by, consolidated_by = [], [], []
    for r in rows:
        if r.get("id") == episode_id:
            continue
        tags = r.get("tags") or []
        if episode_id not in policy.values_in(tags, "voids"):
            continue
        for kind, bucket in (("corrects", replaced_by), ("retracts", retracted_by),
                             ("consolidates", consolidated_by)):
            if episode_id in policy.values_in(tags, kind):
                bucket.append(r.get("id"))
    return {"voided_by": voided_by, "replaced_by": replaced_by,
            "retracted_by": retracted_by, "consolidated_by": consolidated_by}


def annotate(episode_id: str, add: list[str]) -> list[str]:
    """Add tags to an episode — the ONLY edit Rule 20 permits on a stored
    episode, and the mechanism behind void, archive and consolidation. The
    content is never touched; nothing is ever removed."""
    con = sqlite3.connect(str(STORE), timeout=5)
    try:
        row = con.execute("select tags from episodes where id = ?", (episode_id,)).fetchone()
        if not row:
            return []
        try:
            tags = json.loads(row[0] or "[]")
        except Exception:
            tags = []
        merged = list(tags) + [t for t in add if t not in tags]
        con.execute("update episodes set tags = ? where id = ?",
                    (json.dumps(merged, ensure_ascii=False), episode_id))
        con.commit()
        return merged
    finally:
        con.close()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):  # keep the bridge quiet
        pass

    def _json(self, code: int, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        u = urlparse(self.path)
        q = parse_qs(u.query)
        try:
            if u.path == "/health":
                # The health row Eir reports and the Allfather can read at a
                # glance: how big the memory is, when it was last watered, last
                # drunk from, last written as a day, and last pruned. Measured
                # from the record — never from a note about the record.
                row = policy.memory_row(STORE)
                row.pop("grading", None)
                return self._json(200, {
                    "status": "up",
                    "store": str(STORE),
                    "episodes": count_episodes(),
                    "agents": engine(None).list_agents(),
                    "last_observe": _str(row.get("last_observe")),
                    "last_recall": _str(row.get("last_recall")),
                    "last_daily": row.get("last_daily"),
                    "last_prune": _str(row.get("last_prune")),
                    "stores": row.get("stores"),
                    "voided": row.get("voided"),
                    "age_days": row.get("age_days"),
                    "healthy": row.get("healthy"),
                    "why": row.get("why"),
                })
            if u.path == "/inspect":
                # THE LAYERS, not just the count. The smithy shows what it is told,
                # and it was told three fields while the well holds six: a panel that
                # reads only episodes cannot show that facts and entities exist.
                return self._json(200, {
                    "store": str(STORE),
                    "episodes": count_episodes(),
                    "agents": engine(None).list_agents(),
                    **layers(),
                })
            if u.path == "/recent":
                limit = int((q.get("limit") or ["60"])[0])
                out = []
                try:
                    con = sqlite3.connect(f"file:{STORE}?mode=ro", uri=True)
                    con.row_factory = sqlite3.Row
                    try:
                        for r in con.execute(
                            "select id, content, timestamp, tags, actors, agent_id "
                            "from episodes order by timestamp desc limit ?",
                            (limit,),
                        ):
                            out.append({
                                "id": r["id"],
                                "content": r["content"],
                                "timestamp": r["timestamp"],
                                "tags": json.loads(r["tags"] or "[]"),
                                "actors": json.loads(r["actors"] or "[]"),
                                "agent_id": r["agent_id"],
                            })
                    finally:
                        con.close()
                except Exception:
                    pass
                return self._json(200, {"episodes": out})
            if u.path == "/episode":
                eid = (q.get("id") or [""])[0]
                if not eid:
                    return self._json(400, {"error": "episode needs id"})
                rec = None
                try:
                    con = sqlite3.connect(f"file:{STORE}?mode=ro", uri=True)
                    con.row_factory = sqlite3.Row
                    try:
                        rec = con.execute(
                            "select id, content, timestamp, tags, actors, agent_id from episodes where id = ?",
                            (eid,),
                        ).fetchone()
                    finally:
                        con.close()
                except Exception:
                    rec = None
                if not rec:
                    return self._json(404, {"error": "no such episode"})
                tags_rec = json.loads(rec["tags"] or "[]")
                return self._json(200, {"episode": {
                    "id": rec["id"], "content": rec["content"], "timestamp": rec["timestamp"],
                    "tags": tags_rec,
                    "actors": json.loads(rec["actors"] or "[]"),
                    "agent_id": rec["agent_id"],
                    "store": policy.store_of(tags_rec),
                    "voided": policy.is_void(tags_rec),
                    "archived": policy.is_archived(tags_rec),
                    "provenance": policy.values_in(tags_rec, "src"),
                    "chain": correction_chain(str(rec["id"])),
                }})
            if u.path == "/recall":
                query = (q.get("q") or [""])[0]
                try:
                    k = int((q.get("k") or ["5"])[0])
                except ValueError:
                    return self._json(400, {"error": "k must be an integer from 1 to 1000"})
                if not 1 <= k <= 1000:
                    return self._json(400, {"error": "k must be an integer from 1 to 1000"})
                mode = (q.get("mode") or ["hybrid"])[0]
                agent = (q.get("agent_id") or [None])[0]
                cross = (q.get("cross_agent") or ["1"])[0] not in ("0", "false", "")
                # SCOPE FIRST. Recency, memory type and tag decide the shelf; the
                # similarity search only ranks what is already on it. Before plan
                # 136 an unscoped query searched the house and filtered later (or
                # not at all), so a keeper's own memory competed with everyone's.
                stores = tuple(s for s in (q.get("store") or []) if s in policy.STORES)
                if not stores:
                    for chunk in (q.get("stores") or []):
                        stores += tuple(s for s in chunk.split(",") if s in policy.STORES)
                tags = tuple(t for t in (q.get("tag") or []) if t)
                for chunk in (q.get("tags") or []):
                    tags += tuple(t for t in chunk.split(",") if t)
                since = (q.get("since") or [None])[0]
                until = (q.get("until") or [None])[0]
                task = (q.get("task") or [None])[0]
                include_voided = (q.get("include_voided") or ["0"])[0] not in ("0", "false", "")
                include_archived = (q.get("include_archived") or ["0"])[0] not in ("0", "false", "")
                scope = {"stores": list(stores), "tags": list(tags), "since": since,
                         "until": until, "agent_id": agent, "task": task,
                         "include_voided": include_voided, "include_archived": include_archived}

                sliced = build_slice(stores=stores, tags=tags, since=since, until=until,
                                     agent=agent, task=task,
                                     include_voided=include_voided,
                                     include_archived=include_archived)
                allowed = {r.get("id") for r in sliced}
                results = []
                if allowed and query:
                    eng = engine(agent)
                    hits = eng.recall(query, k=max(k * 6, 30), mode=mode, cross_agent=cross,
                                      candidate_limit=max(k * 20, 200))
                    seen = set()
                    for h in hits:
                        ep = ep_json(h.episode)
                        if ep["id"] not in allowed or ep["id"] in seen:
                            continue
                        seen.add(ep["id"])
                        results.append({"score": h.score, "distance": h.distance,
                                        "importance": h.importance, "episode": ep})
                        if len(results) >= k:
                            break
                    # A recall is a fact about the memory too: record that the well
                    # was drunk from, so "never consulted" is visible in the health row.
                    flush_access(eng)
                if len(results) < k:
                    have = {r["episode"]["id"] for r in results}
                    rest = [r for r in lexical_rank(query, sliced) if r.get("id") not in have]
                    for r in rest[: max(0, k - len(results))]:
                        tags_r = r.get("tags") or []
                        results.append({
                            "score": 0.5, "distance": None,
                            "importance": r.get("importance_score"),
                            "episode": {
                                "id": r.get("id"), "content": r.get("content"),
                                "timestamp": r.get("timestamp"), "tags": tags_r,
                                "actors": r.get("actors") or [], "agents": r.get("actors") or [],
                                "agent_id": r.get("agent_id"), "store": policy.store_of(tags_r),
                                "voided": policy.is_void(tags_r),
                                "archived": policy.is_archived(tags_r),
                            },
                            "lexical": True,
                        })
                return self._json(200, {"results": results, "slice": len(sliced),
                                        "scope": scope})
            if u.path == "/timeline":
                entity = (q.get("entity") or [""])[0]
                facts = engine(None).timeline(entity)
                return self._json(200, {
                    "facts": [
                        {
                            "id": f.id, "subject": f.subject, "predicate": f.predicate, "object": f.object,
                            "valid_from": f.valid_from.isoformat() if f.valid_from else None,
                            "valid_to": f.valid_to.isoformat() if f.valid_to else None,
                            "confidence": f.confidence,
                        }
                        for f in facts
                    ]
                })
            if u.path == "/grade":
                # The continuous forgetting pass. REPORT by default; `apply=1`
                # decays, annotates and moves — and refuses to lower the count.
                apply_now = (q.get("apply") or ["0"])[0] not in ("0", "false", "")
                return self._json(200, policy.grade(STORE, apply=apply_now))
            return self._json(404, {"error": f"no route {u.path}"})
        except Exception as exc:  # noqa: BLE001
            return self._json(500, {"error": str(exc)})

    def do_POST(self) -> None:  # noqa: N802
        u = urlparse(self.path)
        length = int(self.headers.get("content-length") or 0)
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
        except Exception:
            body = {}
        try:
            if u.path in ("/observe", "/remember"):
                return self._write(body, kind="observe")
            if u.path == "/correct":
                original = str(body.get("original_id") or "").strip()
                if not original:
                    return self._json(400, {"error": "correct needs original_id"})
                return self._write(body, kind="correct", original_id=original)
            if u.path == "/retract":
                original = str(body.get("original_id") or "").strip()
                if not original:
                    return self._json(400, {"error": "retract needs original_id"})
                why = str(body.get("why") or "").strip()
                first = self._first_line(original)
                body = dict(body)
                body["content"] = (f"Retracted episode {original} ({first}). {why} "
                                   f"The original stays in the record, voided — not erased (Rule 20).")
                body["shape"] = body.get("shape") or "decision"
                body.setdefault("tags", [])
                return self._write(body, kind="retract", original_id=original)
            if u.path == "/grade":
                apply_now = bool(body.get("apply"))
                return self._json(200, policy.grade(STORE, apply=apply_now))
            return self._json(404, {"error": f"no route {u.path}"})
        except Exception as exc:  # noqa: BLE001
            return self._json(500, {"error": str(exc)})

    @staticmethod
    def _first_line(episode_id: str) -> str:
        rows = _rows("id = ?", (episode_id,), limit=1)
        if not rows:
            return "unknown episode"
        line = (rows[0].get("content") or "").split("\n")[0]
        return line[:120]

    def _write(self, body: dict, kind: str, original_id: str | None = None):
        """Every write passes the gate, and a write is answered with its own
        decision — kept, with its type and provenance, or DROPPED with the reason.

        The gate is not advisory. A well that keeps everything cannot be trusted
        about anything, so a drop is a normal answer (HTTP 200, stored:false) and
        the caller is told exactly which question it failed.
        """
        content = str(body.get("content") or "").strip()
        if not content:
            return self._json(400, {"error": f"{kind} needs content"})
        agent = body.get("agent_id") or body.get("source") or DEFAULT_AGENT
        ts = body.get("timestamp")
        when = datetime.fromisoformat(str(ts).replace("Z", "+00:00")) if ts else None
        caller_tags = body.get("tags") or []
        if isinstance(caller_tags, str):  # a comma string is an array of CHARACTERS
            caller_tags = [t for t in caller_tags.split(",") if t.strip()]

        decision = policy.decide(
            content,
            tags=caller_tags,
            task=body.get("task"),
            source=body.get("source") or agent,
            store=body.get("store") or body.get("memory_type"),
            shape=body.get("shape"),
            salience=float(body["salience"]) if body.get("salience") is not None else None,
            confidence=float(body["confidence"]) if body.get("confidence") is not None else None,
            privacy=str(body.get("privacy") or "internal"),
            retention=str(body.get("retention") or "keep"),
            scope=str(body.get("scope") or "house"),
            corpus=policy.read_corpus(STORE),
            force=bool(body.get("force")),
        )
        if not decision["keep"]:
            return self._json(200, {
                "stored": False, "gate": {k: decision[k] for k in
                                            ("keep", "why", "matched", "novelty", "relevance",
                                             "duplicate_of", "notes", "refused") if k in decision},
                "episodes": count_episodes(),
            })

        tags = list(decision["tags"])
        if original_id:
            tags += policy.correction_tags(original_id,
                                           "corrects" if kind == "correct" else "retracts")
        content = decision["content"]
        eid = engine(agent).observe(
            content,
            actors=body.get("actors") or None,
            tags=tags,
            salience=decision["salience"],
            timestamp=when,
            provenance=decision["provenance"],
            quarantined=decision["quarantined"],
        )
        # The chain, in the other direction: the ORIGINAL is annotated void by the
        # replacement's id. Annotation only — the original's words stay.
        chain = None
        if original_id:
            annotate(original_id, [f"void:{eid}"])
            chain = correction_chain(original_id)
        # The log is the truth; the engram is derived from it. Write the log AFTER
        # the store, so a failed observe never logs a phantom — and carry the
        # gate's decision, so a re-seed restores a gated episode, not bare text.
        append_log(content, body.get("actors") or None, tags, decision["salience"],
                   decision["salience"], agent, when,
                   extra={"store": decision["store"], "provenance": decision["provenance"],
                          "quarantined": decision["quarantined"], "gate": decision["meta"].get("gate"),
                          "correction": {"kind": kind, "original": original_id} if original_id else None})
        return self._json(200, {
            "id": eid, "stored": True, "agent_id": agent, "store": decision["store"],
            "tags": tags, "salience": decision["salience"],
            "provenance": decision["provenance"],
            "gate": {k: decision[k] for k in ("keep", "why", "matched", "novelty", "relevance", "notes")},
            "chain": chain, "episodes": count_episodes(),
        })


def ensure_schema() -> None:
    """The store's own shape, brought forward additively (plan 136).

    Two things Ymir needs and the engine's schema may not carry on an old store:
    the engine's provenance columns (`provenance`, `quarantined`, added upstream in
    engdbram 3.0) and an index on `timestamp`, because scoped recall filters by
    recency BEFORE it searches — an unindexed scan is how a slice becomes a
    full-table walk as the well grows. Both are additive; neither rewrites a row.
    """
    try:
        con = sqlite3.connect(str(STORE), timeout=5)
        try:
            cols = {r[1] for r in con.execute("pragma table_info(episodes)")}
            for name, decl in (("provenance", "TEXT DEFAULT NULL"),
                               ("quarantined", "INTEGER DEFAULT NULL")):
                if name not in cols:
                    con.execute(f"alter table episodes add column {name} {decl}")
            con.execute("create index if not exists idx_episodes_ts on episodes(timestamp)")
            con.commit()
        finally:
            con.close()
    except Exception as exc:  # noqa: BLE001
        print(f"[mimir-bridge] schema not brought forward: {exc}", flush=True)


def main() -> None:
    STORE.parent.mkdir(parents=True, exist_ok=True)
    # Touch the store so the schema exists before the first request.
    engine(None)
    ensure_schema()
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"[mimir-bridge] Mimirsbrunn {HOST}:{PORT} · store {STORE}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
