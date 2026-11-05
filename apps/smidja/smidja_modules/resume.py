"""Resume: re-enter a run at its last committed phase — or refuse and say why.

The shape is pi-durable's checkpoint discipline
(`github.com/zerwiz/pi-durable-news-agent`, `news/sweep-task.ts`): a run is a
sequence of named phases; **every phase commits a checkpoint when it completes**,
and a restart re-enters at the phase the checkpoint names — never at the top, and
never past a phase that did not commit.

Translated to the smithy:

  checkpoint   the last phase whose status is green AND whose gate passed
  work         that phase's envelope (agent phases) or its recorded verdict
               (code phases) — handed forward, never recomputed
  context      the agent session ids in `agent_map.json`, so each agent resumes
               its own window instead of starting cold

The commit is the trace itself: `runner.Run.phase()` writes the phase row, the
envelope rows and the `ph.log()` payloads as the phase closes, so a phase that
appears green in `smidja.db` is a phase whose work is on record.

What the reference does not have to say, and this module does: **a phase that did
not commit is not skippable**. So the boundary is the last green phase, and the
resume point is the first phase after it — the phase that failed. That is the
whole point: a run that fails at phase three continues AT phase three instead of
starting again from the top.

Three refusals, and they are the feature — each one is a way a resume would lie:

  no such run                     there is no session under that id
  nothing green to resume from    no phase stands green with its gate passed, or
                                  the record contradicts itself (a phase that
                                  reports success on a failed gate)
  the roster changed since this run   an agent's model is not the one the run
                                  was started with — a changed model means a
                                  fresh session, and a bad resume is worse
                                  than none
"""

from __future__ import annotations

import json
import os
import sqlite3
from pathlib import Path
from typing import Any, Optional

from pydantic import BaseModel, Field

from .data_types import (BaseRef, ChangeSet, QualityCheckResult, QualityResult)

# The refusal vocabulary. These three strings are the contract with the operator,
# the cookbook and the tests; nothing else is a resume refusal.
NO_SUCH_RUN = "no such run"
NOTHING_GREEN = "nothing green to resume from"
ROSTER_CHANGED = "the roster changed since this run"

REFUSALS = (NO_SUCH_RUN, NOTHING_GREEN, ROSTER_CHANGED)


class ResumeRefused(RuntimeError):
    """A resume that would lie. `reason` is one of REFUSALS, `detail` is the why."""

    def __init__(self, reason: str, detail: str = ""):
        self.reason = reason
        self.detail = detail
        super().__init__(f"{reason}{' — ' + detail if detail else ''}")


class ResumeBusy(RuntimeError):
    """The run is still alive — continuing it would run the same phase twice.

    Not one of the three refusals: this is an operational block, answered by
    stopping the live run first (`just kill <id>`), not by rewriting the record.
    """


class ResumeComplete(RuntimeError):
    """Every phase committed — there is no phase left to re-enter at.

    Also not a refusal: the record is honest, it simply says the run is finished.
    `--from-phase <name>` is the answer when the operator wants a phase re-run.
    """


class ResumeQuery(BaseModel):
    """Everything `plan()` needs. Passed as one object, never loose params."""

    smidja_id: str
    db_path: str
    session_dir: str
    roster: dict[str, str] = Field(default_factory=dict)   # agent -> model, from the config NOW
    from_phase: Optional[str] = None                        # re-enter at this phase instead


