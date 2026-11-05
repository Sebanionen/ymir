#!/usr/bin/env -S uv run
# /// script
# dependencies = []
# ///
"""smidja trace — one row per phase of a run: who ran, on what, how full the window.

Usage:
    uv run apps/smidja/smidja_trace.py <run-id> [--json] [--db PATH] [--config PATH]

Prints, from what the run already wrote — the SQLite trace, `raw_output.jsonl`,
`envelope.json`, `prompts/` — never from a new store:

    trace[3]{phase,owner,model,thinking,tools,tokens,window,percent,verdict}:
      "build","sindri","opencode-go/deepseek-v4.1-flash","high","bash,write,read","41203","1000000","4.1","room to work"

The verdicts are `bin/seat/context.sh`'s four words, plus two honest empties:

    room to work · past the auto threshold · near the window — compact now ·
    TRUNCATED · window unknown · no usage recorded

A phase that ended at or above the force threshold (75% of its window) is
`context-pressed`: its status is never `success` in the trace, the banner or the
session row, and this verb prints the verdict that names the pressure.

Exit: 0 when the run is found, 2 when it is not, 3 when the trace cannot be read.
"""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from smidja_modules import context as context_telemetry    # noqa: E402

EMPTY = "—"


# ── where the trace lives (one resolution, never a second table) ─────────────

def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def resolve_db(config_path: str | None = None) -> Path:
    """The trace DB, resolved the way every other reader resolves it.

    Order: an explicit `--db`, then the roster's `observability.db`, then the
    home's DB (where 0003-private-data-separation put it), then the in-repo
    fallback. A path that does not exist is returned as-is so the caller can say
    WHICH path was missing instead of inventing an empty result.
    """
    root = _repo_root()
    candidates: list[Path] = []
    if config_path:
        cfg = _config_db(config_path)
        if cfg:
            candidates.append(Path(cfg) if Path(cfg).is_absolute() else root / cfg)
    else:
        default_cfg = root / "apps" / "smidja" / "smidja_smidja_config" / "smidja.config.yaml"
        if default_cfg.is_file():
            cfg = _config_db(str(default_cfg))
            if cfg:
                candidates.append(Path(cfg) if Path(cfg).is_absolute() else root / cfg)
    home = os.environ.get("YMIR_HOME") or os.environ.get("YMIR_HOARD") \
        or os.path.expanduser("~/Documents/ymirhome")
    candidates.append(Path(home) / "smidja" / "smidja.db")
    candidates.append(root / "apps" / "smidja" / "smidja_data" / "smidja.db")
    for cand in candidates:
        if cand.is_file():
            return cand
    return candidates[-1]


def _config_db(config_path: str) -> str:
    """`observability.db` from the roster, without importing the whole loader."""
    try:
        import yaml
        raw = yaml.safe_load(Path(config_path).read_text()) or {}
        return str(((raw.get("observability") or {}).get("db")) or "")
    except Exception:
        return ""


def _data_dir(db_path: Path) -> Path:
    """Where the sessions/ shelf sits: beside the DB, or the tree's default."""
    beside = db_path.parent / "sessions"
    if beside.is_dir():
        return db_path.parent
    return _repo_root() / "apps" / "smidja" / "smidja_data"


# ── reading the trace ────────────────────────────────────────────────────────

