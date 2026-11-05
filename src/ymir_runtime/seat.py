"""seat(errand) -> seat_id — the one verb that puts an errand in the world.

Everything a seat needs is hidden behind this call: the Yggdrasil worktree, the
harness and its model, the backend pane, the task record, and the heartbeat
baseline. Two steps the old road takes are NOT yet owned here, and the record
says so plainly rather than pretending otherwise:

  · pre-dispatch well recall IS done (best effort, exactly as the old door)
  · the Utgard sandbox is NOT launched — a declared utgard is refused, and the
    caller keeps the old road until the sandbox module's own phase

A refusal is `EngineRefusal`, which is the strangler's hinge: the adapters catch
it, say why, and run the road they already had.
"""

from __future__ import annotations

import os
import random
import re
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Mapping

from . import backend as backend_mod
from . import container, harness, heartbeat, paths, proc, worktree as worktree_mod
from .errors import EngineError, EngineRefusal

SAFE_ID = re.compile(r"^[A-Za-z0-9._-]+$")
KINDS = ("ship", "scout")
MODES = ("direct-PR", "local-only", "no-mistakes", "scout")
ISOLATIONS = ("auto", "herdr", "utgard", "on", "off")
ENGINE_ID = "ymir_runtime/phase1"

_TASK_SECTION_END = re.compile(r"^# (Delivery contract|Setup|Rules)")
_VERDICT_ROW = re.compile(r'"([^"]*)","([^"]*)"')


def task_section(brief: str) -> str:
    """The brief's `# Task` text — the errand itself, as the old door reads it."""
    collected: list[str] = []
    inside = False
    for line in brief.splitlines():
        if line.startswith("# Task"):
            inside = True
            continue
        if inside and _TASK_SECTION_END.match(line):
            break
        if inside and line and not line.startswith("#"):
            collected.append(line)
    return "\n".join(collected)[:1500].strip()


def _worth_a_smith(roots: paths.Roots, brief_text: str, runner: proc.Runner) -> tuple[str, str]:
    """The first law, consulted through the door that owns the heuristic.

    The engine does not keep a second copy of "is this worth a smith": it asks
    `bin/seat/herdr-run.sh worth-a-smith`, the same door the old road asks. The two
    guards the old door adds before asking are kept here because they are about
    the BRIEF, not the heuristic.
    """
    text = task_section(brief_text)
    if "{TASK}" in text:
        return "no", "the brief still carries the unfilled {TASK} errand text — write the errand into the brief before dispatch"
    if len(text) <= 1:
        return "no", "the brief has no # Task section to judge — fill the errand before dispatch"
    # The door moved in the restructure (bin/herdr-run.sh -> bin/seat/herdr-run.sh)
    # and this line did not follow: the engine answered "no worth-a-smith door on
    # this machine" and dispatched on the brief alone, silently, for every errand
    # (measured 2026-10-24). Resolve the current path first, keep the old one as a
    # fallback so a pre-restructure checkout still answers.
    door = roots.root / "bin" / "seat" / "herdr-run.sh"
    if not door.is_file():
        door = roots.root / "bin" / "herdr-run.sh"
    if door.is_file():
        result = runner([str(door), "worth-a-smith", text])
        row = _VERDICT_ROW.search(proc.out(result))
        if row:
            verdict, why = row.group(1), row.group(2)
            if verdict in ("yes", "no"):
                return verdict, why
        return "yes", "worth-a-smith verdict unreadable; dispatching on the brief"
    return "yes", "no worth-a-smith door on this machine; dispatching on the brief"


@dataclass(frozen=True)
class Errand:
    """What a caller hands the engine. Plain data; no behaviour, no defaults
    hidden in the caller."""

    task_id: str
    project_dir: str
    request: str = ""
    kind: str = "ship"
    mode: str = "direct-PR"
    yolo: str = "off"
    harness: str = ""
    model: str = ""
    effort: str = ""
    backend: str = ""
    isolation: str = "auto"
    brief: str = ""
    lock: str = ""
    force: bool = False
    role: str = ""
    worth_a_smith: str = "unknown"
    worth_why: str = "not consulted by the engine"
    extra: Mapping[str, str] = field(default_factory=dict)

    @classmethod
    def coerce(cls, value: "Errand | Mapping[str, Any]") -> "Errand":
        if isinstance(value, cls):
            return value
        if isinstance(value, Mapping):
            known = {f for f in cls.__dataclass_fields__ if f != "extra"}
            data = {k: v for k, v in value.items() if k in known}
            rest = {k: str(v) for k, v in value.items() if k not in known}
            return cls(**data, extra=rest)
        raise TypeError("seat() takes an Errand or a mapping")


