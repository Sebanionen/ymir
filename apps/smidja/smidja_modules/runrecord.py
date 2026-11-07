"""The run AS ONE RECORD: phases · steps · state · where it stopped.

The trace already holds every fact — `sessions`, `phases`, `events`,
`gate_results`, `envelopes`, `decisions`, `agent_sessions`, `processes`. What it
did not have was one reader that turns those rows into the shape a client
renders, so `resume`, the terminal doors and any future visualizer each wrote
their own SQL and could disagree.

This module is that reader, and it is the ONLY one. The shape is pi-durable's
(`github.com/zerwiz/durable-pi`, `apps/dpi-sdk/src/jobs.ts`): a run is one
document — its phases, each phase's steps in order, the run's state, and the one
place it stopped — because every client must render the same run, live and after
a restart.

The phases and steps are READ, never invented: a step exists because the trace
recorded an event, and a phase's status is derived from its row plus its gates
plus its decision. Where the record is silent this says so (`""`, `pending`,
`unknown`), because a guess dressed as a fact is what a resume would then trust.

    record = load(RecordQuery(smidja_id=..., db_path=..., session_dir=...))
    record.status          running | waiting | interrupted | completed | failed | declined
    record.phases          each phase with its steps, gates, approval and progress
    record.checkpoint      the last phase that is green AND gate-passed AND approved
    record.resume_at       the phase a restart re-enters at ("" = nothing recorded)
    record.where_stopped   one sentence, for a person

`interrupted` is the word this house adds to the reference's vocabulary: the
record says `running` while no process is alive, which is exactly what a SIGKILL
leaves behind. A record that keeps calling that `running` would have a resume
believe work is in flight that is already dead.
"""

from __future__ import annotations

import json
import os
import sqlite3
from pathlib import Path
from typing import Any, Optional

from pydantic import BaseModel, Field

MAX_LINE = 160

# What a run can be. The first four are the reference's; `interrupted` is ours.
RUN_STATUSES = ("running", "waiting", "interrupted", "completed", "failed", "declined")
PHASE_STATUSES = ("pending", "running", "waiting", "interrupted", "done", "failed")


class RecordMissing(RuntimeError):
    """The trace holds no such run (or no trace at all)."""


class RecordQuery(BaseModel):
    """Everything `load()` needs, as one object — the family's four-param rule."""

    smidja_id: str
    db_path: str
    session_dir: str = ""


# ── the shape: what a client renders ─────────────────────────────────────────

class Step(BaseModel):
    """One thing the run did, in the order it did it.

    `iteration` is set only inside a `repeat` phase, and it is what makes one
    checkpoint per loop distinguishable from a phase that ran once.
    """

    kind: str                       # phase_start | log | checkpoint | tool_call | gate_pass | error | ...
    label: str = ""
    status: str = "done"            # done | running | error | waiting
    at: str = ""
    iteration: int = 0


class GateVerdict(BaseModel):
    gate: str
    passed: bool
    why: str = ""


class PhaseRun(BaseModel):
    """One phase as the record holds it — the row, its gates, its steps, its contract."""

    phase_id: str
    seq: int
    name: str
    lane: str = ""                  # engineer | agent | code — who runs the block
    contract: str = "ordinary"      # ordinary | approval | repeat — what it owes
    owner: str = ""
    description: str = ""
    status: str = "pending"         # pending | running | waiting | interrupted | done | failed
    recorded: str = ""              # what the phase row itself says
    started_at: str = ""
    ended_at: str = ""
    error: str = ""
    gates: list[GateVerdict] = Field(default_factory=list)
    steps: list[Step] = Field(default_factory=list)
    approval: str = ""              # "" (not an approval phase) | pending | approved | declined | cancelled
    progress: Optional[dict] = None  # repeat phases: {"done": n, "total": m}
    envelope: Optional[dict] = None  # agent phases: the committed envelope
    logged: Optional[dict] = None    # code phases: the last logged verdict

    @property
    def gate_failed(self) -> bool:
        return any(not gate.passed for gate in self.gates)

    @property
    def approved(self) -> bool:
        """Only an approval phase has this question; every other phase is unblocked."""
        return self.contract != "approval" or self.approval == "approved"

    @property
    def green(self) -> bool:
        """Green is earned three times: it finished, no gate of it failed, and —
        when the contract is `approval` — a person actually said yes.
        """
        return self.recorded == "success" and not self.gate_failed and self.approved

    @property
    def lied(self) -> bool:
        """It calls itself successful while a gate failed or a signature is missing."""
        return self.recorded == "success" and not self.green

    @property
    def checkpoints(self) -> int:
        return sum(1 for step in self.steps
                   if step.kind == "checkpoint" and step.status == "done")


