"""SIGKILL recovery — pi-durable's recovery test, proved on the smithy.

The reference (`github.com/zerwiz/durable-pi`,
`apps/dpi-backend/tests/recovery.test.ts`) kills the server with SIGKILL in the
middle of a durable job and asserts the job comes back from its checkpoint with
**no client attached**. This is the same test for us, and the same four claims:

  (a) the restart re-enters at the last green phase
  (b) committed envelopes are reused, not bought again
  (c) no completed phase's work is recomputed — proved by a marker line per
      execution, not by a status word the resumed process could be lying about
  (d) an `approval` phase with no decision does NOT pass silently

Nothing polls the trace while the restarted run is working: the record is read
only after the process has exited, so the recovery is the run's own doing.

The chain under test is `fixtures/recovery_chain.py` — a real subprocess, with
the SHIPPED modules on its path and a real tracer database, killed with a real
SIGKILL. A status word cannot fake that.

    uv run --with pydantic --with pyyaml --with rich --with python-dotenv \\
        python -m unittest discover -s apps/smidja-factory/tests -p 'test_recovery.py'
"""

from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]              # apps/smidja-factory
SHIPPED = HERE / "templates" / "smidja"
CHAIN = HERE / "tests" / "fixtures" / "recovery_chain.py"
DECIDE = HERE.parent / "smidja" / "smidja_decide.py"
sys.path.insert(0, str(SHIPPED))

from smidja_modules import runrecord                                  # noqa: E402

SID = "c0ffee01"
ASK = "add a /health endpoint that survives a crash"


