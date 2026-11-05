"""The smithy's two doors: the trace reader and per-phase context telemetry.

Three laws are asserted here, and each one exists because the house already paid
for its absence:

  1. a trace prints the columns it promised, from the records that exist;
  2. a phase that ends at or above the force threshold is `context-pressed` —
     never `success`, not in the trace, not in the session row, not in the
     banner, not in the exit code;
  3. a run with no usage rows does not crash and does not invent a green.

Run:  python3 -m unittest tests.test_smidja_trace -v
"""

from __future__ import annotations

import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SMIDJA = ROOT / "apps" / "smidja"
sys.path.insert(0, str(SMIDJA))

# The smithy's own modules need pydantic (+ rich for the console). On a bare
# system python3 they are absent, and importing them here would make the whole
# repo's `python3 -m unittest` fail on a missing dependency rather than an
# assertion. So a missing dependency is a CLEAN SKIP with its reason (Rule 25);
# the full proof runs where the smithy runs:
#
#   uv run --with pydantic --with pyyaml --with rich --with python-dotenv \
#     python -m unittest tests.test_smidja_trace -v
MISSING = ""
try:
    import smidja_trace as trace_verb                        # noqa: E402
    from smidja_modules import context as tel                # noqa: E402
    from smidja_modules.data_types import (ConfigDefaults, ObservabilityConfig,   # noqa: E402
                                           Phase, PhaseParams, smidjaConfig)
    from smidja_modules.runner import Run                    # noqa: E402
    from smidja_modules.tracer import SCHEMA, Tracer         # noqa: E402
except ImportError as exc:                                   # pragma: no cover
    MISSING = (f"the smithy's python deps are not importable here ({exc}); run "
               f"under `uv run --with pydantic --with rich --with pyyaml`")
    trace_verb = tel = Run = Tracer = SCHEMA = None          # type: ignore[assignment]
    ConfigDefaults = ObservabilityConfig = Phase = PhaseParams = smidjaConfig = None  # type: ignore[assignment]

needs_smithy = unittest.skipIf(bool(MISSING), MISSING or "")

HEADER = ("trace[{n}]{{phase,owner,model,thinking,tools,tokens,"
          "window,percent,verdict}}:")