class ResumePlan(BaseModel):
    """What to do next: skip these phases, re-enter at that one, hand these forward.

    `replay` is ordered, and it is exactly the phases that already committed —
    so `Run.phase()` can decide per phase name, without knowing the chain's
    remaining order. `from_phase` is empty when the run stopped at its last
    recorded phase: the next phase is simply the next one the chain opens.
    """

    smidja_id: str
    chain: str = ""                       # e.g. "smidja_plan_build_test"
    request: str = ""                     # the ask, as the run recorded it
    boundary: str = ""                    # the last green phase (the checkpoint)
    boundary_seq: int = 0
    from_phase: str = ""                  # the phase to re-enter at ("" = whatever comes next)
    replay: list[str] = Field(default_factory=list)        # phase names to hand forward
    envelopes: dict[str, Any] = Field(default_factory=dict)    # phase name -> envelope dict
    records: dict[str, Any] = Field(default_factory=dict)      # phase name -> logged payload
    sessions: dict[str, str] = Field(default_factory=dict)     # agent -> coding-agent session id
    models: dict[str, str] = Field(default_factory=dict)       # agent -> model at run time

    # ── questions `Run` asks while replaying ────────────────────────────────
    def is_replay(self, phase_name: str) -> bool:
        return phase_name in self.replay

    def envelope_for(self, phase_name: str, output_type):
        """The stored envelope of a replayed phase, parsed into its output type."""
        payload = self.envelopes.get(phase_name)
        if payload is None:
            raise ResumeRefused(NOTHING_GREEN,
                                f"phase {phase_name!r} has no stored envelope to hand forward")
        return output_type(**payload)

    def record_for(self, phase_name: str) -> dict:
        return self.records.get(phase_name) or {}

    def quality_for(self, phase_name: str) -> QualityResult:
        """The verdict a code phase recorded — rebuilt, not re-measured."""
        record = self.record_for(phase_name)
        if "passed" not in record:
            raise ResumeRefused(NOTHING_GREEN,
                                f"phase {phase_name!r} recorded no verdict to hand forward")
        return _verdict_from_record(record)

    def sha_for(self, phase_name: str) -> str:
        return str(self.record_for(phase_name).get("sha") or "")

    def changes_for(self, phase_name: str) -> ChangeSet:
        record = self.record_for(phase_name)
        if "diff" not in record and "files" not in record:
            raise ResumeRefused(NOTHING_GREEN,
                                f"phase {phase_name!r} recorded no change capture to hand forward")
        return _changes_from_record(record)

    # ── the operator's line ─────────────────────────────────────────────────
    def describe(self) -> list[str]:
        rows = [f"run:            {self.smidja_id}",
                f"chain:          {self.chain or '(unknown)'}",
                f"checkpoint:     {self.boundary} (seq {self.boundary_seq})",
                f"re-enter at:    {self.from_phase or 'the next phase the chain opens'}",
                f"handed forward: {', '.join(self.replay) or '(none)'}"]
        for agent, session in self.sessions.items():
            rows.append(f"session:        {agent} -> {session} ({self.models.get(agent, '?')})")
        return rows


# ── reading the trace ────────────────────────────────────────────────────────

class PhaseRecord(BaseModel):
    """One phase as the trace holds it, with the gate verdict that settles it."""

    phase_id: str
    seq: int
    name: str
    kind: str
    owner: str
    status: str
    error: str = ""
    gates: list[tuple[str, bool, str]] = Field(default_factory=list)   # (gate, passed, why)

    @property
    def gate_failed(self) -> bool:
        return any(not passed for _name, passed, _why in self.gates)

    @property
    def green(self) -> bool:
        """Green is earned twice: the phase finished AND no gate of it failed."""
        return self.status == "success" and not self.gate_failed

    @property
    def lied(self) -> bool:
        """It reports success while a gate of it failed — the record contradicts itself."""
        return self.status == "success" and self.gate_failed


