"""Resume from the last green phase — the checkpoint discipline, proved.

The three tests the feature must pass, plus the ones that keep it honest:

  · resume after a passing phase continues at the next one
  · resume after a failed gate refuses
  · resume with a changed roster refuses

Everything here reads and writes a REAL trace (`Tracer`, the same schema the
running smithy uses) built in a temporary directory — no mocks, no hand-written
SQL for the tables under test. A test that drifts from the schema fails here
before it fails in a run.

The modules under test are the SHIPPED copy (`templates/smidja/`), because that
is what `install.py` stamps into a user's repo; `ShippedCopyTest` fails if the
running instance in `apps/smidja/` has drifted from it.

    python3 -m unittest discover -s apps/smidja-factory/tests
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]              # apps/smidja-factory
SHIPPED = HERE / "templates" / "smidja"
INSTANCE = HERE.parent / "smidja"                       # apps/smidja (the running copy)
sys.path.insert(0, str(SHIPPED))

from smidja_modules import git_helper, quality, resume, runner          # noqa: E402
from smidja_modules.data_types import (AgentCall, BuildOutput, ConfigDefaults,  # noqa: E402
                                       EventRecord, GateCheck, GateReport,
                                       ObservabilityConfig, Phase, PhaseParams,
                                       PlanOutput, smidjaConfig)
from smidja_modules.tracer import Tracer                                 # noqa: E402

SID = "a1b2c3d4"
CHAIN = "smidja_plan_build_test"
DESCRIPTION = "Run the phase this test is driving"


class TraceFixture:
    """A real trace with a real session directory, built phase by phase."""

    def __init__(self, root: Path):
        self.root = root
        self.data = root / "smidja_data"
        self.db = self.data / "smidja.db"
        self.session_dir = self.data / "sessions" / SID
        self.session_dir.mkdir(parents=True, exist_ok=True)
        self.tracer = Tracer(self.db, self.session_dir / "events.jsonl")
        self.tracer.session_start(SID, "tester", smidja_name=CHAIN)
        self._phases: dict[str, Phase] = {}

    # ── building the record ────────────────────────────────────────────────
    def phase(self, seq: int, name: str, kind: str = "agent", owner: str = "planner",
              status: str = "success", gates: list[tuple[str, bool]] = (),
              error: str = "") -> Phase:
        phase = Phase(phase_id=f"{SID}_{seq:02d}_{name}", smidja_id=SID, seq=seq,
                      params=PhaseParams(name=name, kind=kind, owner=owner,
                                         description=DESCRIPTION),
                      status=status, error=error or None)
        self.tracer.phase_upsert(phase)
        for gate_name, passed in gates:
            report = GateReport(checks=[GateCheck(item=gate_name, ok=passed,
                                                  note="" if passed else "missing artifact")])
            self.tracer.gate_row(phase, gate_name, report, attempt=1)
        self._phases[name] = phase
        return phase

    def request(self, text: str) -> None:
        phase = self.phase(1, "request", kind="engineer", owner="tester")
        self.log("request", {"input": text})

    def envelope(self, phase_name: str, payload: dict) -> None:
        phase = self._phases[phase_name]
        self.tracer.envelope_row(phase, phase.params.owner, type(payload).__name__,
                                 json.dumps(payload), valid=True, attempt=1)
        (self.session_dir / phase.params.owner).mkdir(parents=True, exist_ok=True)
        (self.session_dir / phase.params.owner / "envelope.json").write_text(json.dumps(payload))

    def log(self, phase_name: str, payload: dict) -> None:
        phase = self._phases[phase_name]
        self.tracer.event(EventRecord(smidja_id=SID, phase_id=phase.phase_id,
                                      type="log", name=phase_name, payload=payload))

    def agent(self, name: str, model: str, session_id: str) -> None:
        path = self.session_dir / "agent_map.json"
        data = json.loads(path.read_text()) if path.is_file() else {}
        data[name] = {"session_id": session_id, "model": model, "coding_agent": "pi"}
        path.write_text(json.dumps(data, indent=2))

    # ── asking the question ────────────────────────────────────────────────
    def plan(self, roster: dict[str, str] | None = None, from_phase: str | None = None):
        return resume.plan(resume.ResumeQuery(
            smidja_id=SID, db_path=str(self.db), session_dir=str(self.session_dir),
            roster=roster or {}, from_phase=from_phase))


class ResumePlanTest(unittest.TestCase):
    """What the trace says, and what the door does with it."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.trace = TraceFixture(self.root)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    # ── the happy road ─────────────────────────────────────────────────────
    def test_resume_after_a_passing_phase_continues_at_the_next_one(self) -> None:
        """The checkpoint is the last green phase; the run continues after it."""
        self.trace.request("add a /health endpoint")
        self.trace.phase(2, "plan", gates=[("artifacts_exist", True)])
        self.trace.envelope("plan", {"status": "success", "summary": "a plan",
                                     "artifacts": ["PLAN.md"]})
        self.trace.agent("planner", "openrouter/planner-a", "smidja-a1b2c3d4-planner-0001")

        plan = self.trace.plan()

        self.assertEqual(plan.boundary, "plan")
        self.assertEqual(plan.replay, ["request", "plan"])
        self.assertEqual(plan.from_phase, "", "nothing follows the checkpoint yet — the chain decides")
        self.assertEqual(plan.envelopes["plan"]["summary"], "a plan",
                         "the stored envelope is what the next agent is handed")
        self.assertEqual(plan.sessions["planner"], "smidja-a1b2c3d4-planner-0001",
                         "the agent's own session id survives, so its context does")
        self.assertEqual(plan.request, "add a /health endpoint")
        self.assertEqual(plan.chain, CHAIN)

    def test_the_failed_phase_is_where_the_run_re_enters(self) -> None:
        """A run that fails at phase three continues AT phase three, never past it."""
        self.trace.request("add a /health endpoint")
        self.trace.phase(2, "plan", gates=[("artifacts_exist", True)])
        self.trace.envelope("plan", {"status": "success", "summary": "a plan"})
        self.trace.phase(3, "build", status="fail", error="builder wrote nothing",
                         gates=[("diff_matches_claims", False)])

        plan = self.trace.plan()

        self.assertEqual(plan.boundary, "plan", "the checkpoint is the last green phase")
        self.assertEqual(plan.from_phase, "build", "and the run re-enters at the failure")
        self.assertEqual(plan.replay, ["request", "plan"])

    # ── the refusals: the vocabulary is the feature ────────────────────────
    def test_resume_of_an_unrecorded_run_refuses(self) -> None:
        with self.assertRaises(resume.ResumeRefused) as caught:
            resume.plan(resume.ResumeQuery(smidja_id="nosuchid", db_path=str(self.trace.db),
                                           session_dir=str(self.trace.session_dir), roster={}))
        self.assertEqual(caught.exception.reason, resume.NO_SUCH_RUN)

    def test_resume_after_a_failed_gate_refuses(self) -> None:
        """A phase that reports success on a failed gate is a lie — never resume past it."""
        self.trace.request("add a /health endpoint")
        self.trace.phase(2, "plan", gates=[("artifacts_exist", True)])
        self.trace.envelope("plan", {"status": "success", "summary": "a plan"})
        self.trace.phase(3, "build", status="success", gates=[("diff_matches_claims", False)])

        with self.assertRaises(resume.ResumeRefused) as caught:
            self.trace.plan()
        self.assertEqual(caught.exception.reason, resume.NOTHING_GREEN)
        self.assertIn("build", caught.exception.detail)

    def test_resume_with_nothing_green_refuses(self) -> None:
        self.trace.phase(1, "plan", status="fail", gates=[("artifacts_exist", False)])

        with self.assertRaises(resume.ResumeRefused) as caught:
            self.trace.plan()
        self.assertEqual(caught.exception.reason, resume.NOTHING_GREEN)

    def test_a_finished_green_run_has_nothing_to_continue(self) -> None:
        """Every phase committed and the run closed green — there is no phase to re-enter at."""
        self.trace.request("add a /health endpoint")
        self.trace.phase(2, "plan", gates=[("artifacts_exist", True)])
        self.trace.envelope("plan", {"status": "success", "summary": "a plan"})
        self.trace.tracer.session_finish(SID, ok=True)

        with self.assertRaises(resume.ResumeComplete):
            self.trace.plan()
        # ... and the override the message names actually works.
        self.assertEqual(self.trace.plan(from_phase="plan").from_phase, "plan")

    def test_a_phase_that_did_not_commit_is_never_skipped(self) -> None:
        """--from-phase may re-run a phase; it may not jump over a red one."""
        self.trace.request("add a /health endpoint")
        self.trace.phase(2, "plan", status="fail", gates=[("artifacts_exist", False)])
        self.trace.phase(3, "build", gates=[("diff_matches_claims", True)])

        with self.assertRaises(resume.ResumeRefused) as caught:
            self.trace.plan(from_phase="build")
        self.assertEqual(caught.exception.reason, resume.NOTHING_GREEN)
        self.assertIn("plan", caught.exception.detail)

    def test_resume_with_a_changed_roster_refuses(self) -> None:
        """A changed model means a fresh session — and a fresh session is not a resume."""
        self.trace.request("add a /health endpoint")
        self.trace.phase(2, "plan", gates=[("artifacts_exist", True)])
        self.trace.envelope("plan", {"status": "success", "summary": "a plan"})
        self.trace.agent("planner", "openrouter/planner-a", "smidja-a1b2c3d4-planner-0001")

        with self.assertRaises(resume.ResumeRefused) as caught:
            self.trace.plan(roster={"planner": "openrouter/planner-b"})
        self.assertEqual(caught.exception.reason, resume.ROSTER_CHANGED)
        self.assertIn("openrouter/planner-b", caught.exception.detail)

    def test_the_same_roster_resumes(self) -> None:
        self.trace.request("add a /health endpoint")
        self.trace.phase(2, "plan", gates=[("artifacts_exist", True)])
        self.trace.envelope("plan", {"status": "success", "summary": "a plan"})
        self.trace.agent("planner", "openrouter/planner-a", "smidja-a1b2c3d4-planner-0001")

        plan = self.trace.plan(roster={"planner": "openrouter/planner-a"})
        self.assertEqual(plan.boundary, "plan")


