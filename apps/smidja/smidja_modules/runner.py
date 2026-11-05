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
from pathlib import Path

from . import agents, git_helper
from .console import Console
from .data_types import AgentCall, EnvelopeBase, EventRecord, Phase, PhaseParams
from .utils import ensure_dir, now_iso


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
        self.console.note(f"resume: checkpoint {plan.boundary} — re-entering at "
                          f"{plan.from_phase or 'the next phase the chain opens'}")
        for name in plan.replay:
            self.console.note(f"resume: {name} already committed — handed forward, not re-run")

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
        self._seq += 1
        phase = Phase(phase_id=f"{self.smidja_id}_{self._seq:02d}_{params.name}",
                      smidja_id=self.smidja_id, seq=self._seq, params=params,
                      status="running", started_at=now_iso())
        self.phases.append(phase)
        self.tracer.phase_upsert(phase)
        self.tracer.event(EventRecord(smidja_id=self.smidja_id, phase_id=phase.phase_id,
                                      type="phase_start", name=params.name,
                                      payload={"kind": params.kind, "owner": params.owner,
                                               "description": params.description}))
        self.console.phase_started(phase)
        clock = time.monotonic()
        try:
            yield PhaseHandle(self, phase)
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
