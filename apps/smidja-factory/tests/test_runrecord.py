"""The run as ONE record — the read side, and the approval contract it carries.

Two things are proved here, and they are the same thing seen twice:

  · `runrecord.load()` returns the run whole — phases, steps, state, and the one
    place it stopped — from a REAL tracer database, so a door, a resume and a UI
    read one shape instead of three private queries;
  · an `approval` phase is green only when a person said yes. A phase that
    reports success with no decision on record is a contradiction, and a resume
    refuses it rather than passing silently.

    uv run --with pydantic --with pyyaml --with rich --with python-dotenv \\
        python -m unittest discover -s apps/smidja-factory/tests -p 'test_runrecord.py'
"""

from __future__ import annotations

import importlib.util
import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]              # apps/smidja-factory
SHIPPED = HERE / "templates" / "smidja"
INSTANCE = HERE.parent / "smidja"
sys.path.insert(0, str(SHIPPED))

from smidja_modules import resume, runrecord                            # noqa: E402
from smidja_modules.data_types import (DecisionRecord, EventRecord,     # noqa: E402
                                       GateCheck, GateReport, Phase, PhaseParams,
                                       smidjaConfig, ConfigDefaults, ObservabilityConfig)
from smidja_modules.tracer import Tracer                                # noqa: E402

SID = "rec0de01"
DESCRIPTION = "Run the phase this test is reading back"
ASK = "add a /health endpoint"


class Trace:
    """A real trace, built row by row — no mocks, no hand-written SQL."""

    def __init__(self, root: Path):
        self.root = root
        self.data = root / "smidja_data"
        self.db = self.data / "smidja.db"
        self.session_dir = self.data / "sessions" / SID
        self.session_dir.mkdir(parents=True, exist_ok=True)
        self.tracer = Tracer(self.db, self.session_dir / "events.jsonl")
        self.tracer.session_start(SID, "tester", smidja_name="smidja_plan_build_test")
        self._phases: dict[str, Phase] = {}

    def phase(self, seq: int, name: str, *, lane: str = "code", owner: str = "quality",
              status: str = "success", contract: str = "ordinary",
              gates: list[tuple[str, bool]] = (), error: str = "") -> Phase:
        phase = Phase(phase_id=f"{SID}_{seq:02d}_{name}", smidja_id=SID, seq=seq,
                      params=PhaseParams(name=name, kind=lane, owner=owner,
                                         contract=contract, description=DESCRIPTION),
                      status=status, error=error or None)
        self.tracer.phase_upsert(phase)
        for gate_name, passed in gates:
            self.tracer.gate_row(phase, gate_name, GateReport(
                checks=[GateCheck(item=gate_name, ok=passed,
                                  note="" if passed else "missing artifact")]), attempt=1)
        self._phases[name] = phase
        return phase

    def log(self, phase_name: str, payload: dict) -> None:
        phase = self._phases[phase_name]
        self.tracer.event(EventRecord(smidja_id=SID, phase_id=phase.phase_id,
                                      type="log", name=phase_name, payload=payload))

    def checkpoint(self, seq: int, phase_name: str, iteration: int, total: int) -> None:
        phase = self._phases[phase_name]
        self.tracer.event(EventRecord(smidja_id=SID, phase_id=phase.phase_id,
                                      type="progress", name=phase_name,
                                      payload={"total": total}))
        self.tracer.event(EventRecord(smidja_id=SID, phase_id=phase.phase_id,
                                      type="checkpoint", name=phase_name,
                                      payload={"iteration": iteration, "done": True}))

    def envelope(self, phase_name: str, payload: dict) -> None:
        phase = self._phases[phase_name]
        self.tracer.envelope_row(phase, phase.params.owner, "GenericOutput",
                                 json.dumps(payload), valid=True, attempt=1)
        (self.session_dir / phase.params.owner).mkdir(parents=True, exist_ok=True)
        (self.session_dir / phase.params.owner / "envelope.json").write_text(
            json.dumps({**payload, "agent_name": phase.params.owner}))

    def decide(self, phase_name: str, decision: str, note: str = "") -> None:
        self.tracer.decision_record(DecisionRecord(smidja_id=SID, phase=phase_name,
                                                    decision=decision, by="the test",
                                                    note=note))

    def record(self) -> runrecord.RunRecord:
        return runrecord.load(runrecord.RecordQuery(
            smidja_id=SID, db_path=str(self.db), session_dir=str(self.session_dir)))

    def plan(self):
        return resume.plan(resume.ResumeQuery(
            smidja_id=SID, db_path=str(self.db), session_dir=str(self.session_dir)))


