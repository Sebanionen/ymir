#!/usr/bin/env -S uv run
# /// script
# dependencies = ["pydantic", "python-dotenv", "pyyaml", "rich"]
# ///
"""smidja Resume — continue a run at its last committed phase.

Usage:
    uv run apps/smidja/smidja_resume.py <run-id> [--from-phase <name>] [--dry-run] [--config <roster>]

    # the operator's door, from the repo root:
    just resume <run-id> [--from-phase <name>]

What it does, in order:

  1. reads the trace (`smidja.db`: `sessions` · `phases` · `gate_results` ·
     `events.payload_json` · `envelopes`, and `sessions/<id>/<agent>/envelope.json`
     + `agent_map.json`);
  2. finds the last phase that is green AND whose gate passed — the checkpoint;
  3. re-enters the chain at the phase after it (or at `--from-phase`), hands the
     committed phases' envelopes and verdicts forward instead of buying them
     again, and keeps every agent's coding-agent session id so context survives;
  4. refuses, and says why, when the record cannot be trusted.

The three refusals — the vocabulary is the feature:

    no such run                        no session under that id (or no such phase)
    nothing green to resume from       nothing stands green with its gate passed
    the roster changed since this run   an agent's model is not the run's model

What is deliberately NOT resumed: **a model switch**. `agent_map.json` records
the model each session was created with; a roster edit means a different session,
and a bad resume is worse than none — so the run refuses instead of quietly
starting the agent cold.

Exit: 0 the resumed run succeeded · 1 it ran and failed · 2 refused.
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path

from smidja_modules import agents, git_helper, resume as resume_module, utils


def main(run_id: str, config: str, from_phase: str | None, dry_run: bool) -> int:
    cfg = agents.load_config(config)
    session_dir = (git_helper.repo_root() / cfg.defaults.data_dir / "sessions" / run_id)
    try:
        plan = resume_module.plan(resume_module.ResumeQuery(
            smidja_id=run_id,
            db_path=cfg.observability.db,
            session_dir=str(session_dir),
            roster={agent.name: agent.model for agent in cfg.agents},
            from_phase=from_phase))
    except resume_module.ResumeRefused as refused:
        print(f"refused: {refused.reason}")
        if refused.detail:
            print(f"  {refused.detail}")
        return 2
    except (resume_module.ResumeBusy, resume_module.ResumeComplete) as blocked:
        print(f"refused: {blocked}")
        return 2

    print(f"resume[1]{{field,value}}:")
    for row in plan.describe():
        field, _, value = row.partition(":")
        print(f'  "{field.strip()}","{value.strip()}"')

    if dry_run:
        print('  "launched","no — --dry-run"')
        return 0

    chain = Path(__file__).resolve().parent / f"{plan.chain}.py"
    if not plan.chain or not chain.is_file():
        print(f'  "error","the chain {plan.chain or "(unrecorded)"} is not in '
              f'{Path(__file__).resolve().parent}"')
        return 2

    # The ask travels as a file, not as an argv: a request can be longer than
    # ARG_MAX, and the chain's own resolver already reads a path as its contents.
    request_path = session_dir / "resume_request.md"
    request_path.write_text(plan.request)
    env = dict(os.environ, SMIDJA_RESUME_FROM=plan.from_phase)
    print(f'  "chain","{chain.name}"')
    print(f'  "request","{request_path}"')
    print(f'  "launched","yes — the run continues under the same smidja_id"')
    sys.stdout.flush()
    completed = subprocess.run(
        [sys.executable, str(chain), str(request_path),
         "--config", config, "--smidja-id", run_id],
        env=env, cwd=str(git_helper.repo_root()))
    return completed.returncode


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("run_id", help="the smidja_id of the run to continue")
    parser.add_argument("--config", default="smidja/smidja_smidja_config/smidja.config.yaml")
    parser.add_argument("--from-phase", default=None,
                        help="re-enter at this phase instead of the phase after the checkpoint")
    parser.add_argument("--dry-run", action="store_true",
                        help="print the plan and stop — launch nothing")
    args = parser.parse_args()
    sys.exit(main(args.run_id, args.config, args.from_phase, args.dry_run))
