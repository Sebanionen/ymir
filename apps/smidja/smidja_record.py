#!/usr/bin/env -S uv run
# /// script
# dependencies = ["pydantic", "python-dotenv", "pyyaml", "rich"]
# ///
"""smidja Record — a run as ONE record: phases · steps · state · where it stopped.

Usage:
    uv run apps/smidja/smidja_record.py <run-id> [--as-steps] [--json] [--config <roster>]

    # the operator's door, from the repo root:
    just record <run-id>             # the run, and the steps of the phases that stopped it
    just record <run-id> --as-steps  # every step of every phase
    just record <run-id> --json      # the same record, whole, for a UI or a test

The record is read by `smidja_modules/runrecord.py` — the ONE reader of the
trace. `resume` reads the same shape, so a resume and a client can never
disagree about what the run was: same phases, same steps, same state, same
place it stopped.

A step exists because the trace recorded an event; a phase's status is derived
from its row, its gates and its decision. Where the record is silent this prints
the absence (`pending`, `unknown`) rather than a guess — a guess dressed as a
fact is what a resume would then trust.

Exit: 0 the run was read · 1 it is waiting for a decision · 2 no such run.
"""

import argparse
import json
import sys

from smidja_modules import runrecord
from smidja_modules.agents import load_config


def main(run_id: str, config: str, as_json: bool, all_steps: bool = False) -> int:
    cfg = load_config(config)
    query = runrecord.RecordQuery(
        smidja_id=run_id, db_path=cfg.observability.db,
        session_dir=f"{cfg.defaults.data_dir}/sessions/{run_id}")
    try:
        record = runrecord.load(query)
    except runrecord.RecordMissing as missing:
        print(f"refused: no such run — {missing}")
        return 2

    if as_json:
        print(json.dumps(record.model_dump(mode="json"), indent=2))
        return _exit_code(record)

    print("run[1]{field,value}:")
    for field, value in record.describe():
        print(f'  "{field}","{_quote(value)}"')

    print(f"phases[{len(record.phases)}]{{seq,name,lane,contract,owner,status,"
          f"checkpoints,approval}}:")
    for phase in record.phases:
        count = (f"{phase.progress['done']}/{phase.progress['total']}"
                 if phase.progress else str(phase.checkpoints))
        print(f'  "{phase.seq}","{_quote(phase.name)}","{phase.lane}","{phase.contract}",'
              f'"{_quote(phase.owner)}","{phase.status}","{count}","{phase.approval or "-"}"')

    rows, elided = _steps_to_print(record, all_steps)
    if rows:
        print(f"steps[{len(rows)}]{{phase,iteration,kind,label,status,at}}:")
        for phase_name, step in rows:
            print(f'  "{_quote(phase_name)}","{step.iteration or "-"}","{step.kind}",'
                  f'"{_quote(step.label)}","{step.status}","{step.at}"')
    if elided["finished"] or elided["tail"]:
        print(f"# {elided['finished']} steps of finished phases and {elided['tail']} earlier "
              f"steps of the phases that stopped the run are not shown — "
              f"pass --as-steps for all of them")
    return _exit_code(record)


def _steps_to_print(record, all_steps: bool) -> tuple[list, dict]:
    """The steps a person reads: where the run stopped, not the whole transcript.

    A real failed agent phase carries 167 events, and a finished one is not why the
    door is open. So the default shows the phases that did NOT finish, most recent
    TAIL_STEPS of each; `--as-steps` shows everything. What is elided is counted and
    named, never silently dropped.
    """
    tail = 20
    phases = record.phases if all_steps else [phase for phase in record.phases
                                              if phase.status != "done"]
    elided = {"finished": sum(len(phase.steps) for phase in record.phases
                              if phase.status == "done") if not all_steps else 0,
              "tail": 0}
    rows = []
    for phase in phases:
        steps = phase.steps
        if not all_steps and len(steps) > tail:
            elided["tail"] += len(steps) - tail
            steps = steps[-tail:]
        rows.extend((phase.name, step) for step in steps)
    return rows, elided


def _exit_code(record: runrecord.RunRecord) -> int:
    """A waiting run is not an error — it is a question somebody owes an answer to."""
    return 1 if record.status == "waiting" else 0


def _quote(value: str) -> str:
    return " ".join(str(value).split()).replace('"', "'")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("run_id", help="the smidja_id of the run to read")
    parser.add_argument("--config", default="smidja/smidja_smidja_config/smidja.config.yaml")
    parser.add_argument("--json", action="store_true",
                        help="print the whole record as JSON instead of tables")
    parser.add_argument("--as-steps", action="store_true",
                        help="print every step of every phase, not only the ones that stopped it")
    args = parser.parse_args()
    sys.exit(main(args.run_id, args.config, args.json, args.as_steps))