def _open(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    return conn


def session_row(conn: sqlite3.Connection, run_id: str) -> dict | None:
    row = conn.execute("SELECT * FROM sessions WHERE smidja_id=?", (run_id,)).fetchone()
    return dict(row) if row else None


def _events(conn: sqlite3.Connection, run_id: str) -> list[dict]:
    rows = conn.execute(
        "SELECT * FROM events WHERE smidja_id=? ORDER BY rowid", (run_id,)).fetchall()
    out = []
    for row in rows:
        rec = dict(row)
        try:
            rec["payload"] = json.loads(rec.get("payload_json") or "{}")
        except (TypeError, ValueError):
            rec["payload"] = {}
        out.append(rec)
    return out


def _phases(conn: sqlite3.Connection, run_id: str) -> list[dict]:
    rows = conn.execute(
        "SELECT * FROM phases WHERE smidja_id=? ORDER BY seq", (run_id,)).fetchall()
    return [dict(r) for r in rows]


def _agent_sessions(conn: sqlite3.Connection, run_id: str) -> dict[str, dict]:
    rows = conn.execute("SELECT * FROM agent_sessions WHERE smidja_id=?", (run_id,)).fetchall()
    return {r["agent"]: dict(r) for r in rows}


def _last_turn_from_stream(path: Path) -> dict:
    """The last VALID assistant usage + stop reason from `raw_output.jsonl`.

    Files are the raw record, so a run whose DB rows predate the context receipt
    can still be read honestly here instead of being reported as unknown.
    """
    out = {"used": 0, "input": 0, "cache_read": 0, "output": 0, "finish": ""}
    if not path.is_file():
        return out
    try:
        text = path.read_text(errors="ignore")
    except OSError:
        return out
    for line in text.splitlines():
        if '"usage"' not in line:
            continue
        try:
            d = json.loads(line)
        except ValueError:
            continue
        msg = d.get("message") if isinstance(d.get("message"), dict) else d
        usage = (d.get("usage") or (msg.get("usage") if isinstance(msg, dict) else None))
        if not isinstance(usage, dict):
            continue
        reason = str((msg or {}).get("stopReason") or "").lower()
        if reason in ("aborted", "error"):
            continue
        total = usage.get("totalTokens") or 0
        if not total:
            total = sum(int(usage.get(p) or 0)
                        for p in ("input", "output", "cacheRead", "cacheWrite"))
        out = {
            "used": int(total or 0),
            "input": int(usage.get("input") or 0),
            "cache_read": int(usage.get("cacheRead") or 0),
            "output": int(usage.get("output") or 0),
            "finish": reason,
        }
    return out


def _envelope_status(agent_dir: Path) -> str:
    """The parsed final response's own status, when the record carries one."""
    path = agent_dir / "envelope.json"
    if not path.is_file():
        return ""
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        return ""
    return str(data.get("status") or "")


def _tools_label(tools, observed: list[str]) -> str:
    """The phase's declared capability, else what it actually called."""
    if isinstance(tools, list) and tools:
        return ",".join(str(t) for t in tools)
    if tools == []:
        return EMPTY
    observed = [t for t in observed if t]
    if observed:
        seen: list[str] = []
        for name in observed:
            if name not in seen:
                seen.append(name)
        return ",".join(seen)
    return "all"


def _row_for_phase(phase: dict, evs: list[dict], agents: dict[str, dict],
                   data_dir: Path, run_id: str) -> dict:
    """Fold a phase's own events and files into one honest row."""
    kind = phase.get("kind") or ""
    owner = phase.get("owner") or EMPTY
    started = next((e for e in evs if e["type"] == "agent_start"), {})
    ended = next((e for e in reversed(evs) if e["type"] == "agent_end"), {})
    start_payload = started.get("payload") or {}
    end_payload = ended.get("payload") or {}

    model = start_payload.get("model") or (end_payload.get("context") or {}).get("model") or ""
    thinking = start_payload.get("thinking") or ""
    observed = [str(e.get("name") or "").split(":", 1)[0]
                for e in evs if e["type"] == "tool_call"]
    # A non-agent phase has no capability list at all; `all` would be a claim
    # about a phase that never ran an agent.
    tools = _tools_label(start_payload.get("tools"), observed) if kind == "agent" else EMPTY

    receipt = end_payload.get("context") or {}
    agent_dir = data_dir / "sessions" / run_id / owner
    stream = _last_turn_from_stream(agent_dir / "raw_output.jsonl")

    used = int(receipt.get("used") or 0)
    window = int(receipt.get("window") or 0)
    finish = str(receipt.get("last_finish") or "")
    input_tokens = int(receipt.get("input") or 0)
    cache_read = int(receipt.get("cache_read") or 0)
    output = int(receipt.get("output") or 0)
    source = str(receipt.get("window_source") or "")

    if not used:
        # No receipt (an older run, or a phase that never reached agent_end):
        # fall back to the last usage event, then the agent's own session row,
        # then the raw stream. Every rung is a real record, never a guess.
        usage_event = next((e for e in reversed(evs) if e["type"] == "usage" and e.get("tokens")),
                           {})
        used = int(usage_event.get("tokens") or 0)
        agent_row = agents.get(owner) or {}
        if not used:
            used = int(agent_row.get("context_tokens") or 0)
        if not model:
            model = str(agent_row.get("model") or "")
        if not used and stream["used"]:
            used = stream["used"]
            input_tokens = stream["input"]
            cache_read = stream["cache_read"]
            output = stream["output"]
            finish = finish or stream["finish"]
        if not finish:
            finish = stream["finish"]
        if not window and agent_row.get("context_window"):
            window, source = int(agent_row["context_window"]), "agent_sessions"

    if model and not window:
        window, source = context_telemetry.window_for(model)

    if kind != "agent":
        verdict = context_telemetry.VERDICT_NO_USAGE
    else:
        verdict = receipt.get("verdict") or context_telemetry.verdict(used, window, finish)

    return {
        "seq": phase.get("seq"),
        "phase": phase.get("name") or EMPTY,
        "kind": kind,
        "owner": owner,
        "status": phase.get("status") or "",
        "model": model or EMPTY,
        "thinking": thinking or EMPTY,
        "tools": tools,
        "tokens": used,
        "input": input_tokens,
        "cache_read": cache_read,
        "output": output,
        "window": window,
        "percent": context_telemetry.percent(used, window) if window else 0.0,
        "verdict": verdict,
        "pressed": bool(receipt.get("pressed")) or context_telemetry.pressed(used, window, finish),
        "window_source": source or ("unknown" if not window else "registry"),
        "finish": finish,
        "envelope_status": _envelope_status(agent_dir) if kind == "agent" else "",
    }


def build_trace(db_path: Path, run_id: str, data_dir: Path | None = None) -> dict:
    """The whole trace, as data. The renderer below is the only formatter."""
    conn = _open(db_path)
    try:
        sess = session_row(conn, run_id)
        if sess is None:
            raise LookupError(f"no run {run_id!r} in {db_path}")
        phases = _phases(conn, run_id)
        events = _events(conn, run_id)
        agents = _agent_sessions(conn, run_id)
    finally:
        conn.close()

    base = data_dir if data_dir is not None else _data_dir(db_path)
    by_phase: dict[str, list[dict]] = {}
    for event in events:
        by_phase.setdefault(event.get("phase_id") or "", []).append(event)

    rows = [_row_for_phase(p, by_phase.get(p["phase_id"], []), agents, base, run_id)
            for p in phases]
    return {"run": sess, "rows": rows, "db": str(db_path)}


# ── printing ─────────────────────────────────────────────────────────────────

def _cell(value) -> str:
    text = str(value).replace('"', "'")
    return text


def render(trace: dict) -> str:
    """The TOON table: exactly the columns the brief names, in its order."""
    rows = trace["rows"]
    lines = [f"trace[{len(rows)}]{{phase,owner,model,thinking,tools,tokens,window,percent,verdict}}:"]
    for row in rows:
        tokens = f"{row['tokens']}" if row["tokens"] else EMPTY
        window = f"{row['window']}" if row["window"] else EMPTY
        pct = f"{row['percent']}" if row["window"] and row["tokens"] else EMPTY
        lines.append(
            '  "{}","{}","{}","{}","{}","{}","{}","{}","{}"'.format(
                _cell(row["phase"]), _cell(row["owner"]), _cell(row["model"]),
                _cell(row["thinking"]), _cell(row["tools"]), tokens, window, pct,
                _cell(row["verdict"])))
    return "\n".join(lines)


def render_json(trace: dict) -> str:
    return json.dumps({
        "run": {k: trace["run"].get(k) for k in
                ("smidja_id", "smidja_name", "status", "engineer",
                 "started_at", "ended_at", "total_tokens", "total_cost")},
        "db": trace["db"],
        "context_pressed": any(r["pressed"] for r in trace["rows"]),
        "phases": trace["rows"],
    }, indent=2)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="One row per phase: who ran, on what, how full the window.")
    parser.add_argument("run_id", help="the run id (the smidja_id printed on startup)")
    parser.add_argument("--config", default=None, help="roster to read observability.db from")
    parser.add_argument("--db", default=None, help="the trace db, when it is not the default")
    parser.add_argument("--data-dir", default=None, help="the shelf holding sessions/<id>/")
    parser.add_argument("--json", action="store_true", help="machine-readable detail")
    args = parser.parse_args(argv)

    db_path = Path(args.db) if args.db else resolve_db(args.config)
    if not db_path.is_file():
        print(f"trace: no trace db at {db_path} — nothing to read", file=sys.stderr)
        return 3
    data_dir = Path(args.data_dir) if args.data_dir else None
    try:
        trace = build_trace(db_path, args.run_id, data_dir)
    except LookupError as missing:
        print(f"trace: {missing}", file=sys.stderr)
        return 2
    except sqlite3.Error as broken:
        print(f"trace: could not read {db_path}: {broken}", file=sys.stderr)
        return 3

    print(render_json(trace) if args.json else render(trace))
    return 0


if __name__ == "__main__":
    sys.exit(main())