class Decision(BaseModel):
    phase: str
    decision: str                   # approved | declined | cancelled
    by: str = ""
    note: str = ""
    at: str = ""


class RunRecord(BaseModel):
    """The run, whole. One object a door, a resume and a UI all read."""

    smidja_id: str
    chain: str = ""
    request: str = ""
    engineer: str = ""
    status: str = "running"
    started_at: str = ""
    ended_at: str = ""
    tokens: int = 0
    cost: float = 0.0
    phases: list[PhaseRun] = Field(default_factory=list)
    decisions: list[Decision] = Field(default_factory=list)
    checkpoint: str = ""            # the last phase that is green, gate-passed and approved
    resume_at: str = ""             # the phase a restart re-enters at
    where_stopped: str = ""
    resumed: int = 0                # how many times a restart continued from a checkpoint
    live_pids: list[int] = Field(default_factory=list)
    agent_sessions: dict[str, str] = Field(default_factory=dict)   # agent -> coding-agent session
    models: dict[str, str] = Field(default_factory=dict)           # agent -> the model it ran on

    # ── questions the doors and the resume ask ──────────────────────────────
    def phase(self, name: str) -> Optional[PhaseRun]:
        """The phase under that name — the NEWEST one when a chain re-entered it twice."""
        return next((phase for phase in reversed(self.phases) if phase.name == name), None)

    @property
    def green_phases(self) -> list[PhaseRun]:
        return [phase for phase in self.phases if phase.green]

    @property
    def waiting_phase(self) -> Optional[PhaseRun]:
        """The approval phase a person owes a decision on, if the run stopped in one."""
        return next((phase for phase in self.phases
                     if phase.contract == "approval" and phase.approval == "pending"), None)

    def describe(self) -> list[tuple[str, str]]:
        """The run's own line — field/value pairs, for a TOON face."""
        rows = [("smidja_id", self.smidja_id),
                ("chain", self.chain or "(unknown)"),
                ("status", self.status),
                ("request", _clip(self.request)),
                ("checkpoint", self.checkpoint or "(none)"),
                ("resume_at", self.resume_at or "(nothing left to re-enter)"),
                ("phases", f"{sum(1 for p in self.phases if p.green)}/{len(self.phases)} green"),
                ("resumed", str(self.resumed))]
        if self.waiting_phase is not None:
            rows.append(("approval", f"{self.waiting_phase.name} — a decision is owed"))
        if self.live_pids:
            rows.append(("live_pids", ", ".join(str(pid) for pid in self.live_pids)))
        rows.append(("where_stopped", self.where_stopped))
        return rows

    def steps(self) -> list[tuple[str, Step]]:
        return [(phase.name, step) for phase in self.phases for step in phase.steps]


# ── loading: the one read of the trace ───────────────────────────────────────

