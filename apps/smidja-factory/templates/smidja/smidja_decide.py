#!/usr/bin/env -S uv run
# /// script
# dependencies = ["pydantic", "python-dotenv", "pyyaml", "rich"]
# ///
"""smidja Decide — record a person's decision on an `approval` phase.

Usage:
    uv run apps/smidja/smidja_decide.py <run-id> <phase> approve|decline [--note "..."] [--by "name"]

    # the operator's door, from the repo root:
    just decide <run-id> <phase> approve

An `approval` phase is the one phase that does not run on its own: its block is
never entered until a decision is on the run's record. No decision is NOT an
approval — a restart re-enters the phase and waits again, which is the whole
point of the contract (`smidja_modules/runrecord.py`, `runner._await_decision`).

The decision is written to the trace (`decisions`), not to a side file, so the
record, the resume and any client read the same answer. Decisions append: the
latest on a phase wins, and the earlier ones stay as the history of who asked
twice.

Exit: 0 recorded · 2 refused (no such run, no such phase, or not an approval phase).
"""

import argparse
import sys

from smidja_modules import runrecord
from smidja_modules.agents import load_config
from smidja_modules.data_types import DecisionRecord
from smidja_modules.tracer import Tracer

VERBS = {"approve": "approved", "decline": "declined", "cancel": "cancelled"}


def main(run_id: str, phase_name: str, verb: str, config: str,
         note: str, by: str) -> int:
    cfg = load_config(config)
    query = runrecord.RecordQuery(
        smidja_id=run_id, db_path=cfg.observability.db,
        session_dir=f"{cfg.defaults.data_dir}/sessions/{run_id}")
    try:
        record = runrecord.load(query)
    except runrecord.RecordMissing as missing:
        print(f"refused: no such run — {missing}")
        return 2

    phase = record.phase(phase_name)
    if phase is None:
        recorded = ", ".join(p.name for p in record.phases) or "(none)"
        print(f"refused: no such phase — this run recorded: {recorded}")
        return 2
    if phase.contract != "approval":
        print(f"refused: phase {phase_name!r} has contract {phase.contract!r} — "
              f"only an approval phase takes a decision. Pass `contract: approval` "
              f"on the phase to make one.")
        return 2

    decision = VERBS[verb]
    tracer = Tracer(cfg.observability.db,
                    f"{cfg.defaults.data_dir}/sessions/{run_id}/events.jsonl")
    try:
        tracer.decision_record(DecisionRecord(smidja_id=run_id, phase=phase_name,
                                              decision=decision, by=by, note=note))
    finally:
        tracer.conn.close()

    print("decision[1]{field,value}:")
    print(f'  "run","{run_id}"')
    print(f'  "phase","{phase_name}"')
    print(f'  "decision","{decision}"')
    print(f'  "by","{by or "-"}"')
    print(f'  "note","{note or "-"}"')
    print(f'  "phase_status","{phase.status}"')
    if decision == "approved" and phase.status == "waiting":
        print(f'  "next","just resume {run_id}   # continue at the approved phase"')
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("run_id", help="the smidja_id of the run")
    parser.add_argument("phase", help="the approval phase's name")
    parser.add_argument("verb", choices=sorted(VERBS), help="what is being decided")
    parser.add_argument("--config", default="smidja/smidja_smidja_config/smidja.config.yaml")
    parser.add_argument("--note", default="", help="why, when a decline needs a reason")
    parser.add_argument("--by", default="", help="who decided; defaults to the engineer")
    args = parser.parse_args()
    sys.exit(main(args.run_id, args.phase, args.verb, args.config, args.note, args.by))
