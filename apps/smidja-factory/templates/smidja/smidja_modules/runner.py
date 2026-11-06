"""The Run object: config + smidja_id + agent_map + tracer + console, bound once.

`run.phase(PhaseParams(...))` is the ONE phase primitive — a context manager
for all three kinds (engineer, agent, code). Success must be earned: every
phase defaults to fail; only a clean exit flips it (agent phases additionally
require a parsed envelope + green gates, enforced inside ph.call).
"""

from __future__ import annotations

import json
import time
from contextlib import contextmanager
from typing import Iterator, Optional
from pathlib import Path

from . import agents, git_helper
from .console import Console
from .data_types import (AgentCall, ApprovalDecision, EnvelopeBase, EventRecord, Phase,
                         PhaseParams)
from .utils import ensure_dir, now_iso

# The two exits an `approval` phase can add. They are separated because they are
# different answers: one run is waiting for a person, the other was refused by
# one. Neither is the run failing at its work, and a caller can tell them apart.
APPROVAL_WAITING_EXIT = 3
APPROVAL_DECLINED_EXIT = 4


class ApprovalWaiting(SystemExit):
    """The run stopped at an `approval` phase that owes a decision — not a failure.

    The phase row is already settled as `waiting` and the session as `waiting`
    when this is raised, so the record says the same thing the exit code does.
    """

    def __init__(self, phase: str, door: str):
        super().__init__(APPROVAL_WAITING_EXIT)
        self.phase = phase
        self.door = door

    def __str__(self) -> str:
        return f"waiting for a decision on {self.phase!r} — {self.door}"


class ApprovalDeclined(SystemExit):
    """A person said no. The block never runs, and the run does not continue."""

    def __init__(self, phase: str, decision: str, note: str = ""):
        super().__init__(APPROVAL_DECLINED_EXIT)
        self.phase = phase
        self.decision = decision
        self.note = note

    def __str__(self) -> str:
        return f"{self.decision} at {self.phase!r}" + (f" — {self.note}" if self.note else "")


class Iteration:
    """One turn of a `repeat` phase. It commits itself, by `checkpoint()`.

    A phase that loops saves one checkpoint per iteration — that is what makes a
    restart re-enter at the first iteration that never committed instead of
    starting the loop again.
    """

    def __init__(self, handle: "PhaseHandle", index: int, total: int):
        self.handle = handle
        self.index = index
        self.total = total

    @property
    def label(self) -> str:
        return f"{self.index}/{self.total}"

    def checkpoint(self, **payload) -> None:
        self.handle.commit(self.index, payload)


class PhaseHandle:
    """One open phase. `replay` is set when the phase already committed elsewhere.

    A replayed handle runs no agent and writes nothing new: its `call()` returns
    the envelope the earlier run recorded, and its `log()` is a console line
    only. That is what makes a resume free — the work is read, not bought twice.
    """

    def __init__(self, run: "Run", phase: Phase | None, replay: str | None = None):
        self.run = run
        self.phase = phase
        self.replay = replay

    def log(self, **payload) -> None:
        if self.replay:
            self.run.console.note(", ".join(f"{k}: {v}" for k, v in payload.items()))
            return
        self.run.tracer.event(EventRecord(smidja_id=self.run.smidja_id,
                                          phase_id=self.phase.phase_id,
                                          type="log", name=self.phase.params.name,
                                          payload=payload))
        self.run.console.note(", ".join(f"{k}: {v}" for k, v in payload.items()))
        if self.phase.params.kind == "engineer" and "input" in payload:
            self.run.tracer.session_request(self.run.smidja_id, str(payload["input"]))

    def call(self, call: AgentCall) -> EnvelopeBase:
        if self.replay:
            return self.run.resume_plan.envelope_for(self.replay, call.output_type)
        if self.phase.params.kind != "agent":
            raise RuntimeError("ph.call() is only valid inside an agent phase")
        return agents.execute(self.run, self.phase, call)

    def iterations(self, total: int) -> Iterator[Iteration]:
        """The turns of a `repeat` phase this process still owes.

        Declaring the total first is what lets the record say `2/4` instead of a
        bare count. Iterations already on the trace are announced and skipped —
        not re-run, because a checkpoint is a commit and this house does not buy
        committed work twice.
        """
        if self.replay or self.phase is None:
            self.run.console.note(f"{self.replay or 'phase'}: every iteration already committed — "
                                  f"nothing to repeat")
            return
        done = self.run.declare_iterations(self.phase, total)
        for index in range(1, total + 1):
            if index in done:
                self.run.console.note(f"iteration {index}/{total} already committed — "
                                      f"handed forward, not re-run")
                continue
            yield Iteration(self, index, total)

    def commit(self, index: int, payload: dict) -> None:
        """Save this iteration's checkpoint. A replayed phase commits nothing new."""
        if self.phase is None:
            return
        self.run.tracer.event(EventRecord(
            smidja_id=self.run.smidja_id, phase_id=self.phase.phase_id,
            type="checkpoint", name=self.phase.params.name,
            payload={"iteration": index, "done": True, **payload}))
        self.run.console.note(f"checkpoint {index} committed")