def load(query: RecordQuery) -> RunRecord:
    """Read the trace once and return the run as a record (or raise RecordMissing)."""
    path = Path(query.db_path)
    if not path.is_file():
        raise RecordMissing(f"no trace database at {query.db_path}")
    conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    try:
        session = _session(conn, query.smidja_id)
        agent_map = _read_agent_map(query.session_dir)
        processes = _processes(conn, query.smidja_id)
        live = [int(row["pid"] or 0) for row in processes
                if row["ended_at"] is None and _alive(int(row["pid"] or 0))]
        gates = _final_gates(conn, query.smidja_id)
        steps, totals = _steps(conn, query.smidja_id)
        decisions = _decisions(conn, query.smidja_id)
        merged = _merge_decisions(decisions)
        envelopes = _envelopes(conn, query.smidja_id, query.session_dir, agent_map)
        logged = _logged(conn, query.smidja_id)
        phases = [_phase(row, gates, steps, totals, merged, envelopes, logged,
                         interrupted=not live)
                  for row in _phase_rows(conn, query.smidja_id)]

        record = RunRecord(
            smidja_id=query.smidja_id,
            chain=_last_chain(session["smidja_name"] or ""),
            request=_request_text(conn, query.smidja_id),
            engineer=session["engineer"] or "",
            started_at=session["started_at"] or "",
            ended_at=session["ended_at"] or "",
            tokens=int(session["total_tokens"] or 0),
            cost=float(session["total_cost"] or 0.0),
            phases=phases,
            decisions=decisions,
            resumed=_count_resumes(conn, query.smidja_id),
            live_pids=live,
            agent_sessions={agent: str(entry.get("session_id") or "")
                            for agent, entry in agent_map.items()
                            if isinstance(entry, dict)},
            models=_agent_models(conn, query.smidja_id, agent_map),
        )
        record.status = _run_status(session["status"] or "running", live)
        record.checkpoint, record.resume_at = _checkpoint(phases)
        record.where_stopped = _where_stopped(record)
        return record
    finally:
        conn.close()


def _phase(row: sqlite3.Row, gates: dict, steps: dict, totals: dict, decisions: dict,
           envelopes: dict, logged: dict, interrupted: bool) -> PhaseRun:
    recorded = row["status"] or "fail"
    contract = (row["contract"] if "contract" in row.keys() else None) or "ordinary"
    approval = decisions.get(row["name"] or "", "")
    if contract == "approval" and not approval:
        approval = "pending"
    phase_steps = steps.get(row["phase_id"], [])
    phase = PhaseRun(
        phase_id=row["phase_id"], seq=row["seq"] or 0, name=row["name"] or "",
        lane=row["kind"] or "", contract=contract, owner=row["owner"] or "",
        description=row["description"] or "", recorded=recorded,
        started_at=row["started_at"] or "", ended_at=row["ended_at"] or "",
        error=row["error"] or "", gates=gates.get(row["phase_id"], []),
        steps=phase_steps, approval=approval if contract == "approval" else "",
        progress=_progress(phase_steps, contract, totals.get(row["phase_id"], 0)),
    )
    phase.status = _phase_status(phase, interrupted)
    if row["kind"] == "agent":
        phase.envelope = envelopes.get(row["phase_id"])
    elif row["kind"] == "code":
        phase.logged = logged.get(row["phase_id"])
    return phase


def _phase_status(phase: PhaseRun, interrupted: bool) -> str:
    """What the phase IS, which is not always what its row says.

    `running` with the process gone is `interrupted`; an `approval` phase with no
    decision is `waiting` — never `done`, that is the whole point of the contract;
    and one a person declined is `failed`, because a refusal is not a pass.
    """
    if phase.contract == "approval":
        if phase.approval in ("declined", "cancelled"):
            return "failed"
        if phase.approval != "approved":
            return "waiting" if phase.recorded != "running" else "interrupted"
    if phase.recorded == "success":
        return "done"
    if phase.recorded == "fail":
        return "failed"
    if phase.recorded == "waiting":
        return "waiting"
    if phase.recorded == "running":
        return "interrupted" if interrupted else "running"
    return "pending"


def _run_status(recorded: str, live: list[int]) -> str:
    """The session row says what the run last believed; the kernel says what is true."""
    if recorded == "success":
        return "completed"
    if recorded == "fail":
        return "failed"
    if recorded in ("waiting", "declined", "aborted"):
        return recorded
    # `running` is only true while something is alive to run it.
    return "running" if live else "interrupted"