def _slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")


def _prompt_for(
    roots: paths.Roots,
    errand: Errand,
    seat_id: str,
    brief_text: str,
    *,
    runner: proc.Runner,
) -> tuple[Path, str]:
    """Write `data/<id>/prompt.md`: the brief plus the well's recall."""
    data_dir = roots.data / seat_id
    data_dir.mkdir(parents=True, exist_ok=True)
    prompt = data_dir / "prompt.md"
    recalled = ""
    mimir = roots.root / "bin" / "mimir.sh"
    if mimir.is_file():
        title = ""
        for line in brief_text.splitlines():
            if line.startswith("#"):
                title = line.lstrip("# ").strip()
                break
        recall = runner([str(mimir), "recall", title or seat_id, "--k", "4"])
        if proc.ok(recall):
            recalled = (recall.stdout or "").strip()
    body = brief_text.rstrip("\n") + "\n"
    if recalled:
        body += "\n\n---\n\n## Recalled context (the well — Mimirsbrunn)\n\n" + recalled + "\n"
    prompt.write_text(body, encoding="utf-8")
    return prompt, body


def _launch_script(
    roots: paths.Roots,
    seat_id: str,
    launch_cwd: Path,
    launch_cmd: str,
    *,
    lock: str = "",
) -> Path:
    state = roots.state
    state.mkdir(parents=True, exist_ok=True)
    script = state / f"{seat_id}.launch.sh"
    inner = launch_cmd
    if lock:
        inner = f"exec {proc.shell_quote(lock)} bash -c {proc.shell_quote(launch_cmd)}"
    elif not launch_cmd.startswith("exec "):
        inner = f"exec {launch_cmd}"
    script.write_text(
        "#!/usr/bin/env bash\nset -eu\n"
        f"cd {proc.shell_quote(str(launch_cwd))}\n"
        f"{inner}\n",
        encoding="utf-8",
    )
    script.chmod(0o755)
    return script


def _prove_seat(
    roots,
    placed,
    launch_cwd: Path,
    *,
    runner: proc.Runner = proc.run,
    env: Mapping[str, str] | None = None,
) -> tuple[str, str, str]:
    """Ask the proof door where the agent stands: `(pane, state, note)`.

    An unproven seat returns empty values — the caller records `seat=no` and keeps
    the pane it chose, so the record says exactly what was and was not seen.
    """
    environ = dict(env) if env is not None else dict(os.environ)
    # The door ships beside the engine, so the engine finds it from its OWN tree —
    # never from whichever repo the errand happens to work in.
    door = Path(__file__).resolve().parents[2] / "bin" / "seat" / "seat-prove.sh"
    if not door.is_file():
        return placed.target, "unchecked", "bin/seat/seat-prove.sh is missing — the seat was not proved"
    settle = environ.get("YMIR_SEAT_SETTLE", "25")
    completed = runner(
        [str(door), placed.target, str(launch_cwd), "--backend", placed.backend, "--settle", settle]
    )
    if not proc.ok(completed):
        lines = (completed.stderr or "").strip().splitlines()
        return "", (lines[-1] if lines else "unproven"), ""
    line = (completed.stdout or "").strip().splitlines()
    fields = (line[0] if line else "").split("\t")
    pane = fields[0] if fields else ""
    state = fields[1] if len(fields) > 1 else "unknown"
    if not pane:
        # A door that exits 0 and names no pane has proved NOTHING; a green that
        # carries no evidence is the false green this house has paid for twice.
        return "", "unproven", ""
    note = ""
    for extra in (completed.stderr or "").strip().splitlines():
        if "not in the pane" in extra:
            note = extra.split("seat-prove: ", 1)[-1]
    return pane or placed.target, state or "unknown", note