class RecoveryTest(unittest.TestCase):
    """One run, killed mid-phase, recovered with nothing watching it."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.data = self.root / "smidja_data"
        self.markers = self.root / "markers"
        self.data.mkdir(parents=True, exist_ok=True)
        self.session_dir = self.data / "sessions" / SID
        (self.root / "prompts").mkdir(exist_ok=True)
        (self.root / "prompts" / "system.md").write_text("fixture system prompt\n")
        (self.root / "prompts" / "user.md").write_text("{{prompt}}\n")
        self.config = self.root / "roster.yaml"
        self.config.write_text(
            "defaults:\n"
            "  coding_agent: pi\n"
            "  model: test/fixture-model\n"
            "  thinking: \"off\"\n"
            f"  data_dir: {self.data}\n"
            "observability:\n"
            f"  db: {self.data / 'smidja.db'}\n"
            "agents:\n"
            "  - name: planner\n"
            "    model: test/fixture-model\n"
            "    purpose: commit a plan\n"
            f"    prompt_engineering:\n"
            f"      system: {self.root / 'prompts' / 'system.md'}\n"
            f"      user: {self.root / 'prompts' / 'user.md'}\n"
        )

    def tearDown(self) -> None:
        self._tmp.cleanup()

    # ── driving the real chain ─────────────────────────────────────────────
    def _launch(self, resume: bool) -> subprocess.Popen:
        env = dict(os.environ)
        env.pop("SMIDJA_RESUME_FROM", None)
        if resume:
            env["SMIDJA_RESUME_FROM"] = ""      # present = continue this run
        return subprocess.Popen(
            [sys.executable, str(CHAIN), ASK, "--config", str(self.config),
             "--smidja-id", SID, "--markers", str(self.markers)],
            cwd=str(self.root), env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def _kill_mid_build(self) -> subprocess.Popen:
        """Start the run and SIGKILL it inside the build phase."""
        proc = self._launch(resume=False)
        deadline = time.time() + 30
        marker = self.markers / "build.log"
        while time.time() < deadline:
            if marker.is_file() and marker.read_text().strip():
                break
            if proc.poll() is not None:
                self.fail(f"the chain exited before the build phase: rc {proc.returncode}\n"
                          f"{proc.stdout.read() if proc.stdout else ''}")
            time.sleep(0.05)
        else:
            proc.kill()
            self.fail("the chain never reached the build phase")
        os.kill(proc.pid, signal.SIGKILL)
        proc.wait(timeout=10)
        return proc

    def _run(self, resume: bool, timeout: float = 60) -> tuple[int, str]:
        proc = self._launch(resume=resume)
        try:
            out, _ = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            proc.kill()
            out, _ = proc.communicate()
            self.fail(f"the chain hung after the restart\n{out}")
        return proc.returncode, out or ""

    def _record(self) -> runrecord.RunRecord:
        return runrecord.load(runrecord.RecordQuery(
            smidja_id=SID, db_path=str(self.data / "smidja.db"),
            session_dir=str(self.session_dir)))

    def _marks(self, phase: str) -> int:
        path = self.markers / f"{phase}.log"
        return len(path.read_text().splitlines()) if path.is_file() else 0

    def _decide(self, verb: str, note: str = "") -> int:
        return subprocess.run(
            [sys.executable, str(DECIDE), SID, "approve", verb,
             "--config", str(self.config), "--by", "the test", "--note", note],
            cwd=str(self.root), capture_output=True, text=True, timeout=60).returncode

    # ── (a) (b) (c) ────────────────────────────────────────────────────────
    def test_sigkill_restart_resumes_from_the_checkpoint_with_no_client_attached(self) -> None:
        self._kill_mid_build()

        # What a SIGKILL leaves: a session still saying `running` with no process
        # alive. The record must call that interrupted, not running.
        after_kill = self._record()
        self.assertEqual(after_kill.status, "interrupted")
        self.assertEqual(after_kill.checkpoint, "plan",
                         "the last green phase is the checkpoint")
        self.assertEqual(after_kill.resume_at, "build",
                         "the restart re-enters AT the phase that died, never after it")
        self.assertEqual(after_kill.phase("build").status, "interrupted")

        # The trace row is the only source: take the envelope FILE away, so a
        # handed-forward envelope can only have come from the record.
        (self.session_dir / "planner" / "envelope.json").unlink()

        code, out = self._run(resume=True)

        # (d) the run now stands at the approval phase and stops for a decision.
        self.assertEqual(code, 3, f"a waiting run exits 3, not silently 0\n{out}")
        self.assertIn("waiting for a decision", out)
        self.assertEqual(self._marks("approve"), 0,
                         "an approval phase with no decision must not run its block")

        # (a) it re-entered at build — the green phases were not opened again.
        self.assertEqual(self._marks("plan"), 1,
                         "the plan phase's agent work ran once, in the killed process")
        self.assertEqual(self._marks("build"), 2,
                         "build ran in the killed process and again after the restart")

        # (b) the committed envelope was handed forward from the trace.
        handed = json.loads((self.markers / "handed_forward.json").read_text())
        self.assertEqual(handed["summary"], f"the plan for {ASK!r}",
                         "the next phase received the committed envelope, not a new one")

        # (c) nothing green was recomputed: one handoff step, one agent execution.
        record = self._record()
        self.assertEqual(record.status, "waiting")
        self.assertEqual(record.resumed, 1, "the record counts the continuation")
        self.assertEqual([p.name for p in record.phases if p.status == "done"],
                         ["request", "plan", "build"])
        handoffs = [step for step in record.phase("plan").steps if step.kind == "handoff"]
        self.assertEqual(len(handoffs), 1, "the plan phase committed exactly once")
        logs = [step for step in record.phase("request").steps
                if step.kind == "log" and step.label.startswith("input:")]
        self.assertEqual(len(logs), 1, "the ask was logged once — a replay re-records nothing")
        self.assertEqual(record.phase("approve").status, "waiting")
        self.assertEqual(record.phase("approve").approval, "pending")

    # ── (d) the decision is the only door ──────────────────────────────────
    def test_the_run_continues_once_a_person_decides(self) -> None:
        self._kill_mid_build()
        (self.session_dir / "planner" / "envelope.json").unlink()
        self.assertEqual(self._run(resume=True)[0], 3)

        self.assertEqual(self._decide("approve"), 0)
        code, out = self._run(resume=True)

        self.assertEqual(code, 0, f"the approved run completes green\n{out}")
        self.assertEqual(self._marks("approve"), 1, "the block ran once, after the decision")
        record = self._record()
        self.assertEqual(record.status, "completed")
        self.assertEqual([phase.status for phase in record.phases],
                         ["done", "done", "done", "done"])
        self.assertEqual(record.phase("approve").approval, "approved")
        self.assertEqual(record.checkpoint, "approve")
        self.assertEqual(record.resume_at, "", "a finished run has nothing to re-enter")

    def test_a_declined_approval_never_runs_its_block(self) -> None:
        self._kill_mid_build()
        self.assertEqual(self._run(resume=True)[0], 3)

        self.assertEqual(self._decide("decline", note="not this week"), 0)
        code, out = self._run(resume=True)

        self.assertEqual(code, 4, f"a declined run exits 4\n{out}")
        self.assertEqual(self._marks("approve"), 0, "a decline is not a pass")
        record = self._record()
        self.assertEqual(record.status, "declined")
        self.assertEqual(record.phase("approve").status, "failed")
        self.assertIn("declined", record.phase("approve").error)


class RepeatCheckpointTest(unittest.TestCase):
    """A `repeat` phase saves one checkpoint per iteration — and only once each."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        sys.path.insert(0, str(SHIPPED))
        from smidja_modules import runner
        from smidja_modules.data_types import (ConfigDefaults, ObservabilityConfig,
                                              PhaseParams, smidjaConfig)
        from smidja_modules.tracer import Tracer
        self.runner = runner
        self.params = PhaseParams
        self.data = self.root / "smidja_data"
        self.data.mkdir(parents=True, exist_ok=True)
        self.db = self.data / "smidja.db"
        self.session_dir = self.data / "sessions" / "loop0001"
        self.tracer = Tracer(self.db, self.session_dir / "events.jsonl")
        self.tracer.session_start("loop0001", "tester", smidja_name="loop_chain")
        cfg = smidjaConfig(defaults=ConfigDefaults(data_dir=str(self.data)),
                           observability=ObservabilityConfig(db=str(self.db)))
        self.run = runner.Run(cfg=cfg, smidja_id="loop0001", tracer=self.tracer,
                              engineer="tester", repo_root=str(self.root),
                              data_base=str(self.data))

    def tearDown(self) -> None:
        from smidja_modules import git_helper
        git_helper.bind(None)
        self._tmp.cleanup()

    def _loop(self, total: int) -> list[int]:
        ran = []
        with self.run.phase(self.params(name="watch", kind="code", owner="tester",
                                        contract="repeat",
                                        description="Poll the change feed four times")) as ph:
            for iteration in ph.iterations(total):
                ran.append(iteration.index)
                iteration.checkpoint(seen=iteration.index)
        return ran

    def _ask(self) -> None:
        """Proven ground for the loop to stand on — a green phase before it."""
        with self.run.phase(self.params(name="request", kind="engineer", owner="tester",
                                        description="Capture the ask the loop polls about")) as ph:
            ph.log(input="watch the change feed")

    def test_each_iteration_commits_one_checkpoint(self) -> None:
        self.assertEqual(self._loop(4), [1, 2, 3, 4])
        record = runrecord.load(runrecord.RecordQuery(
            smidja_id="loop0001", db_path=str(self.db), session_dir=str(self.session_dir)))
        phase = record.phase("watch")
        self.assertEqual(phase.checkpoints, 4)
        self.assertEqual(phase.progress, {"done": 4, "total": 4})
        self.assertTrue(phase.green)

    def test_a_restart_repeats_only_the_iterations_that_never_committed(self) -> None:
        from smidja_modules import resume
        self._ask()
        # Two iterations commit, then the process is gone mid-loop.
        with self.assertRaises(RuntimeError):
            with self.run.phase(self.params(name="watch", kind="code", owner="tester",
                                            contract="repeat",
                                            description="Poll the change feed four times")) as ph:
                for iteration in ph.iterations(4):
                    iteration.checkpoint(seen=iteration.index)
                    if iteration.index == 2:
                        raise RuntimeError("killed after the second checkpoint")

        record = runrecord.load(runrecord.RecordQuery(
            smidja_id="loop0001", db_path=str(self.db), session_dir=str(self.session_dir)))
        self.assertEqual(record.phase("watch").checkpoints, 2)

        plan = resume.plan(resume.ResumeQuery(
            smidja_id="loop0001", db_path=str(self.db), session_dir=str(self.session_dir)))
        self.assertEqual(plan.from_phase, "watch", "the loop itself is where it re-enters")
        self.run.arm_resume(plan)

        self.assertEqual(self._loop(4), [3, 4], "only the iterations still owed are run")
        record = runrecord.load(runrecord.RecordQuery(
            smidja_id="loop0001", db_path=str(self.db), session_dir=str(self.session_dir)))
        self.assertEqual(record.phase("watch").checkpoints, 4)


if __name__ == "__main__":
    unittest.main()