def _checkpoint(phases: list[PhaseRun]) -> tuple[str, str]:
    """(the last green phase, the phase a restart re-enters at)."""
    boundary = next((phase for phase in reversed(phases) if phase.green), None)
    if boundary is None:
        later = phases[0] if phases else None
        return "", later.name if later else ""
    later = next((phase for phase in phases if phase.seq > boundary.seq), None)
    return boundary.name, later.name if later else ""


def _where_stopped(record: RunRecord) -> str:
    if record.status == "completed":
        last = record.phases[-1].name if record.phases else "(none)"
        return f"the run finished green; its last phase was {last}"
    if record.status == "waiting":
        phase = record.waiting_phase or (record.phases[-1] if record.phases else None)
        name = phase.name if phase else "(unrecorded)"
        decider = phase.approval if phase else "pending"
        return (f"waiting at {name!r} — an approval phase with no decision "
                f"({decider}); the block has not run")
    if record.status == "declined":
        phase = record.phases[-1] if record.phases else None
        return f"declined at {phase.name!r}; no further phase was opened" if phase else "declined"
    if record.status == "interrupted":
        name = record.resume_at or "(unrecorded)"
        return (f"the process is gone; {name!r} never closed — a restart re-enters "
                f"there, after checkpoint {record.checkpoint or '(none)'}")
    failed = next((phase for phase in reversed(record.phases) if phase.status == "failed"), None)
    if failed is not None:
        why = f" — {failed.error}" if failed.error else ""
        return f"failed at {failed.name!r}{why}"
    return f"running; {record.resume_at or 'the next phase'} is next" if record.status == "running" \
        else record.status


# ── trace readers (read-only, and tolerant of an older db) ───────────────────

def _columns(conn: sqlite3.Connection, table: str) -> set[str]:
    return {row[1] for row in conn.execute(f"PRAGMA table_info({table})")}


def _has_table(conn: sqlite3.Connection, table: str) -> bool:
    row = conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?",
                       (table,)).fetchone()
    return row is not None


def _session(conn: sqlite3.Connection, smidja_id: str) -> sqlite3.Row:
    row = conn.execute("SELECT * FROM sessions WHERE smidja_id = ?", (smidja_id,)).fetchone()
    if row is None:
        raise RecordMissing(f"the trace has no session {smidja_id!r}")
    return row


def _phase_rows(conn: sqlite3.Connection, smidja_id: str) -> list[sqlite3.Row]:
    if "contract" not in _columns(conn, "phases"):
        return conn.execute(
            "SELECT phase_id, smidja_id, seq, name, kind, owner, description, status,"
            " attempt, retries, error, started_at, ended_at FROM phases"
            " WHERE smidja_id = ? ORDER BY seq, rowid", (smidja_id,)).fetchall()
    return conn.execute(
        "SELECT phase_id, smidja_id, seq, name, kind, owner, description, status,"
        " attempt, retries, contract, error, started_at, ended_at FROM phases"
        " WHERE smidja_id = ? ORDER BY seq, rowid", (smidja_id,)).fetchall()


def _processes(conn: sqlite3.Connection, smidja_id: str) -> list[sqlite3.Row]:
    return conn.execute(
        "SELECT kind, name, pid, command, started_at, ended_at FROM processes"
        " WHERE smidja_id = ? ORDER BY id", (smidja_id,)).fetchall()


def _steps(conn: sqlite3.Connection, smidja_id: str) -> tuple[dict[str, list[Step]], dict[str, int]]:
    """Every event that is a step, in order, keyed by phase; plus repeat totals.

    A `progress` event is a declaration, not a step: it sets the repeat phase's
    total and would otherwise read as work that was done.
    """
    rows = conn.execute(
        "SELECT phase_id, type, name, payload_json, started_at FROM events"
        " WHERE smidja_id = ? ORDER BY rowid", (smidja_id,)).fetchall()
    steps: dict[str, list[Step]] = {}
    totals: dict[str, int] = {}
    for row in rows:
        payload = _json(row["payload_json"], {}) or {}
        phase_id = row["phase_id"] or ""
        if row["type"] == "progress":
            totals[phase_id] = int(payload.get("total") or 0)
            continue
        steps.setdefault(phase_id, []).append(
            Step(kind=row["type"] or "", label=_step_label(row["type"], row["name"], payload),
                 status=_step_status(row["type"], payload),
                 at=row["started_at"] or "",
                 iteration=int(payload.get("iteration") or 0)))
    return steps, totals