def make_db(path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(path)
    conn.executescript(SCHEMA)
    conn.commit()
    return conn


def seed_run(conn: sqlite3.Connection, run_id: str, *, usage: int | None,
             model: str = "llama-swap/qwen3.6-35b-a3b", window: int = 262144,
             with_start: bool = True, thinking: str = "high") -> None:
    """One engineer phase + one agent phase, with the records a real run writes."""
    conn.execute("INSERT INTO sessions (smidja_id, status, engineer, started_at)"
                 " VALUES (?,?,?,?)", (run_id, "running", "zerwiz", "2026-11-05T10:00:00Z"))
    for seq, (name, kind, owner) in enumerate(
            (("request", "engineer", "zerwiz"), ("build", "agent", "sindri")), start=1):
        conn.execute(
            "INSERT INTO phases (phase_id, smidja_id, seq, name, kind, owner, description,"
            " status, attempt, retries, started_at, ended_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
            (f"{run_id}_{seq:02d}_{name}", run_id, seq, name, kind, owner, "seeded",
             "success", 0, 0, "2026-11-05T10:00:00Z", "2026-11-05T10:00:01Z"))
    build = f"{run_id}_02_build"
    if with_start:
        conn.execute(
            "INSERT INTO events (event_id, smidja_id, phase_id, type, name, payload_json,"
            " started_at) VALUES (?,?,?,?,?,?,?)",
            (f"{run_id}-start", run_id, build, "agent_start", "sindri",
             json.dumps({"model": model, "thinking": thinking,
                         "tools": ["bash", "write", "read"]}),
             "2026-11-05T10:00:01Z"))
    if usage is not None:
        conn.execute(
            "INSERT INTO events (event_id, smidja_id, phase_id, type, name, payload_json,"
            " tokens, started_at) VALUES (?,?,?,?,?,?,?,?)",
            (f"{run_id}-end", run_id, build, "agent_end", "sindri",
             json.dumps({"context": tel.phase_context(
                 model=model, thinking=thinking, used=usage, window=window,
                 input_tokens=usage - 1000, cache_read=900, output=100,
                 finish="stop")}),
             usage, "2026-11-05T10:05:00Z"))
    conn.commit()


@needs_smithy
class VerdictVocabularyTest(unittest.TestCase):
    """One vocabulary, and it is the seat door's own."""

    def test_the_four_words_are_the_seat_doors_words(self):
        door = ROOT / "bin" / "seat" / "context.sh"
        if not door.is_file():
            self.skipTest("bin/seat/context.sh is not on this tree — clean skip (Rule 25)")
        body = door.read_text()
        for word in (tel.VERDICT_ROOM, tel.VERDICT_AUTO, tel.VERDICT_NEAR,
                     "TRUNCATED"):
            self.assertIn(word, body,
                          f"{word!r} has drifted from bin/seat/context.sh")

    def test_thresholds_are_a_half_and_three_quarters(self):
        window = 100_000
        self.assertEqual(tel.auto_at(window), 50_000)
        self.assertEqual(tel.force_at(window), 75_000)

    def test_verdict_ladder(self):
        window = 100_000
        self.assertEqual(tel.verdict(10_000, window), tel.VERDICT_ROOM)
        self.assertEqual(tel.verdict(60_000, window), tel.VERDICT_AUTO)
        self.assertEqual(tel.verdict(80_000, window), tel.VERDICT_NEAR)
        self.assertEqual(tel.verdict(80_000, window, "length"), tel.VERDICT_TRUNCATED)
        self.assertEqual(tel.verdict(10, 0), tel.VERDICT_UNKNOWN)
        self.assertEqual(tel.verdict(0, window), tel.VERDICT_NO_USAGE)

    def test_an_unknown_window_is_never_green(self):
        self.assertNotEqual(tel.verdict(500_000, 0), tel.VERDICT_ROOM)
        self.assertFalse(tel.pressed(500_000, 0))


@needs_smithy
class TraceColumnsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.db = self.base / "smidja.db"
        self.conn = make_db(self.db)

    def tearDown(self):
        self.conn.close()
        self.tmp.cleanup()

    def test_trace_prints_the_expected_columns(self):
        seed_run(self.conn, "run0001", usage=41_203)
        trace = trace_verb.build_trace(self.db, "run0001", self.base)
        rendered = trace_verb.render(trace)
        lines = rendered.splitlines()

        self.assertEqual(lines[0], HEADER.format(n=2))
        self.assertEqual(len(lines), 3, rendered)

        # Every promised column is present and populated from a real record.
        build = lines[2]
        self.assertIn('"build","sindri"', build)
        self.assertIn('"llama-swap/qwen3.6-35b-a3b"', build)
        self.assertIn('"high"', build)
        self.assertIn('"bash,write,read"', build)
        self.assertIn('"41203","262144","15.7"', build)
        self.assertIn('"room to work"', build)

        # An engineer phase records no usage; it says so instead of a zero-green.
        self.assertIn('"request","zerwiz"', lines[1])
        self.assertIn(f'"{tel.VERDICT_NO_USAGE}"', lines[1])

    def test_json_mode_carries_the_components(self):
        seed_run(self.conn, "run0002", usage=41_203)
        payload = json.loads(trace_verb.render_json(
            trace_verb.build_trace(self.db, "run0002", self.base)))
        build = [p for p in payload["phases"] if p["phase"] == "build"][0]
        for key in ("input", "cache_read", "output", "window", "percent",
                    "model", "thinking"):
            self.assertIn(key, build)
        self.assertEqual(build["input"], 41_203 - 1_000)
        self.assertEqual(build["cache_read"], 900)
        self.assertEqual(build["output"], 100)
        self.assertEqual(build["window"], 262_144)
        self.assertEqual(build["percent"], 15.7)
        self.assertEqual(build["thinking"], "high")
        self.assertEqual(build["model"], "llama-swap/qwen3.6-35b-a3b")
        self.assertFalse(payload["context_pressed"])

    def test_the_receipt_alone_names_the_model_and_thinking(self):
        """The phase's own record answers both, even with no `agent_start`.

        The model and thinking level live on the `agent_end` receipt precisely so
        the trace never depends on the start event surviving in the ledger.
        """
        seed_run(self.conn, "run0004", usage=41_203, with_start=False,
                 model="opencode-go/deepseek-v4.1-flash", thinking="xhigh")
        trace = trace_verb.build_trace(self.db, "run0004", self.base)
        build = trace["rows"][1]
        self.assertEqual(build["model"], "opencode-go/deepseek-v4.1-flash")
        self.assertEqual(build["thinking"], "xhigh")
        rendered = trace_verb.render(trace)
        self.assertIn('"opencode-go/deepseek-v4.1-flash","xhigh"', rendered)

    def test_run_with_no_usage_rows_does_not_crash(self):
        seed_run(self.conn, "run0003", usage=None)
        trace = trace_verb.build_trace(self.db, "run0003", self.base)
        rendered = trace_verb.render(trace)
        self.assertIn(HEADER.format(n=2), rendered)
        build = trace["rows"][1]
        self.assertEqual(build["tokens"], 0)
        self.assertIn(build["verdict"], (tel.VERDICT_NO_USAGE, tel.VERDICT_UNKNOWN))
        # The empty cells are the honest mark, never a fabricated zero window.
        self.assertIn('"—","—","—"', rendered)

    def test_an_unknown_run_names_the_miss(self):
        with self.assertRaises(LookupError):
            trace_verb.build_trace(self.db, "nope", self.base)


@needs_smithy
class ContextPressedTest(unittest.TestCase):
    """Over the force threshold is not green — anywhere."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.db = self.base / "smidja.db"
        self.conn = make_db(self.db)

    def tearDown(self):
        self.conn.close()
        self.tmp.cleanup()

    def test_a_phase_over_the_force_threshold_reports_context_pressed(self):
        # 80% of a 100k window: past 75%, so pressed.
        seed_run(self.conn, "run0010", usage=80_000, window=100_000)
        trace = trace_verb.build_trace(self.db, "run0010", self.base)
        build = trace["rows"][1]
        self.assertTrue(build["pressed"])
        self.assertEqual(build["verdict"], tel.VERDICT_NEAR)
        self.assertEqual(build["percent"], 80.0)
        self.assertIn('"near the window — compact now"', trace_verb.render(trace))

    def _run(self, run_id: str, used: int, window: int) -> Run:
        cfg = smidjaConfig(
            defaults=ConfigDefaults(data_dir=str(self.base)),
            observability=ObservabilityConfig(db=str(self.db)),
            agents=[])
        tracer = Tracer(self.db, self.base / "events.jsonl")
        tracer.session_start(run_id, "zerwiz")
        run = Run(cfg=cfg, smidja_id=run_id, tracer=tracer, engineer="zerwiz",
                  repo_root=self.base, data_base=self.base)
        phase = Phase(phase_id=f"{run_id}_01_build", smidja_id=run_id, seq=1,
                      params=PhaseParams(name="build", kind="agent", owner="sindri",
                                         description="Implement the request"),
                      status="success")
        run.phases.append(phase)
        run.context_by_phase[phase.phase_id] = tel.phase_context(
            model="llama-swap/qwen3.6-35b-a3b", used=used, window=window, finish="stop")
        return run

    def test_finish_settles_pressed_in_the_db_not_success(self):
        run = self._run("run0011", used=80_000, window=100_000)
        run.context_by_phase[f"run0011_01_build"]["pressed"] = True
        run.phases[0].status = "context-pressed"
        code = run.finish(accepted=True)
        self.assertEqual(code, 1, "a pressed run must not exit 0")
        row = self.conn.execute(
            "SELECT status FROM sessions WHERE smidja_id='run0011'").fetchone()
        self.assertEqual(row[0], "context-pressed")

    def test_finish_keeps_a_clean_run_green(self):
        run = self._run("run0012", used=10_000, window=100_000)
        code = run.finish(accepted=True)
        self.assertEqual(code, 0)
        row = self.conn.execute(
            "SELECT status FROM sessions WHERE smidja_id='run0012'").fetchone()
        self.assertEqual(row[0], "success")


if __name__ == "__main__":
    unittest.main()