class RecordShapeTest(unittest.TestCase):
    """The record IS the run: phases, steps, state, and where it stopped."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.trace = Trace(self.root)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _three_phases(self) -> None:
        self.trace.phase(1, "request", lane="engineer", owner="tester")
        self.trace.log("request", {"input": ASK})
        self.trace.phase(2, "plan", lane="agent", owner="planner",
                         gates=[("artifacts_exist", True)])
        self.trace.envelope("plan", {"status": "success", "summary": "a plan",
                                     "artifacts": ["PLAN.md"]})
        self.trace.phase(3, "build", lane="agent", owner="builder", status="fail",
                         error="builder wrote nothing")

    def test_the_record_carries_phases_steps_state_and_the_place_it_stopped(self) -> None:
        self._three_phases()
        self.trace.tracer.session_finish(SID, ok=False)

        record = self.trace.record()

        self.assertEqual(record.status, "failed")
        self.assertEqual(record.chain, "smidja_plan_build_test")
        self.assertEqual(record.request, ASK, "the ask comes from the log, not the clipped column")
        self.assertEqual([phase.name for phase in record.phases],
                         ["request", "plan", "build"], "phases are in sequence order")
        self.assertEqual([phase.status for phase in record.phases], ["done", "done", "failed"])
        self.assertEqual(record.checkpoint, "plan")
        self.assertEqual(record.resume_at, "build", "the restart re-enters at the failure")
        self.assertIn("failed at 'build'", record.where_stopped)
        self.assertEqual(record.phase("plan").envelope["summary"], "a plan")
        self.assertTrue(any(step.kind == "log" for step in record.phase("request").steps),
                        "steps are the events the run recorded, in order")
        fields = dict(record.describe())
        self.assertEqual(fields["status"], "failed")
        self.assertEqual(fields["checkpoint"], "plan")

    def test_a_run_recorded_running_with_no_process_is_interrupted(self) -> None:
        self.trace.phase(1, "plan", lane="agent", owner="planner", status="running")

        record = self.trace.record()

        self.assertEqual(record.status, "interrupted",
                         "nothing is alive, so `running` would be a lie")
        self.assertEqual(record.phase("plan").status, "interrupted")
        self.assertEqual(record.live_pids, [])
        self.assertIn("the process is gone", record.where_stopped)

    def test_a_repeat_phase_counts_one_checkpoint_per_iteration(self) -> None:
        self.trace.phase(1, "watch", contract="repeat")
        for iteration in (1, 2, 3):
            self.trace.checkpoint(1, "watch", iteration, total=4)
        self.trace.phase(2, "close", status="fail")

        phase = self.trace.record().phase("watch")

        self.assertEqual(phase.checkpoints, 3)
        self.assertEqual(phase.progress, {"done": 3, "total": 4})

    def test_no_such_run_is_named_not_invented(self) -> None:
        with self.assertRaises(runrecord.RecordMissing):
            runrecord.load(runrecord.RecordQuery(
                smidja_id="nosuchid", db_path=str(self.trace.db),
                session_dir=str(self.trace.session_dir)))


class ApprovalContractTest(unittest.TestCase):
    """An approval phase is green only when a person said yes."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.trace = Trace(self.root)
        self.trace.phase(1, "plan", lane="agent", owner="planner")
        self.trace.envelope("plan", {"status": "success", "summary": "a plan"})
        self.trace.phase(2, "approve", lane="code", owner="tester", contract="approval")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_success_with_no_decision_is_not_green(self) -> None:
        """The phase says success; nobody signed. That is a contradiction, not a pass."""
        phase = self.trace.record().phase("approve")

        self.assertEqual(phase.contract, "approval")
        self.assertEqual(phase.approval, "pending")
        self.assertEqual(phase.status, "waiting", "the record never calls it done")
        self.assertFalse(phase.green)
        self.assertTrue(phase.lied)

    def test_a_resume_refuses_to_pass_an_unsigned_approval(self) -> None:
        with self.assertRaises(resume.ResumeRefused) as caught:
            self.trace.plan()

        self.assertEqual(caught.exception.reason, resume.NOTHING_GREEN)
        self.assertIn("signature nobody gave", caught.exception.detail)

    def test_a_waiting_run_says_which_decision_it_owes(self) -> None:
        self.trace.tracer.session_status(SID, "waiting")
        record = self.trace.record()

        self.assertEqual(record.status, "waiting")
        self.assertEqual(record.waiting_phase.name, "approve")
        self.assertIn("no decision", record.where_stopped)
        self.assertEqual(record.resume_at, "approve", "the restart re-enters where it waits")

    def test_an_approved_phase_is_green_and_resumes(self) -> None:
        # The shape a waiting run leaves: the phase row says `waiting`, no decision.
        self.trace.phase(2, "approve", lane="code", owner="tester",
                         contract="approval", status="waiting")
        self.trace.tracer.session_status(SID, "waiting")

        waiting = self.trace.plan()
        self.assertEqual(waiting.from_phase, "approve")
        self.assertEqual(waiting.from_contract, "approval")
        self.assertEqual(waiting.approval, "pending", "the plan names the decision it owes")

        self.trace.decide("approve", "approved", note="ship it")
        record = self.trace.record()
        self.assertEqual(record.phase("approve").approval, "approved")
        self.assertFalse(record.phase("approve").green,
                         "a yes is not the work: the block still has to run")

        resumed = self.trace.plan()
        self.assertEqual(resumed.from_phase, "approve")
        self.assertEqual(resumed.approval, "approved")

        # Once the block has run under that decision, the phase is green.
        self.trace.phase(2, "approve", lane="code", owner="tester",
                         contract="approval", status="success")
        self.assertTrue(self.trace.record().phase("approve").green)

    def test_a_declined_phase_is_neither_green_nor_resumable(self) -> None:
        self.trace.decide("approve", "declined", note="not this week")

        record = self.trace.record()
        self.assertFalse(record.phase("approve").green)
        self.assertEqual(record.phase("approve").status, "failed")

        with self.assertRaises(resume.ResumeRefused) as caught:
            self.trace.plan()
        self.assertEqual(caught.exception.reason, resume.NOTHING_GREEN)