class Run:
    def __init__(self, cfg, smidja_id: str, tracer, engineer: str,
                 repo_root: str | None = None,
                 data_base: str | Path | None = None):
        self.cfg = cfg
        self.smidja_id = smidja_id
        self.tracer = tracer
        self.console = Console(tracer, smidja_id)
        self.engineer = engineer
        self.phases: list[Phase] = []
        self._subagent_counter = 0   # unique ids for orchestrator task-dispatch lanes
        # Lanes opened at tool_execution_start (G2) keyed by (phase_id, call_id)
        # so the terminal materialization closes the SAME lane instead of
        # opening a duplicate. Additive — absent lanes fall back to old behavior.
        self._open_subagent_lanes: dict[str, dict[str, str]] = {}
        self.tokens = 0
        self.cost = 0.0
        self._seq = tracer.max_phase_seq(smidja_id)   # a joined run continues the sequence
        # Project-aware anchor: session.ensure passes the project repo root +
        # its smidja/smidja_data base (agents work in the project, sessions + db
        # live there too). Falls back to the config-relative defaults.
        self.repo_root = Path(repo_root) if repo_root \
            else git_helper.repo_root()             # where every agent is spawned to work
        base = Path(data_base) if data_base \
            else self.repo_root / cfg.defaults.data_dir
        self.session_dir = ensure_dir(base / "sessions" / smidja_id)
        self.context_handoff_dir = ensure_dir(self.session_dir / "context_handoff")
        self._agent_map_path = self.session_dir / "agent_map.json"
        self.agent_map: dict = (json.loads(self._agent_map_path.read_text())
                                if self._agent_map_path.exists() else {})
        # Resume: armed by session.ensure() when this process is re-entering a
        # run at a phase that already committed. None on a normal run.
        self.resume_plan = None
        self._replaying: list[str] = []      # stack: which replayed phase are we inside
        # A commit phase is code, not an agent, and it calls git_helper directly.
        # Binding the run lets git_helper see that its phase is being replayed
        # instead of committing the same tree a second time.
        git_helper.bind(self)

    # ── agent map (smidja_id -> per-agent coding-agent session ids) ────────────
    def save_agent_map(self, agent: str, entry: dict) -> None:
        self.agent_map[agent] = entry
        self._agent_map_path.write_text(json.dumps(self.agent_map, indent=2))

    # ── usage (run totals mirror what the tracer accumulates in sqlite) ─────
    def add_usage(self, tokens: int, cost: float) -> None:
        self.tokens += tokens
        self.cost += cost
        self.tracer.session_add_usage(self.smidja_id, tokens, cost)

    # ── resume ─────────────────────────────────────────────────────────────
    @property
    def replaying(self) -> bool:
        """True inside a phase that already committed — its effects are read, not run."""
        return bool(self._replaying)

    @property
    def replaying_phase(self) -> str:
        return self._replaying[-1] if self._replaying else ""

    def arm_resume(self, plan) -> None:
        """Enter this process as a continuation: these phases are already paid for."""
        self.resume_plan = plan
        self.tracer.event(EventRecord(
            smidja_id=self.smidja_id, type="resume", name=plan.boundary,
            payload={"checkpoint": plan.boundary, "from_phase": plan.from_phase,
                     "handed_forward": plan.replay}))
        self.console.note(f"resume: checkpoint {plan.boundary} — re-entering at "
                          f"{plan.from_phase or 'the next phase the chain opens'}")
        for name in plan.replay:
            self.console.note(f"resume: {name} already committed — handed forward, not re-run")

    # ── repeat phases: one checkpoint per iteration ──────────────────────────
    def declare_iterations(self, phase: Phase, total: int) -> set[int]:
        """Record the loop's size, and return the iterations already committed.

        The `progress` event is the declaration (so the record can say `2/4`);
        the `checkpoint` events are the commits. A restart counts them here and
        skips exactly those — nothing else is skipped, ever.
        """
        self.tracer.event(EventRecord(smidja_id=self.smidja_id, phase_id=phase.phase_id,
                                      type="progress", name=phase.params.name,
                                      payload={"total": total}))
        rows = self.tracer.conn.execute(
            "SELECT payload_json FROM events WHERE phase_id = ? AND type = 'checkpoint'",
            (phase.phase_id,)).fetchall()
        done: set[int] = set()
        for row in rows:
            try:
                payload = json.loads(row[0] or "{}")
            except ValueError:
                continue
            if payload.get("done"):
                done.add(int(payload.get("iteration") or 0))
        if done:
            self.console.note(f"{total - len(done)} of {total} iterations still owed "
                              f"({sorted(done)} already committed)")
        return done

    # ── approval phases: the block does not run without a person's word ──────
    def _await_decision(self, phase: Phase) -> None:
        """Open an `approval` phase, or settle it as waiting / declined.

        No decision is NOT an approval. That is the whole contract: the block is
        never entered on silence, and a restart re-enters here and waits again
        rather than passing quietly.
        """
        name = phase.params.name
        decision = self.tracer.decision_latest(self.smidja_id, name) or {}
        answer: ApprovalDecision = decision.get("decision") or ""     # type: ignore[assignment]
        door = f"just decide {self.smidja_id} {name} approve"

        if answer == "approved":
            self.tracer.event(EventRecord(
                smidja_id=self.smidja_id, phase_id=phase.phase_id, type="approval",
                name=name, payload={"decision": "approved", "by": decision.get("by", ""),
                                    "note": decision.get("note", "")}))
            self.console.note(f"approval {name}: approved by "
                              f"{decision.get('by') or 'a person'}")
            return

        phase.ended_at = now_iso()
        if answer in ("declined", "cancelled"):
            phase.status = "fail"
            phase.error = f"{answer} by {decision.get('by') or 'a person'}" \
                          + (f": {decision.get('note')}" if decision.get("note") else "")
            self.tracer.event(EventRecord(
                smidja_id=self.smidja_id, phase_id=phase.phase_id, type="approval",
                name=name, payload={"decision": answer, "by": decision.get("by", ""),
                                    "note": decision.get("note", "")}))
            self.tracer.event(EventRecord(smidja_id=self.smidja_id, phase_id=phase.phase_id,
                                          type="phase_end", name=name,
                                          payload={"status": "fail"}))
            self.tracer.phase_upsert(phase)
            self.tracer.session_status(self.smidja_id, "declined")
            self.console.note(f"approval {name}: {phase.error} — the block was never run")
            raise ApprovalDeclined(name, answer, decision.get("note") or "")

        phase.status = "waiting"
        phase.error = None
        self.tracer.event(EventRecord(
            smidja_id=self.smidja_id, phase_id=phase.phase_id, type="approval",
            name=name, payload={"decision": "pending"}))
        self.tracer.phase_upsert(phase)
        self.tracer.session_status(self.smidja_id, "waiting")
        self.console.note(f"approval {name}: waiting for a decision — the block has not run")
        self.console.note(f"  decide with: {door}")
        raise ApprovalWaiting(name, door)

    def _reopen_target(self, name: str) -> Optional[dict]:
        """The row a resumed phase re-enters, when this phase is where it stopped.

        A phase is one row, not one row per attempt: a `waiting` approval that is
        later approved, or a failed phase retried, reopens its own row so the
        record shows one phase whose steps tell the story.
        """
        if self.resume_plan is None or self.resume_plan.from_phase != name:
            return None
        row = self.tracer.phase_by_name(self.smidja_id, name)
        if row is None or row["status"] == "success":
            return None
        return {"phase_id": row["phase_id"], "seq": row["seq"] or 0}

    # ── the phase primitive ─────────────────────────────────────────────────
    def phase(self, params: PhaseParams):
        """The one phase door — a live phase, or a replayed one.

        Both are context managers, so every chain keeps its `with run.phase(...)`
        shape and no chain has to know whether it is being resumed.
        """
        if self.resume_plan is not None and self.resume_plan.is_replay(params.name):
            return self._replayed(params)
        return self._live(params)

    @contextmanager
    def _replayed(self, params: PhaseParams):
        """A phase that committed in an earlier process: no row, no agent, no cost."""
        self._replaying.append(params.name)
        try:
            yield PhaseHandle(self, None, replay=params.name)
        finally:
            self._replaying.pop()

    @contextmanager
    def _live(self, params: PhaseParams):
        reopen = self._reopen_target(params.name)
        if reopen is not None:
            phase_id, seq = reopen["phase_id"], reopen["seq"]
            self.console.note(f"resume: re-entering phase {params.name!r} at its own row")
        else:
            self._seq += 1
            phase_id, seq = f"{self.smidja_id}_{self._seq:02d}_{params.name}", self._seq
        phase = Phase(phase_id=phase_id, smidja_id=self.smidja_id, seq=seq,
                      params=params, status="running", started_at=now_iso())
        self.phases.append(phase)
        self.tracer.phase_upsert(phase)
        self.tracer.event(EventRecord(smidja_id=self.smidja_id, phase_id=phase.phase_id,
                                      type="phase_start", name=params.name,
                                      payload={"kind": params.kind, "owner": params.owner,
                                               "contract": params.contract,
                                               "description": params.description}))
        self.console.phase_started(phase)
        clock = time.monotonic()
        try:
            if params.contract == "approval":
                self._await_decision(phase)   # settled, or raised — the block is never entered on silence
            yield PhaseHandle(self, phase)
        except (ApprovalWaiting, ApprovalDeclined):
            raise                             # already settled in the record, on purpose
        except BaseException as error:
            phase.status = "fail"                      # success must be earned
            phase.error = str(error)[:1000]
            phase.ended_at = now_iso()
            self.tracer.event(EventRecord(smidja_id=self.smidja_id, phase_id=phase.phase_id,
                                          type="error", name=params.name,
                                          payload={"error": phase.error}))
            self.tracer.event(EventRecord(smidja_id=self.smidja_id, phase_id=phase.phase_id,
                                          type="phase_end", name=params.name,
                                          payload={"status": "fail"}))
            self.tracer.phase_upsert(phase)
            self.tracer.session_finish(self.smidja_id, ok=False)
            self.console.phase_ended(phase, time.monotonic() - clock)
            self.console.session_finished(False, self.tokens, self.cost,
                                          self.cfg.observability.db)
            raise
        else:
            phase.status = "success"
            phase.ended_at = now_iso()
            self.tracer.event(EventRecord(smidja_id=self.smidja_id, phase_id=phase.phase_id,
                                          type="phase_end", name=params.name,
                                          payload={"status": "success"}))
            self.tracer.phase_upsert(phase)
            self.console.phase_ended(phase, time.monotonic() - clock)

    # ── run outcome ─────────────────────────────────────────────────────────
    def finish(self, accepted: bool = True, reason: str = "") -> int:
        """Finalize the run and return its exit code. Call this exactly once.

        Two criteria, not one. Every phase must have passed, AND the smidja's own
        acceptance test must hold. They are different questions on purpose: a
        test phase that ran the suite did its job even when the suite came back
        red, so the PHASE succeeds while the RUN must not.

        This replaces a `succeeded` property that answered only the first
        question — and, being a property with side effects, wrote the session
        status and printed the banner before the caller's `and test.passed` was
        ever evaluated. A run whose suite never passed was recorded green in the
        db, on the terminal, and in the UI while exiting 1. Anyone reading the
        trace saw success; only a CI job checking `$?` saw the truth. One call
        now settles the db, the banner, and the exit code together, so the three
        cannot disagree.
        """
        phases_ok = bool(self.phases) and all(p.status == "success" for p in self.phases)
        ok = phases_ok and accepted
        if phases_ok and not accepted:
            note = reason or "the run's acceptance criterion was not met"
            self.tracer.event(EventRecord(
                smidja_id=self.smidja_id,
                phase_id=self.phases[-1].phase_id if self.phases else "",
                type="error", name="not_accepted", payload={"reason": note}))
            self.console.note(f"not accepted: {note}")
        self.tracer.session_finish(self.smidja_id, ok=ok)
        self.console.session_finished(ok, self.tokens, self.cost, self.cfg.observability.db)
        return 0 if ok else 1
