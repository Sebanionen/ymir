"""Session lifecycle: pin-or-create an smidja_id, build the Run object.

`ensure(cfg, smidja_id)` joins the session if it exists or creates it under
exactly that id (pinned ids for repeatable runs); omitted, a fresh id is
minted and printed so the next smidja can pick it up.
"""

from __future__ import annotations

import os
import signal
import sys
from pathlib import Path

from .data_types import smidjaConfig
from .runner import Run
from .tracer import Tracer
from .utils import engineer_name, new_id


def _finalize_when_killed(run: Run) -> None:
    """A killed run still closes its own trace.

    Python's default SIGTERM handling exits without unwinding, so `just kill`
    (or any `kill <pid>`) would leave the session reading `running` forever and
    its process rows open — the trace would claim work is in flight that is
    already dead. Turning the signal into SystemExit both finalizes here and
    lets the phase context manager record the phase as failed on the way out.
    """
    def handler(signum, _frame):
        run.tracer.session_finish(run.smidja_id, ok=False)   # also closes process rows
        raise SystemExit(128 + signum)

    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, handler)


def ensure(cfg: smidjaConfig, smidja_id: str | None = None) -> Run:
    smidja_id = smidja_id or new_id(8)
    tracer = Tracer(cfg.observability.db,
                    f"{cfg.defaults.data_dir}/sessions/{smidja_id}/events.jsonl")
    run = Run(cfg=cfg, smidja_id=smidja_id, tracer=tracer, engineer=engineer_name())
    # Resume is decided BEFORE this process writes anything: the plan reads the
    # record exactly as the last run left it (its status included), and a refusal
    # costs nothing because no row has been touched yet.
    plan = _resume_plan(run, cfg)
    tracer.session_start(smidja_id, run.engineer, smidja_name=Path(sys.argv[0]).stem)
    # This process is the run. Record it before any phase opens, so a run that
    # hangs in its first agent call is still killable by smidja_id.
    tracer.process_start(smidja_id, "smidja", "", os.getpid(),
                         " ".join([Path(sys.argv[0]).name, *sys.argv[1:]]))
    _finalize_when_killed(run)
    run.console.session_started(smidja_id, run.engineer)
    if plan is not None:
        run.arm_resume(plan)
    return run


def _resume_plan(run: Run, cfg: smidjaConfig):
    """The plan when `smidja resume` launched this process, else None.

    `SMIDJA_RESUME_FROM` is the whole signal: **present** means this process is
    re-entering an existing run, and its value names the phase to re-enter at
    (empty = the next phase the chain opens). The plan is re-derived from the
    trace rather than passed through, so the run and the operator's preview read
    the same record — one authority.

    A refusal here is the feature: the process exits before a single row is
    written and before a single agent spawns, so a resume that would lie costs
    nothing.
    """
    if "SMIDJA_RESUME_FROM" not in os.environ:
        return None
    from . import resume as resume_module     # late: resume imports data_types only
    try:
        return resume_module.plan(resume_module.ResumeQuery(
            smidja_id=run.smidja_id,
            db_path=run.tracer.db_path,
            session_dir=str(run.session_dir),
            roster={agent.name: agent.model for agent in cfg.agents},
            from_phase=os.environ.get("SMIDJA_RESUME_FROM") or None))
    except (resume_module.ResumeRefused, resume_module.ResumeBusy,
            resume_module.ResumeComplete) as blocked:
        raise SystemExit(f"refused: {blocked}")
