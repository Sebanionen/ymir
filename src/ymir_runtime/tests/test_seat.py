"""seat.py — the whole errand, end to end, in a temp home and a real repo."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from ymir_runtime import heartbeat, paths
from ymir_runtime.seat import _worth_a_smith, seat as seat_verb, task_section
from ymir_runtime.errors import EngineError, EngineRefusal
from ymir_runtime.seat import Errand
from ymir_runtime.tests.support import Recorder, completed, engine_env, make_repo, tmux_responses, write_brief


def available(name: str) -> str:
    return f"/usr/bin/{name}"


class SeatTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.repo = make_repo(self.tmp / "repo")
        self.env = engine_env(self.tmp, repo=self.repo)
        self.state = Path(self.env["YMIR_STATE_DIR"])
        write_brief(
            self.tmp,
            "errand-one",
            "# Task\n\nForge the thing: write the artefact and report it.\n\n"
            "Isolation: herdr — the ordinary road\n\nDelivery contract: mode=direct-PR\n",
        )

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _errand(self, **overrides) -> Errand:
        base = dict(
            task_id="errand-one",
            project_dir=str(self.repo),
            harness="pi",
            model="llama-swap/qwen3.6-35b-a3b@iq3_s",
            backend="tmux",
        )
        base.update(overrides)
        return Errand(**base)

    def test_seat_writes_the_whole_record(self) -> None:
        runner = Recorder(responses=tmux_responses())
        seat_id = seat_verb(self._errand(), runner=runner, env=self.env, probe=available)
        self.assertEqual(seat_id, "errand-one")

        meta = heartbeat.read_meta(self.state, seat_id)
        self.assertEqual(meta["id"], "errand-one")
        self.assertEqual(meta["engine"], "ymir_runtime/phase1")
        self.assertEqual(meta["kind"], "ship")
        self.assertEqual(meta["mode"], "direct-PR")
        self.assertEqual(meta["harness"], "pi")
        self.assertEqual(meta["backend"], "tmux")
        self.assertEqual(meta["window"], "@7")
        self.assertEqual(meta["isolation"], "off")
        self.assertEqual(meta["isolation_declared"], "herdr")
        self.assertEqual(meta["worktree"], str(self.repo / ".yggdrasil" / "errand-one"))
        self.assertEqual(meta["worktree_created"], "yes")
        self.assertTrue(meta["launched"].isdigit())

        self.assertEqual(
            heartbeat.last_line(self.state, seat_id),
            f"working: launched {meta['launch_iso']} (heartbeat baseline)",
        )

    def test_seat_creates_the_worktree_and_the_launch_script(self) -> None:
        runner = Recorder(responses=tmux_responses())
        seat_verb(self._errand(), runner=runner, env=self.env, probe=available)
        tree = self.repo / ".yggdrasil" / "errand-one"
        self.assertTrue((tree / "README.md").is_file())
        script = self.state / "errand-one.launch.sh"
        self.assertTrue(script.is_file())
        body = script.read_text(encoding="utf-8")
        self.assertIn(f"cd '{tree}'", body)
        # The line is the GENERATOR's: discovery off, every extension named, the
        # worktree passed through (plan 190 §4.1).
        self.assertIn("exec pi --model 'llama-swap/qwen3.6-35b-a3b@iq3_s' -ne -e", body)
        self.assertIn("prompt.md", body)

    def test_an_unproven_seat_is_a_failure_not_a_claim(self) -> None:
        """A seat the agent list does not show is refused, and the record says so."""
        responses = tmux_responses()
        responses["seat-prove.sh"] = completed(1, "", "seat-prove: no agent in pane @7 after 1s\n")
        runner = Recorder(responses=responses)
        with self.assertRaises(EngineError):
            seat_verb(self._errand(), runner=runner, env=self.env, probe=available)
        meta = heartbeat.read_meta(self.state, "errand-one")
        self.assertEqual(meta["seat"], "no")
        self.assertIn("NO agent", heartbeat.last_line(self.state, "errand-one"))

    def test_a_seat_proved_in_another_pane_records_that_pane(self) -> None:
        """The record follows the AGENT, not the pane the spawner chose."""
        responses = tmux_responses()
        responses["seat-prove.sh"] = completed(
            0,
            "wQ:p9\tworking\n",
            "seat-prove: the agent stands in wQ:p9, not in the pane @7 this spawn chose — record the printed pane\n",
        )
        runner = Recorder(responses=responses)
        seat_verb(self._errand(), runner=runner, env=self.env, probe=available)
        meta = heartbeat.read_meta(self.state, "errand-one")
        self.assertEqual(meta["seat"], "yes")
        self.assertEqual(meta["window"], "wQ:p9")
        self.assertIn("wQ:p9", meta.get("seat_note", ""))

    def test_seat_writes_the_prompt_from_the_brief(self) -> None:
        runner = Recorder(responses=tmux_responses())
        seat_verb(self._errand(), runner=runner, env=self.env, probe=available)
        prompt = Path(self.env["YMIR_DATA_DIR"]) / "errand-one" / "prompt.md"
        self.assertIn("Forge the thing", prompt.read_text(encoding="utf-8"))

    def test_the_seat_gets_its_own_machine_state_dir(self) -> None:
        runner = Recorder(responses=tmux_responses())
        seat_verb(self._errand(), runner=runner, env=self.env, probe=available)
        typed = runner.saw("tmux send-keys -t @7 -l")[0][-1]
        expected = str(Path(self.env["XDG_STATE_HOME"]) / "ymir" / "seats" / "errand-one")
        self.assertIn(f"BROKK_STATE_OVERRIDE={expected!r}", typed)

    def test_a_second_seat_of_the_same_id_is_refused(self) -> None:
        seat_verb(self._errand(), runner=Recorder(responses=tmux_responses()), env=self.env, probe=available)
        with self.assertRaises(EngineRefusal) as caught:
            seat_verb(self._errand(), runner=Recorder(responses=tmux_responses()), env=self.env, probe=available)
        self.assertIn("already stands", str(caught.exception))

    def test_an_unsafe_task_id_is_refused(self) -> None:
        with self.assertRaises(EngineRefusal):
            seat_verb(
                self._errand(task_id="../escape"), runner=Recorder(), env=self.env, probe=available
            )

    def test_a_utgard_declaration_is_refused_never_downgraded(self) -> None:
        write_brief(self.tmp, "errand-two", "# Untrusted\nIsolation: utgard — untrusted input\n")
        with self.assertRaises(EngineRefusal) as caught:
            seat_verb(
                self._errand(task_id="errand-two"),
                runner=Recorder(),
                env=self.env,
                probe=lambda name: "",
            )
        self.assertIn("neither docker nor podman", str(caught.exception))

    def test_an_unverified_harness_is_refused(self) -> None:
        with self.assertRaises(EngineRefusal) as caught:
            seat_verb(
                self._errand(harness="weird-agent", model=""),
                runner=Recorder(),
                env=self.env,
                probe=available,
            )
        self.assertIn("not verified for direct launch", str(caught.exception))

    def test_a_raw_launch_command_is_accepted_as_the_escape_hatch(self) -> None:
        runner = Recorder(responses=tmux_responses())
        seat_id = seat_verb(
            self._errand(harness="bash -lc 'echo proof'", model="", backend="tmux"),
            runner=runner,
            env=self.env,
            probe=available,
        )
        meta = heartbeat.read_meta(self.state, seat_id)
        self.assertEqual(meta["raw_launch"], "bash -lc 'echo proof'")
        self.assertIn("escape hatch", meta["harness_provenance"])

    def test_a_missing_project_is_refused(self) -> None:
        with self.assertRaises(EngineRefusal):
            seat_verb(
                self._errand(project_dir=str(self.tmp / "nowhere")),
                runner=Recorder(),
                env=self.env,
                probe=available,
            )

    def test_a_local_model_lock_wraps_the_launch(self) -> None:
        runner = Recorder(responses=tmux_responses())
        seat_verb(self._errand(lock="/bin/model/local-model-lock.sh"), runner=runner, env=self.env, probe=available)
        body = (self.state / "errand-one.launch.sh").read_text(encoding="utf-8")
        self.assertIn("exec '/bin/model/local-model-lock.sh' bash -c '", body)
        meta = heartbeat.read_meta(self.state, "errand-one")
        self.assertEqual(meta["locked"], "yes")

    def test_coerce_accepts_a_mapping_and_keeps_unknown_keys(self) -> None:
        errand = Errand.coerce({"task_id": "x", "project_dir": "/p", "spawn_source": "test"})
        self.assertEqual(errand.task_id, "x")
        self.assertEqual(errand.extra, {"spawn_source": "test"})


class WorthTest(unittest.TestCase):
    """The first law, delegated — never a second copy of the heuristic."""

    def _roots(self, tmp: Path) -> paths.Roots:
        return paths.resolve(engine_env(tmp, repo=tmp / "repo"))

    def test_task_section_reads_the_briefs_own_errand(self) -> None:
        brief = "# Task\n\nWrite the thing well.\n\n# Setup\nignored\n"
        self.assertEqual(task_section(brief), "Write the thing well.")

    def test_no_task_section_is_no_errand(self) -> None:
        self.assertEqual(task_section("# Notes\n\nnothing\n"), "")

    def test_an_unfilled_task_placeholder_is_refused(self) -> None:
        verdict, why = _worth_a_smith(self._roots(self.tmp), "# Task\n\n{TASK}\n", Recorder())
        self.assertEqual(verdict, "no")
        self.assertIn("unfilled", why)

    def test_a_brief_with_no_task_section_is_refused(self) -> None:
        verdict, why = _worth_a_smith(self._roots(self.tmp), "# Notes\n", Recorder())
        self.assertEqual(verdict, "no")
        self.assertIn("no # Task section", why)

    def test_with_no_door_on_this_machine_the_errand_is_dispatched(self) -> None:
        verdict, why = _worth_a_smith(self._roots(self.tmp), "# Task\n\nWrite a thing.\n", Recorder())
        self.assertEqual(verdict, "yes")
        self.assertIn("no worth-a-smith door", why)

    def test_the_verdict_comes_from_the_door_that_owns_the_heuristic(self) -> None:
        roots = self._roots(self.tmp)
        (roots.root / "bin").mkdir(parents=True, exist_ok=True)
        (roots.root / "bin" / "herdr-run.sh").write_text("#!/usr/bin/env bash\n", encoding="utf-8")
        runner = Recorder(
            responses={
                "herdr-run.sh worth-a-smith": completed(
                    0, 'worth[1]{verdict,why,words}:\n  "no","a question — answer it in hand",5\n', ""
                )
            }
        )
        verdict, why = _worth_a_smith(roots, "# Task\n\nWhat is this?\n", runner)
        self.assertEqual(verdict, "no")
        self.assertEqual(why, "a question — answer it in hand")

    def test_an_errand_that_is_not_worth_a_smith_is_refused(self) -> None:
        with self.assertRaises(EngineRefusal) as caught:
            seat_verb(
                self._errand("brief-tiny"),
                runner=Recorder(responses=tmux_responses()),
                env=self.env,
                probe=lambda name: "",
            )
        self.assertIn("no # Task section", str(caught.exception))

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.repo = make_repo(self.tmp / "repo")
        self.env = engine_env(self.tmp, repo=self.repo)
        write_brief(self.tmp, "brief-tiny", "# Notes\n\nnothing worth a smith\n")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _errand(self, task_id: str) -> Errand:
        return Errand(
            task_id=task_id,
            project_dir=str(self.repo),
            harness="pi",
            model="llama-swap/qwen3.6-35b-a3b@iq3_s",
            backend="tmux",
        )


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