def plan(query: ResumeQuery) -> ResumePlan:
    """Decide the resume point, or refuse. One read of the trace, one answer."""
    conn = _connect(query.db_path)
    try:
        session = _session(conn, query.smidja_id)
        _refuse_if_alive(conn, query.smidja_id)
        session["agent_map"] = _read_agent_map(query.session_dir)
        phases = _phases(conn, query.smidja_id)
        if not phases:
            raise ResumeRefused(NOTHING_GREEN, "the run recorded no phase at all")

        # A phase that reports success while its gate failed is a contradiction.
        # Resuming past it would repeat the lie; resuming at it would re-run a
        # phase the record already calls green. Neither is honest — refuse.
        for phase in phases:
            if phase.lied:
                failed = [name for name, passed, _ in phase.gates if not passed]
                raise ResumeRefused(
                    NOTHING_GREEN,
                    f"phase {phase.name!r} reports success but its gate "
                    f"{', '.join(failed)} failed — resuming would hide the failure")

        boundary = next((p for p in reversed(phases) if p.green), None)
        if boundary is None:
            raise ResumeRefused(
                NOTHING_GREEN,
                "no phase is both green and gate-passed — there is no proven ground to stand on")

        replay, target = _resume_point(phases, boundary, query.from_phase)

        # A run that FINISHED green has nothing to continue. A run that died after
        # its last green phase has — the chain still owes the phases it never
        # opened. The session's own status is the fact that tells them apart.
        if (target is None and len(replay) == len(phases)
                and session.get("status") == "success"):
            raise ResumeComplete(
                f"this run finished green (checkpoint {boundary.name}) — there is nothing "
                f"left to continue. Use --from-phase <name> to re-run a phase")

        for phase in replay:
            if not phase.green:
                raise ResumeRefused(
                    NOTHING_GREEN,
                    f"phase {phase.name!r} is {phase.status} and would be skipped — "
                    f"a phase that did not commit is never resumed past")

        _refuse_on_roster_change(session, query)

        return ResumePlan(
            smidja_id=query.smidja_id,
            chain=_last_chain(session.get("smidja_name") or ""),
            request=_request_text(conn, query.smidja_id, query.session_dir),
            boundary=boundary.name,
            boundary_seq=boundary.seq,
            from_phase=target.name if target else "",
            replay=[p.name for p in replay],
            envelopes=_envelopes(conn, query.session_dir, replay),
            records=_records(conn, query.smidja_id, replay),
            sessions=_agent_sessions(session),
            models=_agent_models(conn, query.smidja_id, session),
        )
    finally:
        conn.close()


def _resume_point(phases: list[PhaseRecord], boundary: PhaseRecord,
                  from_phase: Optional[str]) -> tuple[list[PhaseRecord], Optional[PhaseRecord]]:
    """(phases to hand forward, the phase to re-enter at)."""
    if from_phase:
        target = next((p for p in phases if p.name == from_phase), None)
        if target is None:
            recorded = ", ".join(p.name for p in phases)
            raise ResumeRefused(
                NO_SUCH_RUN,
                f"phase {from_phase!r} is not in this run — it recorded: {recorded}")
        return [p for p in phases if p.seq < target.seq], target
    later = [p for p in phases if p.seq > boundary.seq]
    return [p for p in phases if p.seq <= boundary.seq], (later[0] if later else None)


def _refuse_on_roster_change(session: dict, query: ResumeQuery) -> None:
    """A changed model means a fresh session — and a fresh session is not a resume."""
    for agent, model in (query.roster or {}).items():
        was = _recorded_model(session, agent)
        if was and model and was != model:
            raise ResumeRefused(
                ROSTER_CHANGED,
                f"{agent}: the run used {was}, the roster now names {model} — "
                f"a changed model starts a fresh session, which is not a resume")


def _recorded_model(session: dict, agent: str) -> str:
    return str((session.get("agent_map") or {}).get(agent, {}).get("model") or "")


# ── trace readers ────────────────────────────────────────────────────────────

def _connect(db_path: str) -> sqlite3.Connection:
    path = Path(db_path)
    if not path.is_file():
        raise ResumeRefused(NO_SUCH_RUN, f"no trace database at {db_path}")
    conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    return conn


def _session(conn: sqlite3.Connection, smidja_id: str) -> dict:
    row = conn.execute("SELECT * FROM sessions WHERE smidja_id = ?", (smidja_id,)).fetchone()
    if row is None:
        raise ResumeRefused(NO_SUCH_RUN, f"the trace has no session {smidja_id!r}")
    session = dict(row)
    session["agent_map"] = {}
    return session


def _refuse_if_alive(conn: sqlite3.Connection, smidja_id: str) -> None:
    """A recorded process that is still breathing means the run is still running.

    `ended_at IS NULL` alone is not enough: a SIGKILLed run leaves its rows open
    forever. The pid is the fact — ask the kernel, never the bookkeeping.
    """
    rows = conn.execute(
        "SELECT kind, name, pid FROM processes WHERE smidja_id = ? AND ended_at IS NULL",
        (smidja_id,)).fetchall()
    for row in rows:
        pid = int(row["pid"] or 0)
        if pid and pid != os.getpid() and _alive(pid):
            raise ResumeBusy(
                f"the run is still alive (pid {pid}, {row['kind']} "
                f"{row['name'] or ''}) — stop it first, then resume")