def _step_label(kind: str, name: str, payload: dict) -> str:
    if isinstance(payload.get("message"), str) and payload["message"].strip():
        return _clip(payload["message"])
    if kind == "checkpoint":
        return f"iteration {payload.get('iteration', '?')} committed"
    if kind in ("gate_pass", "gate_fail", "gate"):
        return str(payload.get("gate") or name or kind)
    if kind in ("error",):
        return _clip(str(payload.get("error") or payload.get("reason") or ""))
    if kind == "phase_start":
        return f"{payload.get('kind', '?')} · {payload.get('owner', '?')}"
    if kind == "approval":
        return f"{payload.get('decision', '?')} by {payload.get('by') or 'nobody'}"
    if kind == "resume":
        return f"continued from checkpoint {payload.get('checkpoint', '?')}"
    if payload:
        return _clip(", ".join(f"{key}: {value}" for key, value in payload.items()))
    return name or kind


def _step_status(kind: str, payload: dict) -> str:
    if kind in ("error", "gate_fail"):
        return "error"
    if kind == "phase_start":
        return "running"
    if kind in ("approval",) and payload.get("decision") not in ("approved",):
        return "waiting"
    return "done"


def _final_gates(conn: sqlite3.Connection, smidja_id: str) -> dict[str, list[GateVerdict]]:
    """The last attempt of each gate, per phase — a retried gate settles on its retry."""
    rows = conn.execute(
        "SELECT phase_id, gate, passed, violations_json FROM gate_results"
        " WHERE smidja_id = ? ORDER BY id", (smidja_id,)).fetchall()
    latest: dict[tuple[str, str], GateVerdict] = {}
    for row in rows:
        violations = _json(row["violations_json"], []) or []
        latest[(row["phase_id"], row["gate"] or "")] = GateVerdict(
            gate=row["gate"] or "", passed=bool(row["passed"]),
            why="; ".join(str(v) for v in violations) if violations else "passed")
    out: dict[str, list[GateVerdict]] = {}
    for (phase_id, _gate), verdict in latest.items():
        out.setdefault(phase_id, []).append(verdict)
    return out


def _decisions(conn: sqlite3.Connection, smidja_id: str) -> list[Decision]:
    if not _has_table(conn, "decisions"):
        return []
    rows = conn.execute(
        "SELECT phase, decision, by, note, created_at FROM decisions"
        " WHERE smidja_id = ? ORDER BY id", (smidja_id,)).fetchall()
    return [Decision(phase=row["phase"] or "", decision=row["decision"] or "",
                     by=row["by"] or "", note=row["note"] or "",
                     at=row["created_at"] or "") for row in rows]


def _merge_decisions(decisions: list[Decision]) -> dict[str, str]:
    """The newest decision per phase — an approval is never revoked by an older row."""
    merged: dict[str, str] = {}
    for decision in decisions:
        merged[decision.phase] = decision.decision
    return merged


def _progress(steps: list[Step], contract: str, total: int) -> Optional[dict]:
    """A repeat phase's honest count: how many iterations committed, of how many."""
    if contract != "repeat":
        return None
    done = {step.iteration for step in steps
            if step.kind == "checkpoint" and step.status == "done"}
    return {"done": len(done), "total": total}


