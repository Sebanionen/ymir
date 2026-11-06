#!/usr/bin/env -S uv run
# /// script
# dependencies = ["pydantic", "python-dotenv", "pyyaml", "rich"]
# ///
"""recovery_chain.py — the chain `tests/test_recovery.py` kills with SIGKILL.

Four phases, each of which writes a MARKER LINE before it does anything else, so
the test can count executions instead of trusting a status word:

  request   engineer   logs the ask (the log event is the marker that matters)
  plan      agent      commits an envelope (the stand-in model below)
  build     code       writes build.log, then HANGS on its first attempt
  approve   approval   writes approve.log — only if a person decided first

The hang is deliberate: the test waits for `build.log` to appear and then
SIGKILLs the runner mid-phase, which is the one thing a phase cannot clean up
after. On the restart the same phase is entered again and runs to its end,
because `build.log` already holds one line.

Why `if run.replaying` in the plan phase: a real chain's work is `ph.call()`,
which the resume machinery answers from the record. The stand-in model is this
fixture's substitute for an actual agent call, so it must not be invoked on the
replay path — and `ph.call()` returning the committed envelope *is* the resumed
code path. The marker line then proves the stand-in did not run twice.

    python3 recovery_chain.py "<ask>" --config <roster.yaml> --smidja-id <id> \
        --markers <dir>
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path

SHIPPED = Path(__file__).resolve().parents[2] / "templates" / "smidja"
sys.path.insert(0, str(SHIPPED))

from smidja_modules import agents, session, utils                    # noqa: E402
from smidja_modules.data_types import (AgentCall, EventRecord, GenericOutput,  # noqa: E402
                                      PhaseParams)


def mark(markers: Path, phase: str) -> int:
    """One line per time this phase's body actually ran; the count is returned."""
    path = markers / f"{phase}.log"
    with path.open("a") as fh:
        fh.write(f"{os.getpid()}\n")
    return len(path.read_text().splitlines())


def stand_in_agent(run, ph, markers: Path, phase: str, request: str) -> GenericOutput:
    """The one 'model' in this fixture: it commits an envelope as an agent would.

    The rows it writes are the same rows `agents._persist_envelope` writes — the
    trace row, the file beside the session, the handoff event — so a resume reads
    exactly what a real agent phase would have left behind.
    """
    mark(markers, phase)
    envelope = GenericOutput(status="success", summary=f"the plan for {request!r}",
                             artifacts=[str(markers / "plan.md")])
    run.tracer.envelope_row(ph.phase, "planner", "GenericOutput",
                            envelope.model_dump_json(indent=2), valid=True, attempt=1)
    agent_dir = run.session_dir / "planner"
    agent_dir.mkdir(parents=True, exist_ok=True)
    (agent_dir / "envelope.json").write_text(json.dumps(
        {"agent_name": "planner", "purpose": "commit a plan", "output_type": "GenericOutput",
         "attempt": 1, **envelope.model_dump()}, indent=2))
    run.save_agent_map("planner", {"session_id": "smidja-fixture-planner-0001",
                                   "model": "test/fixture-model", "coding_agent": "pi"})
    run.tracer.event(EventRecord(smidja_id=run.smidja_id, phase_id=ph.phase.phase_id,
                                 type="handoff", name="planner",
                                 payload={"artifacts": envelope.artifacts,
                                          "summary": envelope.summary}))
    return envelope


def main(request: str, config: str, smidja_id: str, markers_dir: str) -> int:
    cfg = agents.load_config(config)
    run = session.ensure(cfg, smidja_id)
    markers = Path(markers_dir)
    markers.mkdir(parents=True, exist_ok=True)

    with run.phase(PhaseParams(name="request", kind="engineer", owner=run.engineer,
                               description="Capture the ask this fixture run works from")) as ph:
        # No marker here on purpose: a replayed phase's BLOCK still executes, and
        # only the machinery's own doors (`ph.call`, `ph.log`, `checkpoint`) are
        # answered from the record. So the marker goes where the work is (the
        # stand-in agent), and this phase is proved by its log event not repeating.
        ph.log(input=request)

    with run.phase(PhaseParams(name="plan", kind="agent", owner="planner",
                               description="Commit the plan the build phase inherits")) as ph:
        if run.replaying:
            plan = ph.call(AgentCall(output_type=GenericOutput, prompt=request))
        else:
            plan = stand_in_agent(run, ph, markers, "plan", request)

    with run.phase(PhaseParams(name="build", kind="code", owner=run.engineer,
                               description="Do the work the plan describes, hanging on "
                                           "its first attempt so the test can kill it")) as ph:
        (markers / "handed_forward.json").write_text(json.dumps(plan.model_dump(), indent=2))
        (markers / "session_ids.json").write_text(json.dumps(
            run.agent_map if isinstance(run.agent_map, dict) else {}, indent=2))
        ph.log(summary=plan.summary, source="the envelope handed forward")
        if mark(markers, "build") == 1:
            time.sleep(120)          # killed here — the sleep never returns

    with run.phase(PhaseParams(name="approve", kind="code", owner=run.engineer,
                               contract="approval",
                               description="Wait for a person's decision before the run "
                                           "is allowed to close")) as ph:
        mark(markers, "approve")
        ph.log(approved_by="a person", decision="approved")

    return run.finish(accepted=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("request", help="inline text or a path to a prompt file")
    parser.add_argument("--config", required=True)
    parser.add_argument("--smidja-id", required=True)
    parser.add_argument("--markers", required=True, help="where the marker lines land")
    args = parser.parse_args()
    sys.exit(main(utils.resolve_prompt(args.request), args.config,
                  args.smidja_id, args.markers))