class RunReplayTest(unittest.TestCase):
    """The run side: a committed phase is read, not bought twice."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.trace = TraceFixture(self.root)
        self.cfg = smidjaConfig(
            defaults=ConfigDefaults(data_dir=str(self.trace.data)),
            observability=ObservabilityConfig(db=str(self.trace.db)))
        self.run = runner.Run(cfg=self.cfg, smidja_id=SID, tracer=self.trace.tracer,
                              engineer="tester", repo_root=str(self.root),
                              data_base=str(self.trace.data))

    def tearDown(self) -> None:
        git_helper.bind(None)
        self._tmp.cleanup()

    def _arm(self, from_phase: str | None = None) -> resume.ResumePlan:
        plan = self.trace.plan(from_phase=from_phase)
        self.run.arm_resume(plan)
        return plan

    def test_a_replayed_agent_phase_hands_its_envelope_forward_and_spawns_nothing(self) -> None:
        self.trace.request("add a /health endpoint")
        self.trace.phase(2, "plan", gates=[("artifacts_exist", True)])
        self.trace.envelope("plan", {"status": "success", "summary": "a plan",
                                     "artifacts": ["PLAN.md"]})
        self._arm()

        with self.run.phase(PhaseParams(name="plan", kind="agent", owner="planner",
                                        description=DESCRIPTION)) as ph:
            self.assertTrue(self.run.replaying)
            envelope = ph.call(AgentCall(output_type=PlanOutput, prompt="ignored"))
            # A real call would have spawned pi against a model this test never
            # configured; the stored envelope coming back is the proof it did not.
            self.assertIsInstance(envelope, PlanOutput)
            self.assertEqual(envelope.summary, "a plan")

        self.assertFalse(self.run.replaying)
        self.assertEqual(self.run.phases, [], "a replayed phase writes no new phase row")

        with self.run.phase(PhaseParams(name="build", kind="code", owner="git",
                                        description=DESCRIPTION)) as ph:
            self.assertFalse(self.run.replaying)
            self.assertIsNotNone(ph.phase, "the next phase runs for real")
        self.assertEqual([p.params.name for p in self.run.phases], ["build"])

    def test_a_replayed_test_phase_returns_the_recorded_verdict(self) -> None:
        self.trace.request("add a /health endpoint")
        self.trace.phase(2, "test_1", kind="code", owner="quality")
        self.trace.log("test_1", {"passed": True, "checks": "1/1", "artifacts": "quality/01_test"})
        self.trace.phase(3, "commit", kind="code", owner="git", status="fail")
        plan = self.trace.plan()
        self.assertEqual(plan.boundary, "test_1")
        self.run.arm_resume(plan)

        with self.run.phase(PhaseParams(name="test_1", kind="code", owner="quality",
                                        description=DESCRIPTION)):
            result = quality.run_tests(self.run)
        self.assertTrue(result.passed)
        self.assertEqual(result.checks[0].command, "(replayed from the trace)",
                         "the command was not run again")
        self.assertFalse((self.run.context_handoff_dir / "quality").exists(),
                         "a replayed block writes no new artifact")

    def test_a_replayed_commit_returns_the_recorded_sha(self) -> None:
        self.trace.request("add a /health endpoint")
        self.trace.phase(2, "commit", kind="code", owner="git")
        self.trace.log("commit", {"sha": "abc1234", "message": "smidja: the work"})
        self.trace.phase(3, "test_1", kind="code", owner="quality", status="fail")
        self.run.arm_resume(self.trace.plan())

        with self.run.phase(PhaseParams(name="commit", kind="code", owner="git",
                                        description=DESCRIPTION)) as ph:
            # The temp dir is not a git repository, so a real commit here would
            # raise. The recorded sha coming back is the proof it was replayed.
            self.assertEqual(git_helper.commit_all("ignored"), "abc1234")


class ShippedCopyTest(unittest.TestCase):
    """The template is what a user's repo gets — the instance must not drift from it."""

    MODULES = ("resume.py", "runrecord.py", "runner.py", "session.py", "tracer.py",
               "quality.py", "changes.py", "git_helper.py", "data_types.py")

    def test_the_running_instance_is_the_shipped_template(self) -> None:
        if not INSTANCE.is_dir():
            self.skipTest("no running instance on this machine — the template is the truth")
        for name in self.MODULES:
            with self.subTest(module=name):
                shipped = (SHIPPED / "smidja_modules" / name).read_text()
                running = (INSTANCE / "smidja_modules" / name).read_text()
                self.assertEqual(shipped, running,
                                 f"smidja_modules/{name} differs between the template and the "
                                 f"running instance — one of them was edited alone")
        for name in ("smidja_resume.py", "smidja_record.py", "smidja_decide.py"):
            with self.subTest(file=name):
                self.assertEqual((SHIPPED / name).read_text(), (INSTANCE / name).read_text())


if __name__ == "__main__":
    unittest.main()