def _alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _phases(conn: sqlite3.Connection, smidja_id: str) -> list[PhaseRecord]:
    rows = conn.execute(
        "SELECT phase_id, seq, name, kind, owner, status, error FROM phases"
        " WHERE smidja_id = ? ORDER BY seq, rowid", (smidja_id,)).fetchall()
    gates = _final_gates(conn, smidja_id)
    return [PhaseRecord(phase_id=r["phase_id"], seq=r["seq"] or 0, name=r["name"] or "",
                        kind=r["kind"] or "", owner=r["owner"] or "",
                        status=r["status"] or "fail", error=r["error"] or "",
                        gates=gates.get(r["phase_id"], []))
            for r in rows]


def _final_gates(conn: sqlite3.Connection, smidja_id: str) -> dict[str, list[tuple[str, bool, str]]]:
    """The last attempt of each gate, per phase — a retried gate settles on its retry.

    An earlier failed attempt is not a failure of the phase; only the attempt the
    phase ended on is. Reading every row would mark a corrected phase red forever.
    """
    rows = conn.execute(
        "SELECT phase_id, gate, passed, attempt, violations_json FROM gate_results"
        " WHERE smidja_id = ? ORDER BY id", (smidja_id,)).fetchall()
    latest: dict[tuple[str, str], tuple[str, bool, str]] = {}
    for row in rows:
        violations = _json(row["violations_json"], [])
        why = "; ".join(violations) if violations else "passed"
        latest[(row["phase_id"], row["gate"] or "")] = (row["gate"] or "",
                                                        bool(row["passed"]), why)
    out: dict[str, list[tuple[str, bool, str]]] = {}
    for (phase_id, _gate), value in latest.items():
        out.setdefault(phase_id, []).append(value)
    return out


def _envelopes(conn: sqlite3.Connection, session_dir: str,
               replay: list[PhaseRecord]) -> dict[str, Any]:
    """Each replayed agent phase's envelope: the trace first, the file second."""
    out: dict[str, Any] = {}
    for phase in replay:
        if phase.kind != "agent":
            continue
        row = conn.execute(
            "SELECT payload_json FROM envelopes WHERE phase_id = ? AND valid = 1"
            " ORDER BY rowid DESC LIMIT 1", (phase.phase_id,)).fetchone()
        payload = _json(row["payload_json"], None) if row else None
        if payload is None:
            payload = _envelope_file(session_dir, phase.owner)
        if payload is None:
            raise ResumeRefused(
                NOTHING_GREEN,
                f"phase {phase.name!r} is green but its envelope is not in the record — "
                f"there is nothing to hand to the next agent")
        out[phase.name] = payload
    return out


def _envelope_file(session_dir: str, agent: str) -> Optional[dict]:
    path = Path(session_dir) / agent / "envelope.json"
    if not path.is_file():
        return None
    try:
        record = json.loads(path.read_text())
    except (OSError, ValueError):
        return None
    # The file carries the run's bookkeeping beside the envelope itself.
    for key in ("agent_name", "purpose", "output_type", "attempt"):
        record.pop(key, None)
    return record


def _records(conn: sqlite3.Connection, smidja_id: str,
             replay: list[PhaseRecord]) -> dict[str, Any]:
    """What each replayed code phase logged — the verdict it already paid for."""
    out: dict[str, Any] = {}
    for phase in replay:
        if phase.kind != "code":
            continue
        row = conn.execute(
            "SELECT payload_json FROM events WHERE phase_id = ? AND type = 'log'"
            " ORDER BY rowid DESC LIMIT 1", (phase.phase_id,)).fetchone()
        payload = _json(row["payload_json"], None) if row else None
        if payload is None:
            raise ResumeRefused(
                NOTHING_GREEN,
                f"phase {phase.name!r} is green but logged no verdict — replaying it "
                f"would re-run work this run already paid for")
        out[phase.name] = payload
    return out