def _envelopes(conn: sqlite3.Connection, smidja_id: str, session_dir: str,
               agent_map: dict) -> dict[str, dict]:
    """Each agent phase's committed envelope: the trace first, the file second."""
    out: dict[str, dict] = {}
    rows = conn.execute(
        "SELECT phase_id, agent, payload_json FROM envelopes"
        " WHERE smidja_id = ? AND valid = 1 ORDER BY rowid", (smidja_id,)).fetchall()
    for row in rows:
        payload = _json(row["payload_json"], None)
        if isinstance(payload, dict):
            out[row["phase_id"]] = payload
    # A phase whose envelope row was never written may still have the file the
    # agent left behind; read it so the record does not call committed work lost.
    for phase in conn.execute("SELECT phase_id, owner FROM phases WHERE smidja_id = ?"
                              " AND kind = 'agent'", (smidja_id,)).fetchall():
        if phase["phase_id"] in out:
            continue
        payload = _envelope_file(session_dir, phase["owner"] or "")
        if payload is not None:
            out[phase["phase_id"]] = payload
    return out


def _envelope_file(session_dir: str, agent: str) -> Optional[dict]:
    if not session_dir or not agent:
        return None
    path = Path(session_dir) / agent / "envelope.json"
    if not path.is_file():
        return None
    try:
        record = json.loads(path.read_text())
    except (OSError, ValueError):
        return None
    if not isinstance(record, dict):
        return None
    for key in ("agent_name", "purpose", "output_type", "attempt"):
        record.pop(key, None)
    return record


def _logged(conn: sqlite3.Connection, smidja_id: str) -> dict[str, dict]:
    """The verdict each code phase logged last — what it paid for, not a re-measure.

    Console lines are `log` events too (`{"message", "level"}`), so they are told
    apart by their `level` rather than by the word `message`: a chain's own
    `ph.log(message=...)` is a verdict and must not be mistaken for console noise.
    """
    rows = conn.execute(
        "SELECT phase_id, payload_json FROM events WHERE smidja_id = ? AND type = 'log'"
        " ORDER BY rowid", (smidja_id,)).fetchall()
    out: dict[str, dict] = {}
    for row in rows:
        payload = _json(row["payload_json"], None)
        if isinstance(payload, dict) and "level" not in payload:
            out[row["phase_id"]] = payload
    return out


def _count_resumes(conn: sqlite3.Connection, smidja_id: str) -> int:
    row = conn.execute("SELECT COUNT(*) FROM events WHERE smidja_id = ? AND type = 'resume'",
                       (smidja_id,)).fetchone()
    return int(row[0] or 0)


def _request_text(conn: sqlite3.Connection, smidja_id: str) -> str:
    """The ask in full: `sessions.request` is clipped at 500 chars, the log is not."""
    row = conn.execute(
        "SELECT payload_json FROM events WHERE smidja_id = ? AND type = 'log'"
        " AND name = 'request' ORDER BY rowid ASC LIMIT 1", (smidja_id,)).fetchone()
    if row is not None:
        payload = _json(row["payload_json"], {}) or {}
        text = payload.get("input")
        if isinstance(text, str) and text.strip():
            return text
    row = conn.execute("SELECT request FROM sessions WHERE smidja_id = ?", (smidja_id,)).fetchone()
    return (row["request"] or "") if row else ""


def _read_agent_map(session_dir: str) -> dict:
    if not session_dir:
        return {}
    path = Path(session_dir) / "agent_map.json"
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def _agent_models(conn: sqlite3.Connection, smidja_id: str, agent_map: dict) -> dict[str, str]:
    models: dict[str, str] = {}
    for row in conn.execute("SELECT agent, model FROM agent_sessions WHERE smidja_id = ?",
                            (smidja_id,)).fetchall():
        if row["model"]:
            models[row["agent"]] = row["model"]
    for agent, entry in agent_map.items():
        if isinstance(entry, dict) and entry.get("model"):
            models[agent] = str(entry["model"])
    return models


def _last_chain(smidja_name: str) -> str:
    names = [name.strip() for name in smidja_name.split("+") if name.strip()]
    return names[-1] if names else ""


def _alive(pid: int) -> bool:
    if not pid:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _clip(text: str, limit: int = MAX_LINE) -> str:
    flat = " ".join(str(text).split())
    return flat if len(flat) <= limit else flat[: limit - 1] + "…"


def _json(text: Any, default: Any) -> Any:
    if not text:
        return default
    try:
        return json.loads(text)
    except (TypeError, ValueError):
        return default