def seat(
    errand: "Errand | Mapping[str, Any]",
    *,
    runner: proc.Runner = proc.run,
    env: Mapping[str, str] | None = None,
    probe=proc.which,
    now: float | None = None,
) -> str:
    """Seat one errand end to end and return its seat id."""
    errand = Errand.coerce(errand)
    environ = dict(env) if env is not None else dict(os.environ)
    roots = paths.resolve(environ)

    seat_id = (errand.task_id or "").strip()
    if not seat_id or not SAFE_ID.match(seat_id):
        raise EngineRefusal(
            f"unsafe task id '{errand.task_id}' — ids match [A-Za-z0-9._-]+",
            "pass a slug id (letters, digits, dot, dash, underscore)",
        )

    project = Path(errand.project_dir).expanduser()
    if not project.is_dir():
        raise EngineRefusal(
            f"project directory not found: {project}",
            "pass an existing git working tree as <project-dir>",
        )

    state, data, config = roots.state, roots.data, roots.config

    if heartbeat.meta_path(state, seat_id).exists():
        raise EngineRefusal(
            f"a seat record already stands for '{seat_id}' at {heartbeat.meta_path(state, seat_id)}",
            "stop it first, or relaunch it through bin/agents/einherjar-spawn.sh --relaunch",
        )

    brief_path = Path(errand.brief).expanduser() if errand.brief else data / seat_id / "brief.md"
    brief_text = ""
    if brief_path.is_file():
        brief_text = brief_path.read_text(encoding="utf-8", errors="replace")
    elif errand.request:
        brief_text = errand.request

    declared, declared_reason = container.declared_from_brief(brief_text)
    override = ""
    if errand.isolation in ("herdr", "utgard"):
        declared, declared_reason = errand.isolation, "explicit --isolation"
    elif errand.isolation in ("on", "off"):
        override = errand.isolation
        if errand.isolation == "on":
            declared, declared_reason = "utgard", "explicit --isolation on"

    plan = container.plan(
        declared=declared,
        reason=declared_reason,
        override=override,
        env=environ,
        runner=runner,
        probe=probe,
    )
    if not plan.supported:
        raise EngineRefusal(plan.refusal, "bin/agents/einherjar-spawn.sh keeps this road until the sandbox module owns it")

    try:
        tree = worktree_mod.ensure(seat_id, project, roots.wt_root, runner=runner)
    except Exception as exc:  # noqa: BLE001 - the caller must see the plain why
        raise EngineRefusal(str(exc), "check the project worktree and the .yggdrasil root") from exc

    try:
        selection = harness.resolve(
            harness=errand.harness,
            model=errand.model,
            effort=errand.effort,
            config_dir=config,
            env=environ,
            runner=runner,
        )
    except ValueError as exc:
        raise EngineRefusal(str(exc), "pass an explicit --model provider/model that this machine serves") from exc

    if not selection.is_verified and not selection.is_raw:
        raise EngineRefusal(
            f"harness '{selection.name}' is not verified for direct launch; verified: {', '.join(harness.VERIFIED)}",
            "pass a raw launch command via --harness, or use a verified harness",
        )

    try:
        chosen = backend_mod.choose(
            requested=errand.backend, env=environ, config_dir=config, runner=runner, probe=probe
        )
    except (ValueError, RuntimeError) as exc:
        raise EngineRefusal(str(exc), "start a herdr server or install tmux") from exc

    if errand.kind not in KINDS:
        raise EngineRefusal(f"unsupported kind '{errand.kind}' (supported: {', '.join(KINDS)})", "")
    if errand.kind == "ship" and errand.mode not in MODES:
        raise EngineRefusal(f"unsupported mode '{errand.mode}' (supported: {', '.join(MODES)})", "")

    worth, worth_why = errand.worth_a_smith, errand.worth_why
    if worth == "unknown":
        worth, worth_why = _worth_a_smith(roots, brief_text, runner)
        if worth == "no" and not errand.force:
            raise EngineRefusal(
                f"this errand is not worth a smith ({worth_why})",
                "answer it in hand, or pass --force to override and record the override",
            )

    prompt_path, prompt_body = _prompt_for(roots, errand, seat_id, brief_text or errand.request, runner=runner)
    # The generator is told WHERE the seat stands: the extension set is the worktree's,
    # never the primary checkout's (plan 190 §4.1).
    launch_cmd = harness.build_launch_command(selection, str(prompt_path), launch_cwd=tree.path, runner=runner)
    script = _launch_script(roots, seat_id, tree.path, launch_cmd, lock=errand.lock)
    pane_cmd = f"bash {proc.shell_quote(str(script))}"

    seat_state_dir = Path(
        environ.get("XDG_STATE_HOME", str(Path.home() / ".local" / "state"))
    ) / "ymir" / "seats" / seat_id
    seat_state_dir.mkdir(parents=True, exist_ok=True)

    try:
        placed = backend_mod.launch(
            chosen,
            seat_id=seat_id,
            pane_cmd=pane_cmd,
            cwd=tree.path,
            seat_state_dir=seat_state_dir,
            env=environ,
            runner=runner,
            probe=probe,
        )
    except (RuntimeError, ValueError) as exc:
        raise EngineRefusal(str(exc), "check the backend and the worktree, then retry") from exc

    # --- PROVE THE SEAT: a spawn is not a seat until the agent list shows it ----
    # Measured 2026-11-05: this road printed `spawned … target=wQ:p1` for an errand
    # whose pane held a bare shell while the agent stood in another pane entirely,
    # and three errands died that way while their records claimed a worker. The
    # proof is ONE door (bin/seat/seat-prove.sh), shared with the shell road, so
    # neither road can claim a seat it never saw.
    seat_pane, seat_state, seat_note = _prove_seat(
        roots, placed, tree.path, runner=runner, env=environ
    )

    moment = heartbeat.iso(now)
    heartbeat.baseline(state, seat_id, moment)

    epoch = int(now if now is not None else time.time())
    spawn_gen = f"s{epoch}.{os.getpid()}.{random.randint(0, 32767)}"
    record: dict[str, str] = {
        "id": seat_id,
        "engine": ENGINE_ID,
        "kind": errand.kind,
    }
    if errand.kind == "ship":
        record["mode"] = errand.mode
        record["yolo"] = errand.yolo
    record.update(
        {
            "harness": selection.name,
            "raw_launch": selection.raw_launch,
            "harness_provenance": selection.provenance,
            "model": selection.model,
            "model_provenance": selection.model_provenance,
            "model_local": "yes" if selection.is_local else "no",
            "effort": selection.effort,
            "backend": placed.backend,
            "backend_reason": chosen.reason,
            "window": seat_pane or placed.target,
            "seat_workspace": placed.workspace,
            "seat": "yes" if seat_pane else "no",
            "seat_state": seat_state,
            "worktree": str(tree.path),
            "worktree_created": "yes" if tree.created else "no",
            "worktree_base": tree.base,
            "worktree_head": tree.head,
            "project": str(project),
            "brief": str(brief_path) if brief_path.is_file() else "",
            "prompt": str(prompt_path),
            "isolation": plan.effective,
            "isolation_declared": plan.declared,
            "isolation_reason": plan.reason,
            "worth_a_smith": worth,
            "worth_why": worth_why,
            "force": "1" if errand.force else "0",
            "locked": "yes" if errand.lock else "no",
            "launched": str(epoch),
            "launch_iso": moment,
            "launch": str(script),
            "spawn_gen": spawn_gen,
            "role": errand.role,
        }
    )
    if seat_note:
        record["seat_note"] = seat_note
    for key, value in (errand.extra or {}).items():
        record.setdefault(key, str(value))
    heartbeat.write_meta(state, seat_id, record)

    data_dir = data / seat_id
    data_dir.mkdir(parents=True, exist_ok=True)
    if prompt_body and not brief_path.exists():
        (data_dir / "brief.md").write_text(prompt_body, encoding="utf-8")

    # An UNPROVEN seat is a failure, recorded and reported — the record already says
    # `seat=no` with the evidence, and the status line says `failed:` so the
    # heartbeat, the sweep and the operator all read the same fact.
    if not seat_pane:
        heartbeat.append(
            state,
            seat_id,
            f"failed: the launch produced NO agent — pane {placed.target} holds no agent and none "
            f"stands in {tree.path} ({seat_state})",
        )
        raise EngineError(
            f"seat '{seat_id}' was launched into {placed.target} but NO agent stands there or in "
            f"{tree.path} — the errand is not running ({seat_state})"
        )

    watcher = roots.root / "bin" / "eindri-watch.sh"
    if watcher.is_file():
        runner([
            str(watcher), "arm-silence", seat_id,
            "--window", environ.get("EINDRI_SILENT_WINDOW", "1800"),
        ])

    return seat_id


def errand_from(errand: Errand) -> dict[str, str]:  # pragma: no cover - convenience
    return {k: str(v) for k, v in asdict(errand).items()}