def _request_text(conn: sqlite3.Connection, smidja_id: str, session_dir: str) -> str:
    """The ask, in full. `sessions.request` is clipped at 500 chars; the log is not."""
    row = conn.execute(
        "SELECT payload_json FROM events WHERE smidja_id = ? AND type = 'log'"
        " AND name = 'request' ORDER BY rowid ASC LIMIT 1", (smidja_id,)).fetchone()
    if row:
        payload = _json(row["payload_json"], {})
        text = payload.get("input")
        if isinstance(text, str) and text.strip():
            return text
    row = conn.execute("SELECT request FROM sessions WHERE smidja_id = ?", (smidja_id,)).fetchone()
    return (row["request"] or "") if row else ""


def _agent_sessions(session: dict) -> dict[str, str]:
    """agent -> coding-agent session id, from the map that keeps context alive."""
    return {agent: str(entry.get("session_id") or "")
            for agent, entry in (session.get("agent_map") or {}).items()
            if isinstance(entry, dict)}


def _read_agent_map(session_dir: str) -> dict:
    path = Path(session_dir) / "agent_map.json"
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def _agent_models(conn: sqlite3.Connection, smidja_id: str, session: dict) -> dict[str, str]:
    """The model each agent ran on — the map first, the trace second."""
    models: dict[str, str] = {}
    for row in conn.execute("SELECT agent, model FROM agent_sessions WHERE smidja_id = ?",
                            (smidja_id,)).fetchall():
        if row["model"]:
            models[row["agent"]] = row["model"]
    for agent, entry in (session.get("agent_map") or {}).items():
        if isinstance(entry, dict) and entry.get("model"):
            models[agent] = str(entry["model"])
    return models


def _last_chain(smidja_name: str) -> str:
    """A joined session records every chain that ran under it; resume the last one."""
    names = [n.strip() for n in (smidja_name or "").split("+") if n.strip()]
    return names[-1] if names else ""


# ── record → object ──────────────────────────────────────────────────────────

def _verdict_from_record(record: dict) -> QualityResult:
    """Rebuild the verdict a code phase logged, so the chain's branches stay true.

    The chain logs `passed`, `checks` as "passed/total" and the artifact paths;
    that is all a resume needs to walk the same branch it walked the first time,
    without running the command again.
    """
    passed = bool(record.get("passed"))
    counted = str(record.get("checks") or "0/0").split("/")
    total = int(counted[1]) if len(counted) == 2 and counted[1].isdigit() else 0
    ok = int(counted[0]) if counted[0].isdigit() else (total if passed else 0)
    artifacts = [a.strip() for a in str(record.get("artifacts") or "").split(",") if a.strip()]
    checks = [QualityCheckResult(
        name=f"replayed-{index + 1}", area="backend", operation="build",
        command="(replayed from the trace)", returncode=0 if index < ok else 1,
        passed=index < ok, duration_seconds=0.0,
        output_artifact=artifacts[index] if index < len(artifacts) else "")
        for index in range(total)]
    return QualityResult(passed=passed, checks=checks,
                         failures=[] if passed else ["replayed: the suite failed in the earlier run"],
                         artifacts=artifacts)


def _changes_from_record(record: dict) -> ChangeSet:
    """Rebuild the change capture a code phase logged."""
    label = str(record.get("base") or "")
    ref, _, commit = label.partition(" @ ")
    file_count = int(record.get("files") or 0)
    return ChangeSet(base=BaseRef(ref=ref, commit=commit, reason=str(record.get("reason") or "")),
                     insertions=_count(record.get("lines"), "+"),
                     deletions=_count(record.get("lines"), "-"),
                     diff_path=str(record.get("diff") or ""),
                     recorded_file_count=file_count)


def _count(lines: Any, sign: str) -> int:
    for token in str(lines or "").split():
        if token.startswith(sign) and token[1:].isdigit():
            return int(token[1:])
    return 0


def _json(text: Any, default: Any) -> Any:
    if not text:
        return default
    try:
        return json.loads(text)
    except (TypeError, ValueError):
        return default
