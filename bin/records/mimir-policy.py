#!/usr/bin/env python3
"""mimir-policy.py — the law of the well: what may be written, what it is, and
what may be forgotten.

Plan 136, "the best memory an AI best friend can have". The well already had a
store and a recall; it had no *policy*. Everything below is one policy with five
faces, because each one is useless alone:

  1. THE GATE (`decide`). Before anything is stored, three questions are asked:
     does this change future behaviour, is it a commitment with consequences, or
     is it a decision with rationale? If none of the three answers yes, it is
     dropped. A memory that accepts everything is a shelf; the value of the well
     is that a keeper can trust what it holds.

  2. THE SHAPE ROUTE (`infer_store`). Every episode is one of three kinds —
     episodic (an event in time), semantic (a stable fact or preference),
     procedural (an instruction or workflow) — and the kind is stamped at write
     time so recall can filter the shelf before it searches it.

  3. THE PROVENANCE (see `provenance_tags`). An episode carries where it came
     from, what its scope is, how sure the writer was, its privacy class and its
     retention rule. The engine's own `provenance` column holds its fixed
     vocabulary (user|tool|external) and `quarantined` marks content that came
     out of untrusted context; Ymir's richer record rides in tags, because the
     engine refuses any other provenance value — measured, not guessed:
     `PROVENANCES == ('user','tool','external')`.

  4. THE CORRECTION (`correction_tags`). Episodes are corrected and retracted by
     APPENDING, chained to the original by id — never by erasing. The original
     keeps its content and gains one tag, `void:<new-id>`, which is what the ward
     (`bin/records/well-guard.sh`) already reads and what recall excludes. This is
     RULES/20-the-well-appends.md: repair adds, it does not subtract.

  5. THE FORGETTING (`grade`). Memory that never prunes becomes noise, and noise
     is the enemy of recall. Grading (nýr · eldri · forn · safn) is a continuous
     pass — decay by recency and access frequency, consolidation of overlaps,
     old documents moved to `hodd/reference/` with why they went and what
     replaced them. Nothing is deleted: an episode is annotated, a document
     moves.

Stdlib only, on purpose. The bridge, the CLI (`bin/records/mimir.sh`), the
session start and Eir all give this module the same answers, and the gate must
work when the bridge is down and the engine is unimportable.

Doors:
  mimir-policy.py gate --content "<text>" [--task "<words>"] [--shape decision]
  mimir-policy.py grade [--apply] [--json]
  mimir-policy.py memory [--json]        # the one health row (what Eir reports)
  mimir-policy.py --self-test

Exit: 0 keep / healthy · 1 the gate dropped it, or a check failed · 2 usage.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import sqlite3
import sys
import tempfile
import unicodedata
from datetime import datetime, timedelta, timezone
from pathlib import Path

VERSION = "1.0.0"

# ── what an episode may be ────────────────────────────────────────────────────
STORES = ("episodic", "semantic", "procedural")
STORE_MEANING = {
    "episodic": "an event in time — what happened, when, to whom",
    "semantic": "a stable fact or preference — the rule that holds between events",
    "procedural": "an instruction or workflow — how the thing is done",
}

# The three questions the gate asks. A write that answers none is dropped.
QUESTIONS = {
    "changes-behavior": "does this change future behaviour?",
    "commitment": "is this a commitment with consequences?",
    "decision": "is this a decision with rationale?",
}

# Signals are how the gate ANSWERS a question without a model. They are read as
# evidence, never as law: a caller may declare a shape outright (`shape=`), and a
# declared shape is answered without a scan.
SIGNALS = {
    "changes-behavior": [
        r"\bnext time\b", r"\bfrom now on\b", r"\balways\b", r"\bnever\b",
        r"\bprefer\b", r"\binstead use\b", r"\binstead of\b", r"\bstop doing\b",
        r"\bgotcha\b", r"\blesson\b", r"\bthe trap\b", r"\bdo not\b", r"\bdon't\b",
        r"\bthe rule is\b", r"\bmust not\b", r"\bremember to\b",
        # A DOCUMENTED WORKFLOW IS A BEHAVIOUR CHANGE. "how to do this" is the
        # lesson a best friend most needs to hand back, and a gate that only
        # heard was/will/decided would drop every procedure ever written.
        r"\bstep \d\b", r"\bthen run\b", r"\bhow to\b", r"\bworkflow\b",
        r"\bprocedure\b", r"\bthe command is\b", r"\brun .{0,30} before\b",
        r"\bfirst,? then\b", r"\bthe way to\b",
    ],
    "commitment": [
        r"\bwill\b", r"\bowe[sd]?\b", r"\bdeadline\b", r"\bpromise[ds]?\b",
        r"\bagreed\b", r"\bcommitt?ed to\b", r"\bapproval\b", r"\bshipped\b",
        r"\bhandoff\b", r"\bby \d{4}-\d{2}-\d{2}\b", r"\bresponsible for\b",
        r"\bsigned off\b",
    ],
    "decision": [
        r"\bdecided\b", r"\bdecision\b", r"\bchose\b", r"\bchosen\b",
        r"\brationale\b", r"\bbecause\b", r"\bvetoed\b", r"\bsettled? on\b",
        r"\bwe use\b", r"\bthe call is\b", r"\brejected\b", r"\bapproved\b",
    ],
}

# Evidence for the shape route, strongest first. `procedural` before `semantic`
# before `episodic`: a workflow that names a rule is still a workflow.
STORE_SIGNALS = (
    ("procedural", [
        r"\bstep \d\b", r"\bfirst,? then\b", r"\bthen run\b", r"\bhow to\b",
        r"\bworkflow\b", r"\binvoke\b", r"\brun `", r"\bthe command\b",
        r"\binstall\b", r"\bsequence\b", r"\bfollow these\b", r"\bprocedure\b",
    ]),
    ("semantic", [
        r"\bthe rule\b", r"\bis a\b", r"\bis an\b", r"\bmeans\b", r"\bdefaults?\b",
        r"\bconvention\b", r"\bcontract\b", r"\bpreference\b", r"\bthere are two\b",
        r"\bnever\b", r"\balways\b", r"\bthe law\b", r"\bdecid", r"\bdecision\b",
        r"\brationale\b", r"\bwe use\b", r"\bpolicy\b", r"\bthe gate is\b",
    ]),
)

# Never store a secret, and never store the vault (Rules 15, 24). This is a drop,
# not a warning: a leak into the well rides the vault to every seat.
SECRET_PATTERNS = [
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----",
    r"\bgh[pousr]_[A-Za-z0-9]{16,}\b",
    r"\bsk-[A-Za-z0-9_-]{20,}\b",
    r"\bAKIA[0-9A-Z]{16}\b",
    r"\bxox[baprs]-[A-Za-z0-9-]{10,}\b",
    r"(?i)\b(password|passwd|api[_-]?key|secret[_-]?key|token)\s*[:=]\s*['\"]?[A-Za-z0-9/+_=.-]{12,}",
    r"\bage1[0-9a-z]{20,}\b",
]
PRIVATE_CLASSES = ("public", "internal", "private")
REFUSED_CLASSES = {
    "vault": "the vault never enters the well (Rules 15/16) — work on it inside a confidential session",
    "confidential": "confidential work never enters the well (Rules 15/16) — use a confidential session",
    "restricted": "restricted material is not watered in — narrow it, or keep it in the hoard",
}
RETENTION_EPHEMERAL = "ephemeral"

# Grading. nýr fresh · eldri aging · forn old · safn archive.
GRADES = ("nýr", "eldri", "forn", "safn")
GRADE_MEANING = {
    "nýr": "changed or read recently — the live edge of memory",
    "eldri": "still in play, but not of late",
    "forn": "old: superseded, or long unread",
    "safn": "archive: moved to reference on purpose, read but never edited",
}
FRESH_DAYS = 14
AGING_DAYS = 90
OLD_DAYS = 365

STOPWORDS = frozenset("""
a an the and or but if then than that this these those is are was were be been being
of in on at to for from with without by as it its its' we you i he she they them us
our your their not no yes so such very more most much many any all some each other
into over under again once here there when where why how do does did done can could
should would may might must shall will just also only about after before while
""".split())


# ── shape: words, canonicalized ──────────────────────────────────────────────

_MONTHS = {m: i for i, m in enumerate(
    ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"], 1)}

_RE_REL_DAY = re.compile(r"\b(today|yesterday|tomorrow)\b", re.I)
_RE_MON_D = re.compile(
    r"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})\b",
    re.I)
_RE_D_MON = re.compile(
    r"\b(\d{1,2})(?:st|nd|rd|th)?\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?,?\s+(\d{4})\b",
    re.I)
_RE_YMD_SLASH = re.compile(r"\b(\d{4})/(\d{1,2})/(\d{1,2})\b")
_RE_CLOCK = re.compile(r"\b(\d{1,2}):(\d{2})\s*([ap])\.?m\.?\b", re.I)


def _text(value) -> str:
    if value is None:
        return ""
    return value if isinstance(value, str) else str(value)


def canonicalize(text: str, now: datetime | None = None) -> tuple[str, list[str]]:
    """One shape for the same fact, so two tellings are two spellings no more.

    What is canonicalized, and what is NOT: dates become ISO-8601 (a memory that
    says "yesterday" is unreadable the day after), clocks become 24-hour, unicode
    is normalized, and whitespace is collapsed. Prose is never rewritten — the
    words a keeper wrote are the words it must read back."""
    notes: list[str] = []
    if not text:
        return "", notes
    out = unicodedata.normalize("NFC", _text(text))
    out = out.replace("\u00a0", " ").replace("\u200b", "").replace("\r\n", "\n")
    now = now or datetime.now(timezone.utc)
    if now.tzinfo is None:
        now = now.replace(tzinfo=timezone.utc)

    def rel(m: re.Match) -> str:
        word = m.group(1).lower()
        delta = {"today": 0, "yesterday": -1, "tomorrow": 1}[word]
        iso = (now + timedelta(days=delta)).strftime("%Y-%m-%d")
        notes.append(f"date {word!r} -> {iso}")
        return iso

    out = _RE_REL_DAY.sub(rel, out)

    def mon_d(m: re.Match) -> str:
        iso = f"{int(m.group(3)):04d}-{_MONTHS[m.group(1)[:3].lower()]:02d}-{int(m.group(2)):02d}"
        notes.append(f"date {m.group(0)!r} -> {iso}")
        return iso

    def d_mon(m: re.Match) -> str:
        iso = f"{int(m.group(3)):04d}-{_MONTHS[m.group(2)[:3].lower()]:02d}-{int(m.group(1)):02d}"
        notes.append(f"date {m.group(0)!r} -> {iso}")
        return iso

    def ymd(m: re.Match) -> str:
        iso = f"{int(m.group(1)):04d}-{int(m.group(2)):02d}-{int(m.group(3)):02d}"
        notes.append(f"date {m.group(0)!r} -> {iso}")
        return iso

    out = _RE_MON_D.sub(mon_d, out)
    out = _RE_D_MON.sub(d_mon, out)
    out = _RE_YMD_SLASH.sub(ymd, out)

    def clock(m: re.Match) -> str:
        hour, minute, half = int(m.group(1)), m.group(2), m.group(3).lower()
        if half == "p" and hour != 12:
            hour += 12
        elif half == "a" and hour == 12:
            hour = 0
        iso = f"{hour:02d}:{minute}"
        notes.append(f"time {m.group(0)!r} -> {iso}")
        return iso

    out = _RE_CLOCK.sub(clock, out)
    out = re.sub(r"[ \t]+", " ", out)
    out = re.sub(r" *\n *", "\n", out)
    out = re.sub(r"\n{3,}", "\n\n", out).strip()
    return out, notes


def canonical_actor(name: str) -> str:
    """One name for one hand: `Deck`, `deck `, `DECK` are the same keeper."""
    s = unicodedata.normalize("NFKD", _text(name)).encode("ascii", "ignore").decode()
    s = re.sub(r"[\s_]+", "-", s.strip().lower())
    s = re.sub(r"[^a-z0-9.-]", "", s)
    return re.sub(r"-{2,}", "-", s).strip("-")


def canonical_actors(actors) -> list[str]:
    seen: list[str] = []
    for a in actors or []:
        c = canonical_actor(a)
        if c and c not in seen:
            seen.append(c)
    return seen


def canonical_tags(tags) -> list[str]:
    """Tags are lowercase, single-token labels; a tag with a colon keeps its key.

    A tag is a shelf, not a sentence: `store:semantic` filters, `Store: Semantic`
    does not. Values are slugged so two spellings cannot fork one shelf."""
    out: list[str] = []
    for t in tags or []:
        raw = _text(t).strip()
        if not raw:
            continue
        if ":" in raw:
            key, _, val = raw.partition(":")
            c = f"{canonical_actor(key)}:{canonical_actor(val)}"
        else:
            c = canonical_actor(raw)
        if c and c not in out:
            out.append(c)
    return out


def tokenize(text: str) -> set:
    words = re.findall(r"[a-z0-9][a-z0-9_-]{2,}", _text(text).lower())
    return {w for w in words if w not in STOPWORDS}


def similarity(a: str, b: str) -> float:
    """Jaccard over the content words — cheap, deterministic, and honest enough
    to tell a re-telling from a new lesson."""
    ta, tb = tokenize(a), tokenize(b)
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / len(ta | tb)


def content_hash(text: str) -> str:
    return hashlib.sha256(_text(text).encode("utf-8")).hexdigest()


# ── the gate ─────────────────────────────────────────────────────────────────

def infer_store(content: str, declared: str | None = None) -> str:
    if declared:
        d = _text(declared).strip().lower()
        if d in STORES:
            return d
    low = _text(content).lower()
    for store, patterns in STORE_SIGNALS:
        for p in patterns:
            if re.search(p, low):
                return store
    return "episodic"


def secret_shape(text: str) -> str | None:
    """The first secret-shaped thing in the text, named but never echoed."""
    for p in SECRET_PATTERNS:
        if re.search(p, _text(text)):
            return p
    return None


def answered(content: str, shape: str | None = None) -> list[str]:
    """Which of the three questions this write answers (empty = drop it)."""
    if shape:
        s = _text(shape).strip().lower()
        key = {"behaviour": "changes-behavior", "behavior": "changes-behavior",
               "changes-behaviour": "changes-behavior",
               "changes-behavior": "changes-behavior", "commitment": "commitment",
               "decision": "decision"}.get(s)
        if key:
            return [key]
    low = _text(content).lower()
    hit = []
    for q, patterns in SIGNALS.items():
        if any(re.search(p, low) for p in patterns):
            hit.append(q)
    return hit


def decide(
    content: str,
    *,
    tags=None,
    actors=None,
    task: str | None = None,
    source: str = "unknown",
    store: str | None = None,
    shape: str | None = None,
    salience: float | None = None,
    confidence: float | None = None,
    privacy: str = "internal",
    retention: str = "keep",
    scope: str = "house",
    corpus=None,
    now: datetime | None = None,
    force: bool = False,
) -> dict:
    """Ask the three questions, then canonicalize, dedupe, score and tag.

    Returns one dict the bridge and the CLI both print:
      keep         may this be stored?
      why          one plain sentence — the gate's own account of itself
      matched      which of the three questions answered yes
      store        episodic | semantic | procedural
      content      canonical text (what gets written)
      tags         the caller's tags + the provenance tags
      salience     caller's value, else novelty/relevance scored
      novelty      how unlike the corpus it is (0..1)
      relevance    how close to the stated task (0..1)
      duplicate_of the id of an episode that already says this
      notes        every canonicalization applied, named
      provenance   the engine's own word: user | tool | external
      quarantined  the writer had read untrusted content
      meta         source/scope/confidence/privacy/retention/store/gate
    """
    notes: list[str] = []
    text, date_notes = canonicalize(content, now)
    notes.extend(date_notes)
    declared_privacy = _text(privacy).strip().lower() or "internal"
    meta = {
        "source": canonical_actor(source) or "unknown",
        "scope": canonical_actor(scope) or "house",
        "store": infer_store(text, store),
        "confidence": round(float(confidence if confidence is not None else 0.7), 3),
        "privacy": declared_privacy,
        "retention": _text(retention).strip().lower() or "keep",
        "task": (_text(task).strip() or None),
    }

    def drop(why: str, **extra) -> dict:
        out = {
            "keep": False, "why": why, "matched": [], "store": meta["store"],
            "content": text, "tags": canonical_tags(tags), "salience": 0.0,
            "novelty": 0.0, "relevance": 0.0, "duplicate_of": None,
            "notes": notes, "provenance": provenance_word(meta["source"]),
            "quarantined": declared_privacy == "untrusted", "meta": meta,
        }
        out.update(extra)
        return out

    if not text or len(text) < 12:
        return drop("too short to be a lesson — the gate keeps nothing it cannot read back")
    if text.strip().lower() in ("undefined", "null", "none", "n/a", "test"):
        return drop("not a lesson — a missing field serialised as content")

    if declared_privacy in REFUSED_CLASSES:
        return drop(REFUSED_CLASSES[declared_privacy], refused=declared_privacy)

    secret = secret_shape(text)
    if secret:
        return drop("secret-shaped content is never watered in (Rules 15/24) — reference it by path instead",
                    refused="secret")

    matched = answered(text, shape)
    if not matched and not force:
        return drop("answers none of the three questions (behaviour · commitment · decision) — dropped, not stored")
    if not matched:
        matched = ["forced"]

    corpus = list(corpus or [])
    best_sim, best_id = 0.0, None
    digest = content_hash(text)
    for ep in corpus:
        other = _text(ep.get("content"))
        if _text(ep.get("hash")) == digest or (other and content_hash(other) == digest):
            return drop("already in the well — byte for byte (deduplicated)",
                        duplicate_of=ep.get("id") or ep.get("hash"))
        sim = similarity(text, other)
        if sim > best_sim:
            best_sim, best_id = sim, ep.get("id")

    if best_sim >= 0.85 and best_id:
        return drop("already in the well — the same lesson in other words (deduplicated)",
                    duplicate_of=best_id, novelty=round(1.0 - best_sim, 3))

    novelty = round(1.0 - best_sim, 3)
    relevance = 0.5
    if meta["task"]:
        tt, ct = tokenize(meta["task"]), tokenize(text)
        relevance = round(len(tt & ct) / len(tt), 3) if tt else 0.5

    if salience is None:
        salience = max(0.2, min(1.0, 0.5 + 0.3 * novelty + 0.2 * relevance))
    salience = round(max(0.0, min(1.0, float(salience))), 3)

    meta["gate"] = {
        "matched": matched, "novelty": novelty, "relevance": relevance,
        "forced": bool(force and shape is None and matched == ["forced"]),
        "notes": notes,
    }
    tags_out = canonical_tags(list(tags or []) + provenance_tags(meta))
    if not tags_out:
        tags_out = ["well"]
    return {
        "keep": True,
        "why": f"answers {', '.join(matched)}; novel ({novelty}) · relevant ({relevance})",
        "matched": matched, "store": meta["store"], "content": text,
        "tags": tags_out, "salience": salience, "novelty": novelty,
        "relevance": relevance, "duplicate_of": None, "notes": notes,
        "provenance": provenance_word(meta["source"]),
        "quarantined": declared_privacy == "untrusted", "meta": meta,
    }


def provenance_word(source: str) -> str:
    """The engine's own vocabulary — it refuses anything else, measured:
    `from engram.models import PROVENANCES` -> ('user','tool','external')."""
    s = canonical_actor(source)
    if s in ("allfather", "odin", "user", "operator", "human"):
        return "user"
    if s in ("tool", "bridge", "mcp", "well", "cli") or s.startswith("tool"):
        return "tool"
    return "external"


def provenance_tags(meta: dict) -> list[str]:
    """The record an episode carries besides its content and its labels.

    `store:` is the shelf (the type), `src:` the hand that wrote it, `scope:` the
    reach, `conf:` how sure the writer was, `privacy:` the class the ward reads,
    `retain:` the rule that says when it may be archived. All of them are tags so
    that every existing reader — the CLI, the UI, the MCP server, a `grep` on the
    log — sees them without being taught a new column."""
    out = [f"store:{meta.get('store', 'episodic')}",
           f"src:{meta.get('source', 'unknown')}",
           f"scope:{meta.get('scope', 'house')}",
           f"conf:{meta.get('confidence', 0.7)}",
           f"privacy:{meta.get('privacy', 'internal')}",
           f"retain:{meta.get('retention', 'keep')}"]
    task = meta.get("task")
    if task:
        out.append(f"task:{canonical_actor(task)}")
    return out


def correction_tags(original_id: str, kind: str = "corrects") -> list[str]:
    """The chain, by id, in both directions: the replacement NAMES the original
    (`corrects:<id>` / `retracts:<id>` / `consolidates:<id>`), and the original is
    annotated `void:<new>` so recall stops surfacing it. Nothing is erased."""
    kind = _text(kind).strip().lower() or "corrects"
    return [f"{kind}:{original_id}", f"voids:{original_id}"]


def values_in(tags, prefix: str) -> list[str]:
    """Every `prefix:<value>` in a tag list — how a void is found without SQL."""
    pre = f"{_text(prefix).lower()}:"
    return [t.split(":", 1)[1] for t in (canonical_tags(tags) if tags else [])
            if _text(t).lower().startswith(pre)]


def is_void(tags) -> bool:
    return any(_text(t).lower().startswith("void:") for t in (tags or []))


def is_archived(tags) -> bool:
    return any(_text(t).lower().startswith("archived:") for t in (tags or []))


def store_of(tags) -> str:
    vals = values_in(tags, "store")
    for v in vals:
        if v in STORES:
            return v
    return "episodic"


# ── the store, read without the engine ───────────────────────────────────────

def ymir_home() -> Path:
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


def default_store() -> Path:
    return Path(os.environ.get("ENGRAM_DB",
                               str(ymir_home() / "hodd/memory/kaia.engram"))).expanduser()


def state_dir(store: Path | None = None) -> Path:
    """Where runtime state lives — never in the code tree (Rule 04).

    env first; then the home the store was found in; then the store's own shelf
    (a temp or out-of-tree store keeps its state beside itself, which is what a
    test wants and what a packaged install must never depend on)."""
    env = os.environ.get("YMIR_STATE_DIR")
    if env:
        return Path(env).expanduser()
    store = store or default_store()
    candidates = [store.parent.parent.parent / "state", store.parent / "state"]
    home = ymir_home()
    if str(store).startswith(str(home)):
        candidates.insert(0, home / "state")
    for c in candidates:
        if c.parent.exists() and os.access(c.parent, os.W_OK):
            return c
    return candidates[-1]


def grading_state(store: Path | None = None) -> Path:
    return state_dir(store) / ".well-grading.json"


def log_path(store: Path | None = None) -> Path:
    return Path(os.environ.get(
        "ENGRAM_LOG", str((store or default_store()).parent / "well" / "episodes.jsonl"))).expanduser()


def _connect(store: Path) -> sqlite3.Connection | None:
    try:
        con = sqlite3.connect(f"file:{store}?mode=ro", uri=True, timeout=2)
        con.row_factory = sqlite3.Row
        return con
    except Exception:
        return None


def _json_list(value) -> list:
    if isinstance(value, list):
        return value
    try:
        out = json.loads(value or "[]")
        return out if isinstance(out, list) else [str(out)]
    except Exception:
        return []


def _row_episode(r) -> dict:
    return {
        "id": r["id"], "content": r["content"] or "",
        "timestamp": r["timestamp"], "tags": _json_list(r["tags"]),
        "actors": _json_list(r["actors"]), "salience": r["salience"],
        "importance": r["importance_score"], "agent_id": r["agent_id"],
    }


def read_corpus(store: Path | None = None, limit: int = 800) -> list[dict]:
    """The recent well, as plain rows — what the gate compares a write against.

    The store first (it has ids and salience); the append log when the store
    cannot be read, so the gate is never blind and never judging nothing."""
    store = store or default_store()
    rows: list[dict] = []
    con = _connect(store)
    if con is not None:
        try:
            for r in con.execute(
                "select id, content, timestamp, tags, actors, salience, importance_score, agent_id "
                "from episodes order by timestamp desc limit ?", (limit,)):
                rows.append(_row_episode(r))
        except Exception:
            rows = []
        finally:
            con.close()
    if rows:
        return rows
    try:
        for line in log_path(store).read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                e = json.loads(line)
            except Exception:
                continue
            e.setdefault("id", e.get("hash"))
            rows.append(e)
    except OSError:
        pass
    return rows[-limit:]


# ── the one health row (what Eir reports) ────────────────────────────────────

def _iso_age_days(value, now: datetime) -> float | None:
    if not value:
        return None
    text = str(value).strip().replace("Z", "+00:00")
    try:
        moment = datetime.fromisoformat(text)
    except ValueError:
        return None
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return round((now - moment).total_seconds() / 86400.0, 2)


def memory_row(store: Path | None = None, now: datetime | None = None) -> dict:
    """Well size · last observe · last recall · last daily entry · last pruning
    run. Measured from the record itself — the store, the access log, the daily
    shelf, the grading state — never from a note about them."""
    store = store or default_store()
    now = now or datetime.now(timezone.utc)
    row = {
        "store": str(store), "readable": store.exists(), "episodes": 0,
        "last_observe": None, "last_recall": None, "last_daily": None,
        "last_prune": None, "stores": {s: 0 for s in STORES}, "voided": 0,
        "grading": None, "why": "",
    }
    con = _connect(store)
    if con is not None:
        try:
            row["episodes"] = int(con.execute("select count(*) from episodes").fetchone()[0])
            # Counted in SQL, not in a Python loop over every row: /health is polled
            # by the UI, by Eir and by every tool's boot probe, and a count that is
            # O(all episodes) turns a health check into a scan of the whole memory.
            for shelf in ("semantic", "procedural"):
                row["stores"][shelf] = int(con.execute(
                    "select count(*) from episodes where instr(coalesce(tags,'[]'), ?) > 0",
                    (f"store:{shelf}",)).fetchone()[0])
            # Episodic is the DEFAULT shelf, so an episode written before the three
            # shelves existed belongs there — reporting it as shelfless would say
            # 122 episodes and 0 memories on the house well (measured 2026-10-26).
            row["stores"]["episodic"] = max(
                0, row["episodes"] - row["stores"]["semantic"] - row["stores"]["procedural"])
            row["voided"] = int(con.execute(
                "select count(*) from episodes where instr(coalesce(tags,'[]'), 'void:') > 0"
            ).fetchone()[0])
            row["last_observe"] = con.execute("select max(timestamp) from episodes").fetchone()[0]
            try:
                row["last_recall"] = con.execute("select max(accessed_at) from access_log").fetchone()[0]
            except Exception:
                row["last_recall"] = None
        except Exception:
            row["readable"] = False
        finally:
            con.close()
    daily = store.parent / "daily"
    try:
        days = sorted(p.stem for p in daily.glob("*.md"))
        row["last_daily"] = days[-1] if days else None
    except OSError:
        pass
    try:
        g = json.loads(grading_state(store).read_text(encoding="utf-8"))
        row["last_prune"] = g.get("finished_at")
        row["grading"] = {k: g.get(k) for k in ("grades", "consolidated", "archived", "documents_moved")}
    except (OSError, ValueError):
        pass

    age = _iso_age_days
    row["age_days"] = {
        "observe": age(row["last_observe"], now),
        "recall": age(row["last_recall"], now),
        "daily": (round((now.date() - datetime.strptime(row["last_daily"], "%Y-%m-%d").date()).days, 2)
                  if row["last_daily"] else None),
        "prune": age(row["last_prune"], now),
    }

    # HEALTH: the door answers or it does not, and a memory no one writes to is
    # failing its one job. Staleness is reported, not hidden; a stale well is red.
    problems = []
    if not row["readable"]:
        problems.append(f"store unreadable at {store}")
    elif row["episodes"] == 0:
        problems.append("the well holds no episodes")
    a = row["age_days"]
    if a["observe"] is None:
        problems.append("nothing has ever been observed")
    elif a["observe"] > 30:
        problems.append(f"last observe {a['observe']}d ago")
    if a["prune"] is None:
        problems.append("grading has never run (bin/records/mimir.sh grade)")
    elif a["prune"] > 45:
        problems.append(f"last grading {a['prune']}d ago")
    # The day's shape: the well holds what was learned, the daily log holds what
    # the day was. One without the other is a memory with no story, so a well
    # that has been fed for a week with no daily entry is reported, not hidden.
    if row["episodes"] > 0:
        if a["daily"] is None:
            problems.append("no daily entry has ever been written (bin/records/daily-log.sh add)")
        elif a["daily"] > 7:
            problems.append(f"last daily entry {a['daily']}d ago")
    row["healthy"] = not problems
    row["why"] = "; ".join(problems) if problems else "well answering, recent, and pruned"
    return row


# ── continuous forgetting: grading, decay, consolidation, reference ──────────

def _grade_episode(ts: datetime, accessed: datetime | None, tags: list, importance: float,
                   now: datetime) -> tuple[str, str]:
    """nýr · eldri · forn · safn, from two honest signals: how long since it last
    mattered (written OR read) and whether it was archived on purpose."""
    if is_archived(tags):
        return "safn", "archived on purpose — moved to reference, read but not edited"
    last = accessed or ts
    if last.tzinfo is None:
        last = last.replace(tzinfo=timezone.utc)
    age = (now - last).days
    written = (now - (ts if ts.tzinfo else ts.replace(tzinfo=timezone.utc))).days
    if age <= FRESH_DAYS:
        return "nýr", f"read or written {age}d ago"
    if age <= AGING_DAYS:
        return "eldri", f"{age}d since it last mattered"
    if written <= OLD_DAYS and age <= OLD_DAYS:
        return "eldri", f"{written}d old, read {age}d ago"
    if importance >= 0.6:
        return "eldri", f"{written}d old but carrying weight (importance {importance})"
    return "forn", f"{written}d old, last read {age}d ago"


def grade(store: Path | None = None, apply: bool = False, now: datetime | None = None) -> dict:
    """The continuous pass. Report by default; `apply` annotates and moves.

    In order: decay (recency × access frequency, through the engine), grade every
    episode, consolidate exact duplicates, archive retention-expired episodes,
    move superseded documents to `hodd/reference/`. The episode count is checked
    before and after and a run that lowers it is a FAILURE — Rule 20."""
    store = store or default_store()
    now = now or datetime.now(timezone.utc)
    report = {
        "at": now.isoformat().replace("+00:00", "Z"), "store": str(store),
        "apply": bool(apply), "episodes_before": 0, "episodes_after": 0,
        "grades": {g: 0 for g in GRADES}, "decayed": 0, "consolidated": 0,
        "archived": 0, "documents_moved": [], "documents_kept": [],
        "candidates": [], "notes": [], "ok": True,
    }
    con = _connect(store)
    if con is None:
        report["ok"] = False
        report["notes"].append(f"store unreadable at {store}")
        return report
    try:
        episodes = [_row_episode(r) for r in con.execute(
            "select id, content, timestamp, tags, actors, salience, importance_score, agent_id "
            "from episodes order by timestamp")]
        try:
            access = {r[0]: r[1] for r in con.execute(
                "select memory_id, max(accessed_at) from access_log group by memory_id")}
        except Exception:
            access = {}
    finally:
        con.close()
    report["episodes_before"] = report["episodes_after"] = len(episodes)

    def _dt(value):
        if isinstance(value, datetime):
            return value
        try:
            return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        except Exception:
            return now

    graded: list[tuple[dict, str, str]] = []
    for ep in episodes:
        last = access.get(ep["id"])
        g, why = _grade_episode(_dt(ep["timestamp"]),
                                _dt(last) if last else None,
                                ep["tags"], float(ep["importance"] or 0), now)
        report["grades"][g] += 1
        graded.append((ep, g, why))

    # Consolidation: the same lesson told twice is one lesson and a copy. Exact
    # content hashes are collapsed by annotating the LATER copies void — an
    # annotation, never a delete, and the first telling stands as the record.
    by_hash: dict[str, dict] = {}
    void_annotations: list[tuple[str, str]] = []
    for ep in episodes:
        if is_void(ep["tags"]):
            continue
        h = content_hash(ep["content"])
        first = by_hash.get(h)
        if first is None:
            by_hash[h] = ep
            continue
        void_annotations.append((ep["id"], first["id"]))
        report["candidates"].append({
            "kind": "exact-duplicate", "keep": first["id"], "void": ep["id"],
            "why": "the same content, byte for byte — the earlier telling stands",
        })
    # Near-duplicates are REPORTED, never merged by a script: a summary written by
    # a machine is an invented fact. Consolidation of near-duplicates is a keeper's act.
    seen: list[dict] = []
    for ep, g, why in graded:
        if g not in ("eldri", "forn") or is_void(ep["tags"]):
            continue
        for other in seen:
            sim = similarity(ep["content"], other["content"])
            if sim >= 0.70:
                report["candidates"].append({
                    "kind": "overlap", "a": other["id"], "b": ep["id"],
                    "similarity": round(sim, 2),
                    "why": "two tellings of one lesson — consolidate by appending one summary that names both",
                })
                break
        else:
            seen.append(ep)
    # Retention: an episode written with a short rule is archived, not erased.
    archive_annotations: list[tuple[str, str]] = []
    for ep in episodes:
        if is_void(ep["tags"]) or is_archived(ep["tags"]):
            continue
        rules = values_in(ep["tags"], "retain")
        if not any(r == RETENTION_EPHEMERAL or r.startswith("season:") for r in rules):
            continue
        limit = 7
        for r in rules:
            if r.startswith("season:"):
                try:
                    limit = int(r.split(":", 1)[1])
                except ValueError:
                    limit = 7
        age = (now - _dt(ep["timestamp"])).days
        if age > limit:
            archive_annotations.append((ep["id"], now.strftime("%Y-%m-%d")))
            report["candidates"].append({
                "kind": "retention-expired", "id": ep["id"],
                "why": f"written to be kept {limit}d, stored {age}d — archived, still in the record",
            })

    if not apply:
        report["notes"].append("report only — re-run with --apply to decay, annotate and move")
        return report

    # ── apply ────────────────────────────────────────────────────────────────
    try:
        from engram import Engram  # noqa: PLC0415
        # UNSCOPED on purpose: a decay pass scoped to one keeper would recompute
        # only that keeper's scores, and the well is ONE well (measured: an
        # agent-scoped `decay()` returned 0 over four episodes belonging to
        # `deck`). The house prunes the house.
        eng = Engram(path=str(store))
        report["decayed"] = eng.decay()
        eng.close()
    except Exception as exc:  # noqa: BLE001
        report["notes"].append(f"decay skipped ({type(exc).__name__}: {exc}) — the engine owns the score")

    try:
        con = sqlite3.connect(str(store), timeout=5)
        try:
            for eid, keep_id in void_annotations:
                _annotate(con, eid, [f"void:{keep_id}", "consolidated:exact-duplicate"])
                report["consolidated"] += 1
            for eid, day in archive_annotations:
                _annotate(con, eid, [f"archived:{day}"])
                report["archived"] += 1
            con.commit()
        finally:
            con.close()
    except Exception as exc:  # noqa: BLE001
        report["ok"] = False
        report["notes"].append(f"annotation failed: {type(exc).__name__}: {exc}")

    moved, kept = _grade_documents(store, now=now)
    report["documents_moved"], report["documents_kept"] = moved, kept

    after = _connect(store)
    if after is not None:
        try:
            report["episodes_after"] = int(after.execute("select count(*) from episodes").fetchone()[0])
        except Exception:
            pass
        finally:
            after.close()
    if report["episodes_after"] < report["episodes_before"]:
        report["ok"] = False
        report["notes"].append("THE COUNT FELL — this run was a loss, not a tidy-up (Rule 20)")

    try:
        st = grading_state(store)
        st.parent.mkdir(parents=True, exist_ok=True)
        st.write_text(json.dumps({
            "finished_at": now.isoformat().replace("+00:00", "Z"),
            "grades": report["grades"], "decayed": report["decayed"],
            "consolidated": report["consolidated"], "archived": report["archived"],
            "documents_moved": [d["path"] for d in report["documents_moved"]],
            "episodes": report["episodes_after"], "ok": report["ok"],
        }, indent=1), encoding="utf-8")
    except OSError as exc:
        report["notes"].append(f"could not write the grading state: {exc}")
    return report


def _annotate(con: sqlite3.Connection, episode_id: str, add: list[str]) -> None:
    """Add tags to an episode. Content is untouchable; tags are the annotation
    Rule 20 permits — which is how a void, an archive or a consolidation is
    recorded without rewriting a word of what was written."""
    row = con.execute("select tags from episodes where id = ?", (episode_id,)).fetchone()
    if not row:
        return
    tags = _json_list(row[0])
    merged = tags + [t for t in add if t not in tags]
    con.execute("update episodes set tags = ? where id = ?",
                (json.dumps(merged, ensure_ascii=False), episode_id))


def _grade_documents(store: Path, now: datetime | None = None) -> tuple[list[dict], list[dict]]:
    """Old documents MOVE to `hodd/reference/` — with why they went and what
    replaced them — and only when the document itself DECLARES a successor.

    A guess is not a reason to move a record. Two guards, both deliberate:
    a document without a declared `superseded_by:` is reported and stays, and the
    append-only / live records (the runes, the operator record, the learnings)
    are never moved at all."""
    now = now or datetime.now(timezone.utc)
    hodd = store.parent.parent
    ref = hodd / "reference"
    moved: list[dict] = []
    kept: list[dict] = []
    never = {"runes_audit.md", "operator.md", "learnings.md", "projects.md"}
    try:
        docs = [p for p in hodd.rglob("*.md")
                if ".git" not in p.parts and "reference" not in p.parts
                and "node_modules" not in p.parts and p.name not in never]
    except OSError:
        return moved, kept
    for doc in docs[:600]:
        rel = doc.relative_to(hodd)
        try:
            head = "\n".join(doc.read_text(encoding="utf-8", errors="replace").splitlines()[:12])
        except OSError:
            continue
        sup = re.search(r"(?im)^\s*(?:superseded_by|superseded-by|replaced_by):\s*(\S+)", head)
        if not sup:
            continue
        if sup.group(1).strip().lower() in ("none", "-", "null"):
            continue
        try:
            out = os.popen(f'git -C "{hodd.parent}" log -1 --format=%ct -- "{doc}"').read().strip()
            age = (now.timestamp() - int(out)) / 86400.0 if out.isdigit() else 0.0
        except Exception:
            age = 0.0
        if age <= OLD_DAYS:
            kept.append({"path": str(rel), "why": f"declares a successor but only {int(age)}d old — still live"})
            continue
        target = ref / rel
        why = (f"graded forn after {int(age)}d; superseded by {sup.group(1).strip()}. "
               f"Moved here {now.strftime('%Y-%m-%d')} by the well's grading pass (plan 136). "
               f"Nothing was deleted — a record of what was believed, not what is.")
        try:
            target.parent.mkdir(parents=True, exist_ok=True)
            body = doc.read_text(encoding="utf-8", errors="replace")
            target.write_text(f"<!-- {why} -->\n\n{body}", encoding="utf-8")
            if target.stat().st_size >= doc.stat().st_size:
                doc.unlink()
                moved.append({"path": str(rel), "to": str(target.relative_to(hodd)),
                              "why": why, "superseded_by": sup.group(1).strip()})
            else:
                kept.append({"path": str(rel), "why": "the copy did not survive the write — original kept"})
        except OSError as exc:
            kept.append({"path": str(rel), "why": f"could not move: {exc}"})
    return moved, kept


# ── the door ─────────────────────────────────────────────────────────────────

def _toon_decision(d: dict) -> str:
    meta = d.get("meta") or {}
    lines = [f'gate[1]{{keep,store,novelty,relevance,salience,source}}:',
             f'  "{str(d["keep"]).lower()}","{d["store"]}",{d["novelty"]},{d["relevance"]},'
             f'{d["salience"]},"{meta.get("source", "?")}"',
             f'why: {d["why"]}']
    if d.get("duplicate_of"):
        lines.append(f'duplicate_of: {d["duplicate_of"]}')
    if d.get("matched"):
        lines.append(f'matched: {", ".join(d["matched"])}')
    if d.get("notes"):
        lines.append(f'canonicalized: {"; ".join(d["notes"])}')
    if d["keep"]:
        lines.append(f'tags: {", ".join(d["tags"])}')
    return "\n".join(lines)


def _toon_grades(r: dict) -> str:
    g = r["grades"]
    lines = [
        f'grading[1]{{mode,episodes,decayed,consolidated,archived,docs_moved,ok}}:',
        f'  "{"applied" if r["apply"] else "report"}",{r["episodes_after"]},{r["decayed"]},'
        f'{r["consolidated"]},{r["archived"]},{len(r["documents_moved"])},"{str(r["ok"]).lower()}"',
        'grades[4]{grade,count,meaning}:',
    ]
    for name in GRADES:
        lines.append(f'  "{name}",{g[name]},"{GRADE_MEANING[name]}"')
    for c in r["candidates"][:20]:
        lines.append(f'  candidate {c["kind"]}: {c.get("why", "")} '
                     f'({", ".join(str(c[k]) for k in ("id", "a", "b", "keep", "void") if c.get(k))})')
    for d in r["documents_moved"]:
        lines.append(f'  moved {d["path"]} -> {d["to"]} (superseded by {d["superseded_by"]})')
    for d in r["documents_kept"][:10]:
        lines.append(f'  kept {d["path"]} — {d["why"]}')
    for n in r["notes"]:
        lines.append(f'note: {n}')
    return "\n".join(lines)


def _toon_memory(row: dict) -> str:
    a = row.get("age_days") or {}
    stores = ", ".join(f"{k}:{v}" for k, v in row["stores"].items())
    lines = [
        'memory[1]{episodes,voided,last_observe,last_recall,last_daily,last_prune,healthy}:',
        f'  {row["episodes"]},{row["voided"]},"{row["last_observe"] or "never"}",'
        f'"{row["last_recall"] or "never"}","{row["last_daily"] or "never"}",'
        f'"{row["last_prune"] or "never"}","{str(row["healthy"]).lower()}"',
        f'stores: {stores}',
        f'days: observe={a.get("observe")} recall={a.get("recall")} daily={a.get("daily")} prune={a.get("prune")}',
        f'why: {row["why"]}',
    ]
    return "\n".join(lines)


def memory_line(row: dict) -> str:
    """One terse line for a health row: the five numbers and the reason.

    Eir's rows are read by a person in a table, so the row is a sentence, not a
    dump of the TOON block (2026-10-26: the first version pasted three lines of
    quotes into the detail column and became unreadable)."""
    a = row.get("age_days") or {}

    def age(key: str) -> str:
        v = a.get(key)
        if v is None:
            return "never"
        return f"{int(v)}d" if v >= 1 else "today"

    return (f'{row["episodes"]} eps · {row["voided"]} void · '
            f'{" ".join(f"{k}:{v}" for k, v in row["stores"].items())} · '
            f'observe {age("observe")} · recall {age("recall")} · '
            f'daily {age("daily")} · prune {age("prune")} — {row["why"]}')


def _self_test() -> int:
    """Prove the policy bites — on a throwaway well, never the real one.

    Each check is a claim plan 136 makes, and each one can fail:
      1 the gate DROPS a write that answers none of the three questions
      2 the gate DROPS a duplicate, and names the episode it duplicates
      3 the gate KEEPS a decision, typed semantic, with provenance tags
      4 dates and names are canonicalized (yesterday -> ISO, Deck -> deck)
      5 a secret is refused, and the vault with it
      6 a retraction appends, chains by id, and leaves the original in place
      7 scoped recall sees only its own store
      8 grading never lowers the count and archives what expired
    """
    fails = 0

    def check(name: str, ok: bool, detail: str = "") -> None:
        nonlocal fails
        if ok:
            print(f"  {name:<46} PASS")
        else:
            fails += 1
            print(f"  {name:<46} FAIL {detail}")

    now = datetime(2026, 10, 26, 12, 0, tzinfo=timezone.utc)
    corpus = [{"id": "e1", "content": "Next time, always run the smoke test before pushing the branch.",
               "tags": ["store:procedural"]}]

    d = decide("The sky is blue.", corpus=corpus, now=now)
    check("a write answering no question is dropped", not d["keep"], d["why"])
    check("  ... and says which questions it failed", "three questions" in d["why"], d["why"])

    d = decide("Step 1: raise the bridge. Then run the smoke test so the well answers.", now=now)
    check("a documented workflow is kept", d["keep"], d["why"])
    check("  ... typed procedural", d["store"] == "procedural", d["store"])

    d = decide("Next time, always run the smoke test before pushing the branch.", corpus=corpus, now=now)
    check("a duplicate is dropped", not d["keep"], d["why"])
    check("  ... naming the episode it duplicates", d.get("duplicate_of") == "e1", str(d.get("duplicate_of")))

    d = decide("We decided the well's write gate asks three questions because noise kills recall.",
               corpus=corpus, now=now, source="brokk", task="memory architecture gate")
    check("a decision with rationale is kept", d["keep"], d["why"])
    check("  ... typed semantic", d["store"] == "semantic", d["store"])
    check("  ... carrying provenance tags",
          all(any(t.startswith(p) for t in d["tags"]) for p in ("src:", "scope:", "conf:", "privacy:", "retain:")),
          str(d["tags"]))
    check("  ... scored by novelty and relevance", d["novelty"] > 0.5 and d["relevance"] > 0, str(d))

    text, notes = canonicalize("Yesterday at 9:05 pm Deck said Oct 26, 2026 is the day.", now=now)
    check("dates canonicalized to ISO", "2026-10-25" in text and "2026-10-26" in text, text)
    check("clock canonicalized to 24h", "21:05" in text, text)
    check("  ... and the change is named", any("yesterday" in n for n in notes), str(notes))
    check("names canonicalized", canonical_actor("  Deck ") == "deck" and canonical_actor("Deck_2") == "deck-2")

    d = decide("The host password: hunter2hunter2hunter2 and the api_key=abcdef1234567890 are set.")
    check("a secret is refused", not d["keep"] and d.get("refused") == "secret", d["why"])
    d = decide("The NDA contract says we must always keep their name private.", privacy="vault")
    check("the vault is refused", not d["keep"] and d.get("refused") == "vault", d["why"])

    tags = correction_tags("orig-id", "retracts")
    check("a retraction chains to the original by id",
          "retracts:orig-id" in tags and "voids:orig-id" in tags, str(tags))
    check("a void is recognised from tags", is_void(["store:episodic", "void:new-id"]))
    check("an archived episode is recognised", is_archived(["archived:2026-10-26"]))

    # The store side, on a throwaway engram-shaped database.
    with tempfile.TemporaryDirectory() as tmp:
        db = Path(tmp) / "test.engram"
        con = sqlite3.connect(str(db))
        con.executescript("""
          create table episodes (id text primary key, content text, timestamp datetime,
            actors json default '[]', tags json default '[]', salience real default 0.5,
            importance_score real default 1.0, agent_id text, provenance text, quarantined int);
          create table access_log (memory_id text, accessed_at datetime, query text, rank int);
        """)
        rows = [
            ("a", "The vault key design was decided: LUKS2 sealed until the operator opens it.",
             "2026-10-25T10:00:00+00:00", ["store:semantic", "retain:keep"], 1.0),
            ("b", "Ran the smoke test and it passed at 09:00.",
             "2025-01-01T09:00:00+00:00", ["store:episodic", "retain:ephemeral"], 0.2),
            ("c", "The vault key design was decided: LUKS2 sealed until the operator opens it.",
             "2026-10-25T11:00:00+00:00", ["store:semantic", "retain:keep"], 1.0),
        ]
        con.executemany("insert into episodes (id, content, timestamp, tags, importance_score) "
                        "values (?,?,?,?,?)",
                        [(i, c, t, json.dumps(g), imp) for i, c, t, g, imp in rows])
        con.commit()
        con.close()

        corpus = read_corpus(db)
        check("the store is read, not mocked", len(corpus) == 3, str(len(corpus)))
        semantic = [e for e in corpus if store_of(e["tags"]) == "semantic"]
        check("scoping by store narrows the slice", len(semantic) == 2, str(len(semantic)))

        r = grade(db, apply=False, now=now)
        check("grading reports without writing", r["apply"] is False and r["episodes_before"] == 3)
        check("  ... graded the old episode forn", r["grades"]["forn"] >= 1, str(r["grades"]))
        check("  ... found the exact duplicate", any(c["kind"] == "exact-duplicate" for c in r["candidates"]))
        check("  ... found the expired retention", any(c["kind"] == "retention-expired" for c in r["candidates"]))
        r2 = grade(db, apply=True, now=now)
        check("applying never lowers the count",
              r2["episodes_after"] >= r2["episodes_before"] == 3, str(r2["episodes_after"]))
        check("  ... it annotated, it did not erase", r2["episodes_after"] == 3)
        con = sqlite3.connect(str(db))
        tags_c = json.loads(con.execute("select tags from episodes where id='c'").fetchone()[0])
        content_c = con.execute("select content from episodes where id='c'").fetchone()[0]
        con.close()
        check("  ... the later copy is voided by the earlier", "void:a" in tags_c, str(tags_c))
        check("  ... and its content is untouched",
              content_c == rows[2][1], content_c)

    print(f'policy-selftest[1]{{fails,state}}:\n  {fails},"{"PASS" if fails == 0 else "FAIL"}"')
    return 0 if fails == 0 else 1


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return _self_test()
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 2
    verb, rest = argv[0], argv[1:]
    opts: dict[str, str] = {}
    flags: set[str] = set()
    i = 0
    while i < len(rest):
        a = rest[i]
        if a.startswith("--"):
            key = a[2:]
            if "=" in key:
                key, _, val = key.partition("=")
                opts[key] = val
                i += 1
                continue
            if i + 1 < len(rest) and not rest[i + 1].startswith("--"):
                opts[key] = rest[i + 1]
                i += 2
            else:
                flags.add(key)
                i += 1
            continue
        i += 1

    if verb == "gate":
        content = opts.get("content", "")
        if opts.get("content-file"):
            content = Path(opts["content-file"]).expanduser().read_text(encoding="utf-8", errors="replace")
        store = Path(opts["store"]).expanduser() if opts.get("store") else default_store()
        d = decide(
            content,
            tags=[t for t in opts.get("tags", "").split(",") if t.strip()],
            task=opts.get("task"), source=opts.get("source", "cli"),
            store=opts.get("store-type") or opts.get("type"),
            shape=opts.get("shape"), salience=float(opts["salience"]) if opts.get("salience") else None,
            confidence=float(opts["confidence"]) if opts.get("confidence") else None,
            privacy=opts.get("privacy", "internal"), retention=opts.get("retention", "keep"),
            scope=opts.get("scope", "house"), corpus=[] if "no-dedupe" in flags else read_corpus(store),
            force="force" in flags,
        )
        print(json.dumps(d, ensure_ascii=False, indent=1) if "json" in flags else _toon_decision(d))
        return 0 if d["keep"] else 1

    if verb == "grade":
        store = Path(opts["store"]).expanduser() if opts.get("store") else default_store()
        r = grade(store, apply="apply" in flags)
        print(json.dumps(r, ensure_ascii=False, indent=1) if "json" in flags else _toon_grades(r))
        return 0 if r["ok"] else 1

    if verb == "memory":
        store = Path(opts["store"]).expanduser() if opts.get("store") else default_store()
        if opts.get("bridge"):
            # Ask the process that owns SQLite, including its WAL and platform.
            # A client across SSH/WSL must not open a different local store.
            from urllib.request import urlopen
            try:
                with urlopen(opts["bridge"].rstrip("/") + "/health", timeout=5) as response:
                    row = json.load(response)
                required = {"episodes", "voided", "stores", "healthy", "why",
                            "last_observe", "last_recall", "last_daily", "last_prune"}
                if not required.issubset(row) or type(row["healthy"]) is not bool:
                    raise ValueError("bridge does not provide memory health")
                row["measurement"] = "bridge"
            except Exception as exc:
                print(f"error: bridge memory health unavailable ({type(exc).__name__}: {exc})")
                return 1
        else:
            row = memory_row(store)
            row["measurement"] = "local-file"
        if "line" in flags:
            print(memory_line(row))
        elif "json" in flags:
            print(json.dumps(row, ensure_ascii=False, indent=1))
        else:
            print(_toon_memory(row))
        return 0 if (row["healthy"] or "check" not in flags) else 1

    print(f"error: unknown verb {verb}\nhelp: mimir-policy.py [gate|grade|memory|--self-test]",
          file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