class RecordDoorTest(unittest.TestCase):
    """`smidja record` prints the record a person reads — the same one resume reads."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.trace = Trace(self.root)
        self.trace.phase(1, "request", lane="engineer", owner="tester")
        self.trace.log("request", {"input": ASK})
        self.trace.phase(2, "plan", lane="agent", owner="planner")
        self.trace.envelope("plan", {"status": "success", "summary": "a plan"})
        self.trace.phase(3, "build", status="fail", error="builder wrote nothing")
        self.trace.log("build", {"summary": "the builder gave up", "changed": "none"})
        self.trace.tracer.session_finish(SID, ok=False)
        self.config = self.root / "roster.yaml"
        self.config.write_text(
            "defaults:\n"
            "  data_dir: {data}\n"
            "observability:\n"
            "  db: {db}\n"
            "agents: []\n".format(data=self.trace.data, db=self.trace.db))

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _door(self):
        path = INSTANCE / "smidja_record.py"
        spec = importlib.util.spec_from_file_location("smidja_record_door", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_the_door_prints_the_phases_the_steps_and_the_place_it_stopped(self) -> None:
        out = io.StringIO()
        with redirect_stdout(out):
            code = self._door().main(SID, str(self.config), False)

        printed = out.getvalue()
        self.assertEqual(code, 0)
        self.assertIn('"status","failed"', printed)
        self.assertIn('"checkpoint","plan"', printed)
        self.assertIn("phases[3]{seq,name,lane,contract,owner,status,checkpoints,approval}", printed)
        self.assertIn('"build"', printed)
        self.assertIn("steps[", printed)
        self.assertIn("the builder gave up", printed,
                      "the steps of the phase that stopped the run are the evidence")
        self.assertIn("pass --as-steps", printed,
                      "what is elided is counted, never silently dropped")
        self.assertNotIn(f'"input: {ASK}"', printed,
                         "a finished phase's steps do not bury where the run stopped")

    def test_as_steps_prints_the_whole_transcript(self) -> None:
        out = io.StringIO()
        with redirect_stdout(out):
            self._door().main(SID, str(self.config), False, True)

        printed = out.getvalue()
        self.assertIn(f'"input: {ASK}"', printed)
        self.assertNotIn("pass --as-steps", printed, "nothing is elided when all of it is asked for")

    def test_the_record_can_be_handed_over_whole_as_json(self) -> None:
        out = io.StringIO()
        with redirect_stdout(out):
            self._door().main(SID, str(self.config), True)

        payload = json.loads(out.getvalue())
        self.assertEqual(payload["checkpoint"], "plan")
        self.assertEqual([phase["name"] for phase in payload["phases"]],
                         ["request", "plan", "build"])
        self.assertEqual(payload["phases"][1]["envelope"]["summary"], "a plan")

    def test_a_missing_run_is_refused_by_name(self) -> None:
        out = io.StringIO()
        with redirect_stdout(out):
            code = self._door().main("nosuchid", str(self.config), False)
        self.assertEqual(code, 2)
        self.assertIn("no such run", out.getvalue())


if __name__ == "__main__":
    unittest.main()
