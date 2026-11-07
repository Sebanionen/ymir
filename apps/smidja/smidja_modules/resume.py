"""Resume: re-enter a run at its last committed phase — or refuse and say why.

The shape is pi-durable's checkpoint discipline
(`github.com/zerwiz/durable-pi`, `apps/dpi-backend/tests/recovery.test.ts`): a
run is a sequence of named phases; **every phase commits a checkpoint when it
completes**, and a restart re-enters at the phase the checkpoint names — never at
the top, and never past a phase that did not commit. The reference proves it by
killing the server with SIGKILL and letting it come back with no client
attached; `apps/smidja-factory/tests/test_recovery.py` proves the same here.

Translated to the smithy:

  checkpoint   the last phase that is green AND whose gate passed AND — when its
               contract is `approval` — that a person actually approved
  work         that phase's envelope (agent phases), its recorded verdict (code
               phases) or its committed iterations (repeat phases) — handed
               forward, never recomputed
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
                                  reports success on a failed gate, or an
                                  `approval` phase that finished with nobody's
                                  decision on record)
  the roster changed since this run   an agent's model is not the one the run
                                  was started with — a changed model means a
                                  fresh session, and a bad resume is worse
                                  than none

The record it reads is `runrecord.RunRecord` — the same shape the terminal doors
and any future UI render, so a resume and a client can never disagree about what
the run was.
"""

from __future__ import annotations

import os
from typing import Any, Optional

from pydantic import BaseModel, Field

from . import runrecord
from .data_types import BaseRef, ChangeSet, QualityCheckResult, QualityResult

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
    from_contract: str = ""               # ordinary | approval | repeat, at the re-entry point
    approval: str = ""                    # from_phase's decision state, when it is an approval phase
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
                f"re-enter at:    {self.from_phase or 'the next phase the chain opens'}"]
        if self.from_contract:
            rows.append(f"contract:       {self.from_contract}")
        if self.approval:
            rows.append(f"approval:       {self.approval}")
        rows.append(f"handed forward: {', '.join(self.replay) or '(none)'}")
        for agent, session in self.sessions.items():
            rows.append(f"session:        {agent} -> {session} ({self.models.get(agent, '?')})")
        return rows


def plan(query: ResumeQuery) -> ResumePlan:
    """Decide the resume point, or refuse. One read of the record, one answer."""
    try:
        record = runrecord.load(runrecord.RecordQuery(
            smidja_id=query.smidja_id, db_path=query.db_path,
            session_dir=query.session_dir))
    except runrecord.RecordMissing as missing:
        raise ResumeRefused(NO_SUCH_RUN, str(missing)) from missing

    _refuse_if_alive(record)
    phases = record.phases
    if not phases:
        raise ResumeRefused(NOTHING_GREEN, "the run recorded no phase at all")

    # A phase that calls itself successful while a gate failed — or, being an
    # approval phase, while no decision exists — is a contradiction. Resuming
    # past it would repeat the lie; resuming at it would re-run a phase the
    # record already calls green. Neither is honest, so refuse.
    for phase in phases:
        if phase.lied:
            if phase.contract == "approval":
                raise ResumeRefused(
                    NOTHING_GREEN,
                    f"phase {phase.name!r} is an approval phase recorded successful with no "
                    f"decision on record — a signature nobody gave is not a phase that passed")
            failed = [gate.gate for gate in phase.gates if not gate.passed]
            raise ResumeRefused(
                NOTHING_GREEN,
                f"phase {phase.name!r} reports success but its gate "
                f"{', '.join(failed)} failed — resuming would hide the failure")

    boundary = next((phase for phase in reversed(phases) if phase.green), None)
    if boundary is None:
        raise ResumeRefused(
            NOTHING_GREEN,
            "no phase is both green and gate-passed — there is no proven ground to stand on")

    replay, target = _resume_point(phases, boundary, query.from_phase)

    # A run that FINISHED green has nothing to continue. A run that died after
    # its last green phase has — the chain still owes the phases it never
    # opened. The record's own status is the fact that tells them apart.
    if target is None and len(replay) == len(phases) and record.status == "completed":
        raise ResumeComplete(
            f"this run finished green (checkpoint {boundary.name}) — there is nothing "
            f"left to continue. Use --from-phase <name> to re-run a phase")

    for phase in replay:
        if not phase.green:
            raise ResumeRefused(
                NOTHING_GREEN,
                f"phase {phase.name!r} is {phase.status} and would be skipped — "
                f"a phase that did not commit is never resumed past")
        if phase.lane == "agent" and phase.envelope is None:
            raise ResumeRefused(
                NOTHING_GREEN,
                f"phase {phase.name!r} is green but its envelope is not in the record — "
                f"there is nothing to hand to the next agent")
        if phase.lane == "code" and phase.logged is None and phase.contract != "approval":
            raise ResumeRefused(
                NOTHING_GREEN,
                f"phase {phase.name!r} is green but logged no verdict — replaying it "
                f"would re-run work this run already paid for")

    _refuse_on_roster_change(record, query)

    return ResumePlan(
        smidja_id=query.smidja_id,
        chain=record.chain,
        request=record.request,
        boundary=boundary.name,
        boundary_seq=boundary.seq,
        from_phase=target.name if target else "",
        from_contract=target.contract if target else "",
        approval=target.approval if target and target.contract == "approval" else "",
        replay=[phase.name for phase in replay],
        envelopes={phase.name: phase.envelope for phase in replay
                   if phase.lane == "agent" and phase.envelope is not None},
        records={phase.name: phase.logged for phase in replay
                 if phase.lane == "code" and phase.logged is not None},
        sessions=record.agent_sessions,
        models=record.models,
    )


def _resume_point(phases: list[runrecord.PhaseRun], boundary: runrecord.PhaseRun,
                  from_phase: Optional[str]) -> tuple[list[runrecord.PhaseRun],
                                                      Optional[runrecord.PhaseRun]]:
    """(phases to hand forward, the phase to re-enter at)."""
    if from_phase:
        target = next((phase for phase in phases if phase.name == from_phase), None)
        if target is None:
            recorded = ", ".join(phase.name for phase in phases)
            raise ResumeRefused(
                NO_SUCH_RUN,
                f"phase {from_phase!r} is not in this run — it recorded: {recorded}")
        return [phase for phase in phases if phase.seq < target.seq], target
    later = [phase for phase in phases if phase.seq > boundary.seq]
    return [phase for phase in phases if phase.seq <= boundary.seq], (later[0] if later else None)


def _refuse_if_alive(record: runrecord.RunRecord) -> None:
    """A recorded process that is still breathing means the run is still running.

    `ended_at IS NULL` alone is not enough: a SIGKILLed run leaves its rows open
    forever. The pid is the fact — ask the kernel, never the bookkeeping.
    """
    for pid in record.live_pids:
        if pid and pid != os.getpid():
            raise ResumeBusy(f"the run is still alive (pid {pid}) — stop it first, then resume")


def _refuse_on_roster_change(record: runrecord.RunRecord, query: ResumeQuery) -> None:
    """A changed model means a fresh session — and a fresh session is not a resume."""
    for agent, model in (query.roster or {}).items():
        was = record.models.get(agent, "")
        if was and model and was != model:
            raise ResumeRefused(
                ROSTER_CHANGED,
                f"{agent}: the run used {was}, the roster now names {model} — "
                f"a changed model starts a fresh session, which is not a resume")


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
