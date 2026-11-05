"""Config loading/validation and agent execution.

Every smidja validates its agents before running (fail fast, nothing spawns
against a half-valid config). Every agent call parses against a concrete
output type; parse failures and gate violations re-prompt the SAME session
with a correction — context intact, bounded retries. Agent proposes, code
disposes.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path
from typing import Literal, Optional

import yaml

from . import (agent_opencode, agent_pi, context as context_telemetry, lm_local,
               permissions, prompts, stall_watch)
from .data_types import (AgentCall, AgentConfig, EnvelopeBase, EventRecord,
                         GateCheck, GateReport, Phase, PhaseParams, PiRequest,
                         smidjaConfig, UsageBreakdown)
from .utils import new_id, now_iso

# ── the always-available primary fallback model: Nemotron 3 Ultra Free ─────
# Slow but good, and always reachable. When an agent's configured model fails
# to resolve or its dispatch produces no usable output, the send() path retries
# ONCE on the fallback model, then records a `model_fallback` trace event.
# Surface-aware: Nemotron works in BOTH coding agents.
#  * opencode (ocrd profile) → opencode/nemotron-3-ultra-free (native alias)
#  * pi harness            → openrouter/nvidia/nemotron-3-ultra-550b-a55b:free
# Override with SMIDJA_FALLBACK_MODEL_PI / SMIDJA_FALLBACK_MODEL_OPENCODE (or set
# the var to "" to disable the retry entirely).
FALLBACK_MODEL_PI = os.environ.get(
    "SMIDJA_FALLBACK_MODEL_PI", "openrouter/nvidia/nemotron-3-ultra-550b-a55b:free")
FALLBACK_MODEL_OPENCODE = os.environ.get(
    "SMIDJA_FALLBACK_MODEL_OPENCODE", "opencode/nemotron-3-ultra-free")


def _fallback_model(agent) -> str | None:
    """The fallback model for an agent's coding surface, if any.

    Returns None when a fallback is disabled (env empty), when the agent is
    ALREADY on the fallback (no point retrying the same model), or when the
    surface is unknown.
    """
    fb = (FALLBACK_MODEL_OPENCODE if agent.coding_agent == "opencode"
          else FALLBACK_MODEL_PI if agent.coding_agent == "pi" else "")
    if not fb or fb == agent.model:
        return None
    return fb


# Scout roles eligible for the interval context-reset (Pillar C): rotating to a
# fresh window seeded with the latest checkpoint instead of forgetting early
# findings when the window approaches 0.85 × its ceiling.
_SCOUT_AGENTS = frozenset({"scout", "wot-scout"})
_CONTEXT_RESET_HEADER = (
    "## CONTEXT RESET — new session seeded with the recon's latest checkpoint\n\n"
    "Your window was nearly full, so you were given a fresh one. Everything you "
    "found so far is in the checkpoint(s) below — RE-READ them before continuing, "
    "then keep mapping from where they left off. Cite paths you already found "
    "directly; do not re-walk them from scratch.\n\n"
)


def _latest_checkpoint(handoff_dir: Path) -> str:
    """Return the newest interval checkpoint's content (capped), or empty."""
    candidates = [
        (handoff_dir / "running_summary.md"),
        (handoff_dir / "scout_findings.md"),
    ]
    import glob as _glob
    numbering = sorted(_glob.glob(str(handoff_dir / "scout_findings_*.md")))
    for path in numbering:
        candidates.append(Path(path))
    best: Optional[Path] = None
    best_mtime = -1
    for path in candidates:
        try:
            m = path.stat().st_mtime
        except OSError:
            continue
        if m > best_mtime:
            best, best_mtime = path, m
    if best is None:
        return ""
    try:
        text = best.read_text(errors="replace")
    except OSError:
        return ""
    return text[:6000] if len(text) > 6000 else text


JSON_FIX_ATTEMPTS = 3      # continue-with-correction attempts for malformed JSON


class GateFailure(RuntimeError):
    pass


# ── config ───────────────────────────────────────────────────────────────────

_ENV_VAR = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}")


def _expand_one(text: str) -> str:
    """Expand the first `${VAR:-default}` in `text`, matching nested braces.

    `default` may itself contain `${...}` (e.g. `${SMIDJA_PLANNER_MODEL:-${SMIDJA_LOCAL_MODEL:-lmstudio/...}}`);
    the closing brace is found by depth counting, so nesting survives.
    """
    i = text.find("${")
    if i == -1:
        return text
    depth, j = 0, i + 2
    while j < len(text):
        if text.startswith("${", j):
            depth += 1
            j += 2
            continue
        if text[j] == "}":
            if depth == 0:
                break
            depth -= 1
        j += 1
    if j >= len(text):
        return text                                   # unclosed — leave as-is
    inner = text[i + 2:j]
    if ":-" in inner:
        name, default = inner.split(":-", 1)
    else:
        name, default = inner, None
    value = os.environ.get(name)
    if value is None:
        value = default if default is not None else ""
    return text[:i] + value + text[j + 1:]


def _expand_env(value):
    """Expand `${VAR}` / `${VAR:-default}` in config strings from the environment.

    Rosters stay environment-agnostic: write `model: ${SMIDJA_LOCAL_MODEL:-}`
    and each machine's `.env` decides the backend without editing the roster.

    Defaults may nest (`${SMIDJA_PLANNER_MODEL:-${SMIDJA_LOCAL_MODEL:-}}`);
    expansion loops until no placeholder remains.
    """
    if isinstance(value, str):
        out = value
        for _ in range(8):                      # bounded: nested defaults, no cycles
            nxt = _expand_one(out)
            if nxt == out:
                break
            out = nxt
        return out
    if isinstance(value, list):
        return [_expand_env(item) for item in value]
    if isinstance(value, dict):
        return {key: _expand_env(item) for key, item in value.items()}
    return value


# ── the hoard road (Rule 07 / plan 56) ───────────────────────────────────────
# The roster carries no concrete model: an empty `model:` is filled from the
# operator's hoard (`config/agents.yaml`, per-host overlay), resolved by the ONE
# resolver `bin/fleet/agents-config.sh`. Env wins (already expanded above); then the
# hoard; then the roster refuses loudly. Two operators, two models, tree untouched.

_HOARD_CACHE: dict[str, str] = {}


def _repo_root() -> Optional[Path]:
    """The tree that owns bin/fleet/agents-config.sh (found, never assumed)."""
    for cand in Path(__file__).resolve().parents:
        if (cand / "bin" / "agents-config.sh").is_file():
            return cand
    return None


def _hoard_agents_yaml() -> Optional[Path]:
    """The operator's private agents.yaml, resolved without hardcoding a path."""
    env = os.environ.get("YMIR_AGENTS_YAML")
    if env and Path(env).is_file():
        return Path(env)
    settings = os.environ.get("YMIR_SETTINGS_DIR")
    if not settings:
        ymir_home = os.environ.get("YMIR_HOME") or os.environ.get("YMIR_HOARD")
        if ymir_home:
            settings = str(Path(ymir_home) / "config")
    if settings:
        cand = Path(settings) / "agents.yaml"
        if cand.is_file():
            return cand
    return None


def _hoard_cfg() -> dict:
    """Parse the hoard agents.yaml once (with overlay left to the resolver)."""
    if "_cfg" in _HOARD_CACHE:
        return json.loads(_HOARD_CACHE["_cfg"])
    p = _hoard_agents_yaml()
    try:
        cfg = (yaml.safe_load(p.read_text()) or {}) if p else {}
    except Exception:
        cfg = {}
    _HOARD_CACHE["_cfg"] = json.dumps(cfg)
    return cfg


def _hoard_default_model() -> str:
    """The hoard's default model, via the ONE resolver (`agents-config.sh default`).

    Falls back to the raw `default_model:` only if the resolver cannot run.
    """
    if "default" in _HOARD_CACHE:
        return _HOARD_CACHE["default"]
    model = ""
    root = _repo_root()
    if root:
        script = root / "bin" / "agents-config.sh"
        try:
            model = subprocess.check_output(
                ["bash", str(script), "default"], text=True,
                stderr=subprocess.DEVNULL, timeout=15).strip()
        except Exception:
            model = ""
    if not model:
        model = str(_hoard_cfg().get("default_model") or "")
    _HOARD_CACHE["default"] = model
    return model


def _hoard_role_model(role: str) -> str:
    """A per-role override from the hoard (`smidja_roles:`), else empty."""
    roles = _hoard_cfg().get("smidja_roles") or {}
    if isinstance(roles, dict):
        v = roles.get(role)
        if isinstance(v, str):
            return v
        if isinstance(v, dict):
            return str(v.get("model") or "")
    return ""


def _fill_models_from_hoard(raw: dict) -> str:
    """Fill empty roster models from the hoard (env already won during expansion)."""
    default = _hoard_default_model()
    targets = [raw.get("defaults") or {}] + list(raw.get("agents") or [])
    for target in targets:
        if not isinstance(target, dict):
            continue
        if not target.get("model"):
            role = str(target.get("name") or "")
            target["model"] = _hoard_role_model(role) or default
    return default


def load_config(path: str = "smidja/smidja_smidja_config/smidja.config.yaml") -> smidjaConfig:
    raw = _expand_env(yaml.safe_load(Path(path).read_text()) or {})
    # Fill empty models from the hoard BEFORE the defaults-merge below, so a
    # roster entry with no model inherits the operator's choice, not a literal.
    _fill_models_from_hoard(raw)
    defaults = raw.get("defaults", {}) or {}
    for agent in raw.get("agents", []) or []:
        for key in ("coding_agent", "model", "thinking", "color", "tools", "writes"):
            if key in defaults:
                agent.setdefault(key, defaults[key])
        agent.setdefault("harness_engineering", defaults.get("harness_engineering", []))
    return smidjaConfig(**raw)


def resolve(cfg: smidjaConfig, name: str) -> AgentConfig:
    for agent in cfg.agents:
        if agent.name == name:
            return agent
    raise SystemExit(f"agent {name!r} is not defined in the config — "
                     f"available: {[a.name for a in cfg.agents]}")


def validate(cfg: smidjaConfig, required: list[str]) -> None:
    """Fail fast: every required name must resolve to a usable agent."""
    problems = []
    for name in required:
        try:
            agent = resolve(cfg, name)
        except SystemExit as e:
            problems.append(str(e))
            continue
        if agent.coding_agent not in ("pi", "opencode"):
            problems.append(f"agent {name!r}: coding_agent {agent.coding_agent!r} "
                            f"is not implemented (pi | opencode)")
        elif not agent.model:
            problems.append(
                f"agent {name!r}: no model — set SMIDJA_LOCAL_MODEL (or "
                f"SMIDJA_{name.upper()}_MODEL), or default_model in your hoard "
                f"config/agents.yaml (resolve with bin/fleet/agents-config.sh)")
        elif agent.coding_agent == "pi":
            try:
                agent_pi.resolve_model(agent.model)
            except ValueError as e:
                problems.append(f"agent {name!r}: {e}")
        else:
            if "/" not in agent.model:
                problems.append(f"agent {name!r}: opencode model must be "
                                f"provider/model (no pi registry lookup): {agent.model}")
        for label, ref in (("system", agent.prompt_engineering.system),
                           ("user", agent.prompt_engineering.user)):
            if not Path(ref).is_file():
                problems.append(f"agent {name!r}: {label} prompt not found: {ref}")
    if problems:
        raise SystemExit("config validation failed:\n- " + "\n- ".join(problems))


# ── execution ────────────────────────────────────────────────────────────────

def execute(run, phase: Phase, call: AgentCall) -> EnvelopeBase:
    """One agent call: render prompts -> pi run -> typed parse -> gates -> envelope."""
    agent = resolve(run.cfg, phase.params.owner)
    agent_dir = run.session_dir / agent.name
    agent_dir.mkdir(parents=True, exist_ok=True)

    # gates receive (envelope, run); the current phase is what gates must read
    # the agent's raw stream from (loop_guard / tools_were_used).
    run._current_phase = phase
    try:
        return _execute(run, phase, call, agent, agent_dir)
    finally:
        run._current_phase = None


def _execute(run, phase: Phase, call: AgentCall, agent, agent_dir) -> EnvelopeBase:

    variables = {
        "prompt": call.prompt,
        "previous_envelope": call.previous.model_dump_json(indent=2) if call.previous else "(none)",
        "context_handoff_dir": str(run.context_handoff_dir),
    }
    system_text = prompts.render(agent.prompt_engineering.system, variables)
    user_text = prompts.render(agent.prompt_engineering.user, variables)

    # Live engineer steering: a `steer.md` written to the session dir (from the
    # visualizer's Pause → steer box, or `smidja steer`) is injected as standing
    # guidance into EVERY subsequent agent call. This is how the engineer tells
    # the run "you are not building what I asked — do this instead" mid-flight.
    steer_file = run.session_dir / "steer.md"
    if steer_file.exists():
        steer_text = steer_file.read_text().strip()
        if steer_text:
            system_text += (
                "\n\n## LIVE ENGINEER GUIDANCE (must follow — highest priority)\n\n"
                f"{steer_text}"
            )
    # Kaia's startup notes (Pillar D admission) ride a separate file so they are
    # clearly inherited context, not a live steer — injected the same standing way.
    kaia_file = run.session_dir / "kaia_notes.md"
    if kaia_file.exists():
        kaia_text = kaia_file.read_text().strip()
        if kaia_text:
            system_text += (
                "\n\n## KAIA ADMISSION NOTES (orchestrator context for this task)\n\n"
                f"{kaia_text}\n\n"
            )
    prompts.save(agent_dir / "prompts", "system.md", system_text)
    prompts.save(agent_dir / "prompts", "user.md", user_text)

    session_id = _agent_session_id(run, agent)
    run.tracer.event(EventRecord(smidja_id=run.smidja_id, phase_id=phase.phase_id,
                                 type="agent_start", name=agent.name,
                                 payload={"model": agent.model, "thinking": agent.thinking,
                                          "color": agent.color,
                                          "session_id": session_id,
                                          "coding_agent": agent.coding_agent,
                                          "purpose": agent.purpose,
                                          "tools": agent.tools,  # None = all tools
                                          "harness_engineering": agent.harness_engineering}))
    run.console.agent_started(agent.name, agent.model, session_id)

    # Parse retries and gate corrections re-enter the SAME pi session, so the
    # last send is the one whose context occupancy is current — while spend is
    # the opposite: every send costs, so usage accumulates across all of them.
    latest: agent_pi.PiResult | None = None
    spent = UsageBreakdown()
    dispatcher = agent_pi.run if agent.coding_agent == "pi" else agent_opencode.run

    # The model this agent is ACTUALLY on. It starts at the configured model and
    # only ever moves to the fallback (never back), so every send in the phase
    # stays on one model — a session continuation must not silently switch models.
    current_model = agent.model

    def _dispatch(req: PiRequest) -> agent_pi.PiResult:
        """One dispatcher run, bracketed by process tracking (killable)."""
        if agent.coding_agent == "pi" and req.model.startswith("lmstudio/"):
            # Keep VRAM from overflowing between phases: if this model is not
            # already resident, free the others so it can load cleanly (the
            # llama.cpp engine 400s / SIGABRTs when a load won't fit).
            lm_local.make_room_for(req.model.split("/", 1)[1])
        # G3 stall watchdog: a live lmstudio pi child that stops writing while
        # the GPU is pegged gets unload→reload + killed so the phase recovers
        # (additive; disabled for opencode/cloud, and off via SMIDJA_STALL_WATCH=0).
        watch = stall_watch.watch_for(req, run, phase, agent)

        def _on_spawn(pid: int) -> None:
            run.tracer.process_start(
                run.smidja_id, "agent", agent.name, pid,
                f"{agent.coding_agent} {agent.name} {req.model}")
            if watch:
                watch.arm(pid)

        def _on_exit(pid: int) -> None:
            if watch:
                watch.disarm()
            run.tracer.process_end(run.smidja_id, pid)

        return dispatcher(
            req,
            on_event=_event_forwarder(run, phase, agent.name),
            on_spawn=_on_spawn,
            on_exit=_on_exit)

    def _usable(result: agent_pi.PiResult) -> bool:
        """Output we can build on: a real response, or a clean (rc 0) exit."""
        return bool(result.text) or result.returncode == 0

    def send(prompt_text: str) -> agent_pi.PiResult:
        nonlocal latest, session_id, current_model
        # Scout-only context reset: when the previous window is nearly full, a
        # long recon scout would otherwise forget its early findings (pi's
        # auto-compaction only frees space, it never rescues recall). Rotate to
        # a FRESH session seeded with the latest checkpoint file, so the scout
        # keeps going with the context it actually needs. Non-scout agents keep
        # the same window (and pi's own compaction) untouched.
        if (latest is not None and agent.name in _SCOUT_AGENTS
                and latest.context_window and latest.context_tokens
                and latest.context_tokens >= 0.85 * latest.context_window):
            seed = _latest_checkpoint(run.context_handoff_dir)
            if seed:
                fresh = f"smidja-{run.smidja_id}-{agent.name}-{new_id(4)}"
                session_id = fresh
                run.save_agent_map(agent.name, {"session_id": fresh,
                                                "model": current_model,
                                                "coding_agent": agent.coding_agent})
                prompt_text = _CONTEXT_RESET_HEADER + seed + "\n\n---\n\n" + prompt_text
                run.tracer.event(EventRecord(
                    smidja_id=run.smidja_id, phase_id=phase.phase_id,
                    type="log", name="context_reset",
                    payload={"agent": agent.name, "session_id": fresh,
                             "seed": seed[:80] + "…" if len(seed) > 80 else seed}))
        request = PiRequest(
            prompt=prompt_text,
            system_prompt=system_text,
            model=current_model,
            thinking=agent.thinking,
            session_id=session_id,
            # absolute: these are read by the pi subprocess, which runs in repo_root
            session_dir=str((agent_dir / "pi_sessions").resolve()),
            raw_output_path=str((agent_dir / "raw_output.jsonl").resolve()),
            tools=agent.tools,
            extensions=agent.harness_engineering,
            cwd=str(run.repo_root),
        )
        # Primary attempt on the configured model; a hard failure retries ONCE
        # on the always-available fallback (Nemotron 3 Ultra Free). A dispatch
        # that raises (model unresolvable / provider down) or returns no output
        # is a dead model, not an agent failure — so the phase survives on the
        # fallback with a fresh session rather than aborting the whole run.
        result: agent_pi.PiResult | None = None
        error: str | None = None
        try:
            result = _dispatch(request)
        except Exception as exc:                       # noqa: BLE001 — model dead, not agent error
            error = str(exc)
        if result is not None and not _usable(result):
            error = (f"returncode={result.returncode}, "
                     f"text={'yes' if result.text else 'no'}")
        if error:
            run.tracer.event(EventRecord(
                smidja_id=run.smidja_id, phase_id=phase.phase_id,
                type="model_error", name="dispatch",
                payload={"agent": agent.name, "model": current_model,
                         "error": error[:400]}))
        fb = _fallback_model(agent)
        if error and fb:
            fresh = f"smidja-{run.smidja_id}-{agent.name}-{new_id(4)}"
            session_id = fresh
            current_model = fb
            run.save_agent_map(agent.name, {"session_id": fresh,
                                            "model": fb,
                                            "coding_agent": agent.coding_agent})
            run.tracer.event(EventRecord(
                smidja_id=run.smidja_id, phase_id=phase.phase_id,
                type="model_fallback", name=agent.coding_agent,
                payload={"agent": agent.name, "from": agent.model, "to": fb,
                         "reason": "primary dispatch returned no usable output"}))
            fb_request = PiRequest(
                prompt=request.prompt,
                system_prompt=request.system_prompt,
                model=fb,
                thinking=request.thinking,
                session_id=fresh,
                session_dir=request.session_dir,
                raw_output_path=request.raw_output_path,
                tools=request.tools,
                extensions=request.extensions,
                cwd=request.cwd,
            )
            result = _dispatch(fb_request)
        if result is not None and not _usable(result):
            raise RuntimeError(
                f"{agent.name} produced no usable output on {current_model} "
                f"(fallback {fb or 'disabled'})")
        if result is None:
            raise RuntimeError(
                f"{agent.name} could not dispatch on {current_model} "
                f"({error or 'no result'}) — fallback {fb or 'disabled'}")
        if result.session_id:
            session_id = result.session_id     # opencode: real ses_... id, for continuation
        run.add_usage(result.tokens, result.cost)
        spent.merge(result.usage)
        latest = result
        return result

    # What the tree looked like before this agent got its hands on it. Every
    # send in this phase — first prompt, JSON retries, gate corrections — is
    # measured against this one baseline.
    tree_before = permissions.snapshot(run)

    result = send(user_text)
    envelope, attempt = _parse_with_retries(run, phase, call, result, send)

    # claim gates — violations flow back into the SAME session as corrections
    for gate_attempt in range(1, max(1, phase.params.retries + 1) + 1):
        violations = []
        for gate in call.gates:
            report = _as_report(gate(envelope, run))
            found = report.violations
            run.tracer.gate_row(phase, gate.__name__, report, gate_attempt)
            run.tracer.event(EventRecord(
                smidja_id=run.smidja_id, phase_id=phase.phase_id,
                type="gate_fail" if found else "gate_pass", name=gate.__name__,
                payload={"attempt": gate_attempt, "violations": found,
                         "checks": [c.model_dump() for c in report.checks]}))
            run.console.gate_result(gate.__name__, report)
            violations.extend(found)
        if not violations:
            break
        if gate_attempt > phase.params.retries:
            raise GateFailure(f"{agent.name} failed gates after {gate_attempt} attempt(s):\n- "
                              + "\n- ".join(violations))
        phase.attempt = gate_attempt
        run.console.retry(agent.name, gate_attempt, phase.params.retries,
                          f"{len(violations)} gate violation(s)")
        correction = ("Your previous response failed validation:\n- "
                      + "\n- ".join(violations)
                      + "\n\nFix these problems, then re-emit ONLY your Report JSON.")
        result = send(correction)
        envelope, attempt = _parse_with_retries(run, phase, call, result, send)

    # Permission is checked after every send is done, and before the envelope is
    # accepted: an agent does not get to report success on a phase in which it
    # wrote somewhere it was not allowed to.
    try:
        touched = permissions.enforce(run, phase, agent, tree_before)
    except permissions.PermissionBreach as breach:
        run.tracer.event(EventRecord(smidja_id=run.smidja_id, phase_id=phase.phase_id,
                                     type="error", name="permission_breach",
                                     payload={"agent": agent.name, "error": str(breach),
                                              "writes": agent.writes,
                                              "protected_files": run.cfg.defaults.protected_files}))
        raise
    if touched:
        run.tracer.event(EventRecord(smidja_id=run.smidja_id, phase_id=phase.phase_id,
                                     type="log", name="paths_touched",
                                     payload={"agent": agent.name, "paths": touched}))

    _persist_envelope(run, phase, agent.name, call, envelope, attempt, valid=True)
    run.console.envelope_summary(envelope)
    reading = latest or result
    # THE PHASE'S CONTEXT RECEIPT. Occupancy is what the last turn left in the
    # window; the window comes from the door the rest of the house uses (never a
    # table here). Recorded per phase, not per agent, because one agent can run
    # several phases (build_1, revise_1) and only the phase knows which ceiling
    # it ended against.
    window, window_source = context_telemetry.window_for(
        current_model, hint=reading.context_window)
    last_usage = reading.last_usage or {}
    receipt = context_telemetry.phase_context(
        model=current_model,
        used=reading.context_tokens,
        window=window,
        source=window_source,
        input_tokens=last_usage.get("input") or 0,
        cache_read=last_usage.get("cacheRead") or 0,
        output=last_usage.get("output") or 0,
        finish=reading.last_finish,
    )
    run.context_by_phase[phase.phase_id] = receipt
    run.tracer.agent_session_row(run.smidja_id, agent, session_id,
                                 context_tokens=reading.context_tokens,
                                 context_window=window)
    run.save_agent_map(agent.name, {"session_id": session_id, "model": agent.model,
                                    "coding_agent": agent.coding_agent})
    run.tracer.event(EventRecord(smidja_id=run.smidja_id, phase_id=phase.phase_id,
                                 type="handoff", name=agent.name,
                                 payload={"artifacts": envelope.artifacts,
                                          "summary": envelope.summary}))
    run.tracer.event(EventRecord(smidja_id=run.smidja_id, phase_id=phase.phase_id,
                                 type="agent_end", name=agent.name,
                                 # Phase totals, not the last send's: a retried
                                 # phase paid for every attempt.
                                 tokens=spent.total_tokens,
                                 payload={"cost": spent.total_cost,
                                          "usage": spent.model_dump(),
                                          "context_tokens": reading.context_tokens,
                                          "context_window": window,
                                          "context": receipt}))
    run.console.agent_finished(agent.name, spent.total_tokens, spent.total_cost)
    run.console.context_receipt(agent.name, receipt)
    if envelope.status != "success":
        raise RuntimeError(f"{agent.name} reported status={envelope.status!r}: {envelope.summary}")
    return envelope


# ── internals ────────────────────────────────────────────────────────────────

def _as_report(result) -> GateReport:
    """Accept a GateReport, or a legacy gate that returned a violations list."""
    if isinstance(result, GateReport):
        return result
    return GateReport(checks=[GateCheck(item=str(v), ok=False) for v in (result or [])])


def _agent_session_id(run, agent: AgentConfig) -> str:
    entry = run.agent_map.get(agent.name)
    if entry and entry.get("model") == agent.model:
        return entry["session_id"]           # rejoin the existing context window
    return f"smidja-{run.smidja_id}-{agent.name}-{new_id(4)}"


# Subagent lanes: the visualizer draws one lane per distinct owner across
# agent-kind phases, so an orchestrator task-tool subagent that only got a
# logged trace event was INVISIBLE as a team member. We materialize each
# dispatch as a real phase row (kind='agent', owner=<subagent>) with its own
# spans — exactly how a manifest agent earns its lane. Seqs count from a large
# base so subagent lanes sort after every manifest phase (session-card dots)
# and can never collide with them.
_SUBAGENT_SEQ_BASE = 1000

# Smidja team roles for task-dispatch lane labelling (matches the harness
# SUBAGENT_TYPES list). Longest-first so "recon_orchestrator" wins over "recon".
_SUBAGENT_ROLES = ("recon_orchestrator", "planner", "builder", "reviewer",
                   "documenter", "scout", "recon", "ui_builder", "general")


def _infer_task_role(description: str) -> str:
    """Map a task description / subagent_type to a smidja role label.

    The orchestrator often omits subagent_type (or the model writes it wrong),
    so the lane name is inferred from the description keywords — "Scout
    (read-only recon)…" becomes `scout`, never `general`. Unknown descriptions
    fall back to `general`. Additive helper (G2); the terminal materializer
    keeps using the explicit subagent_type when present.
    """
    hay = (description or "").strip().lower()
    for role in _SUBAGENT_ROLES:
        if role in hay:
            return role
    return "general"


def _materialize_subagent_start(run, phase: Phase, parent_agent: str, event: dict) -> None:
    """Open a subagent lane the moment an orchestrator `task`/`subagent_create`
    tool call STARTS, so the child is visible below Kaia while it runs.

    Old behavior materialized only at `tool_execution_end` (terminal-only lane,
    and nothing at all if the child stalls). This additive step writes the
    phase row + phase_start + agent_start with status=running immediately; the
    terminal path (kept below) then completes the SAME phase idempotently.
    Deliberately NO agent_sessions row: a task-dispatched `scout` must never
    overwrite a same-named manifest scout's real row (same rule as the closer).
    """
    args = event.get("args") or {}
    sub = _infer_task_role(str(args.get("description") or args.get("subagent_type") or ""))
    if sub == "general" and args.get("subagent_type"):
        sub = str(args.get("subagent_type")).strip().lower()
    description = ((str(args.get("description") or "")).strip()[:140]
                   or f"dispatched by {parent_agent} via the task tool")
    prompt = (str(args.get("prompt") or args.get("task") or ""))[-1200:]
    try:
        parent_cfg = resolve(run.cfg, parent_agent)
        model, surface = parent_cfg.model, parent_cfg.coding_agent
    except Exception:
        model, surface = None, None
    run._subagent_counter += 1
    ts = now_iso()
    sub_phase = Phase(
        phase_id=f"{phase.phase_id}::{sub}::{run._subagent_counter}",
        smidja_id=run.smidja_id,
        seq=phase.seq + _SUBAGENT_SEQ_BASE + run._subagent_counter,
        params=PhaseParams(name=sub, kind="agent", owner=sub,
                           description=description),
        status="running", started_at=ts, ended_at=None,
    )
    run.tracer.phase_upsert(sub_phase)
    for rec in (
        EventRecord(smidja_id=run.smidja_id, phase_id=sub_phase.phase_id,
                    type="phase_start", name=sub,
                    payload={"kind": "agent", "owner": sub,
                             "description": description,
                             "dispatched_by": parent_agent}),
        EventRecord(smidja_id=run.smidja_id, phase_id=sub_phase.phase_id,
                    type="agent_start", name=sub,
                    payload={"model": model, "thinking": None, "color": None,
                             "session_id": None, "coding_agent": surface,
                             "purpose": description, "tools": None,
                             "harness_engineering": [],
                             "dispatched_by": parent_agent,
                             "surface": "task-tool"}),
    ):
        run.tracer.event(rec)
    # Track the lane so the terminal closer completes the SAME phase_id.
    call_id = str(event.get("toolCallId") or event.get("id") or "")
    run._open_subagent_lanes.setdefault(phase.phase_id, {})[call_id or sub] = sub_phase.phase_id


def _materialize_subagent(run, phase: Phase, parent_agent: str, event: dict) -> None:
    """Close (or, for a terminal-only dispatch, fully materialize) a subagent lane.

    If the lane was already opened by `_materialize_subagent_start` at
    tool_execution_start (G2), this idempotently completes that SAME phase:
    agent_end + phase_end + status success/fail, and copies the child's /tmp
    stream into the lane dir. If no open lane exists (opencode reports the task
    RESULT, never a separate start), the phase is written here at completion
    with a real timestamp — the original terminal path, preserved. The subagent
    runs inside the dispatcher's session, so its lane inherits the dispatcher's
    configured model + coding surface; its live session_id and context occupancy
    are unknown here, so they are omitted rather than guessed (no context bar,
    honest label). Deliberately NO agent_sessions row is written: that table's
    key is (smidja_id, agent), so a task-dispatched `scout` must never overwrite a
    same-named manifest scout's real row.
    """
    sub = event.get("subagent_type") or "general"
    status = event.get("status") or "completed"
    ok = status in ("completed", "success")
    description = ((event.get("description") or "").strip()[:140]
                   or f"dispatched by {parent_agent} via the task tool")
    prompt = (event.get("prompt") or "")[-1200:]
    output = (event.get("output") or "").strip() or None

    # ── G2: complete an already-open lane (started at tool_execution_start) ──
    call_id = str(event.get("toolCallId") or event.get("id") or "")
    opened = run._open_subagent_lanes.get(phase.phase_id, {})
    sub_phase_id = opened.pop(call_id, None) or opened.pop(sub, None)
    if sub_phase_id:
        ts = now_iso()
        closer = Phase(
            phase_id=sub_phase_id,
            smidja_id=run.smidja_id,
            seq=phase.seq + _SUBAGENT_SEQ_BASE + run._subagent_counter,
            params=PhaseParams(name=sub, kind="agent", owner=sub,
                               description=description),
            status="success" if ok else "fail", started_at=ts, ended_at=ts,
        )
        run.tracer.phase_upsert(closer)
        for rec in (
            EventRecord(smidja_id=run.smidja_id, phase_id=sub_phase_id,
                        type="subagent_dispatch", name=sub,
                        payload={"description": description, "prompt": prompt,
                                 "status": status, "agent": parent_agent,
                                 "surface": "task-tool",
                                 "dispatcher_phase": phase.phase_id}),
            EventRecord(smidja_id=run.smidja_id, phase_id=sub_phase_id,
                        type="agent_end", name=sub, tokens=0,
                        payload={"cost": 0.0, "usage": {},
                                 "context_tokens": None, "context_window": None,
                                 "dispatched_by": parent_agent, "surface": "task-tool"}),
            EventRecord(smidja_id=run.smidja_id, phase_id=sub_phase_id,
                        type="phase_end", name=sub,
                        payload={"status": "success" if ok else "fail"}),
        ):
            run.tracer.event(rec)
        _capture_subagent_output(run, sub, sub_phase_id, output)
        _copy_subagent_stream(run, sub, sub_phase_id)
        return

    # ── Original terminal-only path (no start event seen) ────────────────────
    try:
        parent_cfg = resolve(run.cfg, parent_agent)
        model, surface = parent_cfg.model, parent_cfg.coding_agent
    except Exception:
        model, surface = None, None
    run._subagent_counter += 1
    ts = now_iso()
    sub_phase = Phase(
        phase_id=f"{phase.phase_id}::{sub}::{run._subagent_counter}",
        smidja_id=run.smidja_id,
        seq=phase.seq + _SUBAGENT_SEQ_BASE + run._subagent_counter,
        params=PhaseParams(name=sub, kind="agent", owner=sub,
                           description=description),
        status="success" if ok else "fail",
        started_at=ts, ended_at=ts,
    )
    run.tracer.phase_upsert(sub_phase)
    for rec in (
        EventRecord(smidja_id=run.smidja_id, phase_id=sub_phase.phase_id,
                    type="phase_start", name=sub,
                    payload={"kind": "agent", "owner": sub,
                             "description": description,
                             "dispatched_by": parent_agent}),
        EventRecord(smidja_id=run.smidja_id, phase_id=sub_phase.phase_id,
                    type="agent_start", name=sub,
                    payload={"model": model, "thinking": None, "color": None,
                             "session_id": None, "coding_agent": surface,
                             "purpose": description, "tools": None,
                             "harness_engineering": [],
                             "dispatched_by": parent_agent,
                             "surface": "task-tool"}),
        EventRecord(smidja_id=run.smidja_id, phase_id=sub_phase.phase_id,
                    type="subagent_dispatch", name=sub,
                    payload={"description": description, "prompt": prompt,
                             "status": status, "agent": parent_agent,
                             "surface": "task-tool",
                             "dispatcher_phase": phase.phase_id}),
        EventRecord(smidja_id=run.smidja_id, phase_id=sub_phase.phase_id,
                    type="agent_end", name=sub, tokens=0,
                    payload={"cost": 0.0, "usage": {},
                             "context_tokens": None, "context_window": None,
                             "dispatched_by": parent_agent, "surface": "task-tool"}),
        EventRecord(smidja_id=run.smidja_id, phase_id=sub_phase.phase_id,
                    type="phase_end", name=sub,
                    payload={"status": "success" if ok else "fail"}),
    ):
        run.tracer.event(rec)
    _capture_subagent_output(run, sub, sub_phase.phase_id, output)
    _copy_subagent_stream(run, sub, sub_phase.phase_id)


def _capture_subagent_output(run, sub: str, sub_phase_id: str, output: str | None) -> None:
    """Capture the child sub-agent's REAL final report into its lane (P1).

    opencode's native `task` tool returns the child's task_result in the tool
    state.output — the parent never sees the child's internal stream, only this
    final text. Writing it as an `agent_output` event + `output.txt` makes the
    lane's "outputs" section show what the child ACTUALLY produced instead of
    an empty shell. Additive; absent output is a no-op.
    """
    if not output:
        return
    clipped = output[:30000]
    try:
        lane_dir = Path(run.data_base) / "sessions" / run.smidja_id / sub
        lane_dir.mkdir(parents=True, exist_ok=True)
        (lane_dir / "output.txt").write_text(clipped, encoding="utf-8")
    except Exception:
        pass
    run.tracer.event(EventRecord(
        smidja_id=run.smidja_id, phase_id=sub_phase_id,
        type="agent_output", name=sub,
        payload={"text": clipped, "surface": "task-tool", "agent": sub}))


def _copy_subagent_stream(run, sub: str, sub_phase_id: str) -> None:
    """Best-effort: carry the child pi's stream into the lane dir so the
    visualizer can render the sub-agent's thinking too (the thinking endpoint
    parses raw_output.jsonl pi delta streams under the agent dir). The child's
    session file lives in /tmp (task tool --session). Copy, never move: the
    /tmp file is the active child's live record while it runs. The merged
    subagents.ts task tool ALSO mirrors to the persistent subagents path, so a
    subagent-* copy is attempted first, then the smidja's smidja-task-* name.
    """
    try:
        lane_dir = Path(run.data_base) / "sessions" / run.smidja_id / sub
        lane_dir.mkdir(parents=True, exist_ok=True)
        dest = lane_dir / "raw_output.jsonl"
        candidates = sorted(
            [p for p in Path("/tmp").glob("smidja-task-*.jsonl")
             if p.stat().st_mtime < time.time()] +
            [p for p in Path(os.path.expanduser("~/.pi/agent/sessions/subagents")).glob("subagent-task-*.jsonl")],
            key=lambda p: p.stat().st_mtime, reverse=True,
        )
        if candidates:
            shutil.copyfile(candidates[0], dest)
    except Exception:
        pass


def _event_forwarder(run, phase: Phase, agent_name: str):
    """One tool_call event per real tool call, plus compact events per compaction."""
    tracker = agent_pi.ToolCallTracker()
    activity = agent_pi.ActivityObserver()

    def forward(event: dict) -> None:
        if event.get("type") == "tool_execution_start" and (
                event.get("toolName") in ("task", "subagent_create")):
            # G2 live lanes: open the subagent lane the moment the dispatch
            # starts (status=running), so the child is visible below Kaia while
            # it runs instead of only appearing at tool_execution_end. The
            # terminal path below completes the SAME lane idempotently.
            _materialize_subagent_start(run, phase, agent_name, event)
            return
        if event.get("type") == "subagent_dispatch":
            # opencode `task`-tool subagent dispatch (agent_opencode). One
            # dispatch = one real agent the orchestrator spawned, and it must
            # surface as its OWN lane exactly like a manifest agent, not just
            # as a logged event — so we materialize it as a phase row + spans.
            # Gates still verify dispatch from raw_output.jsonl (their source).
            _materialize_subagent(run, phase, agent_name, event)
            return
        if (event.get("type") == "tool_execution_end"
                and (event.get("toolName") in ("task", "subagent_dispatch"))):
            # pi `task`-tool subagent dispatch (task-dispatch.ts extension).
            # The child ran synchronously, so the _end event carries the result
            # and we materialize the subagent lane at completion — exactly the
            # same contract as opencode's terminal `task` result. Still traced
            # as a plain tool call below? No: a dispatch is a lane, not a tool.
            eargs = event.get("args") or {}
            result_block = event.get("result") or {}
            _materialize_subagent(run, phase, agent_name, {
                "type": "subagent_dispatch",
                "subagent_type": eargs.get("subagent_type")
                                 or eargs.get("agent") or "general",
                "description": eargs.get("description") or "",
                "prompt": eargs.get("prompt") or "",
                "status": "completed" if not event.get("isError") else "failed",
                "output": (result_block.get("content") or [{}])[0].get("text")
                          if isinstance(result_block.get("content"), list)
                          else "",
            })
            return
        if event.get("type") == "thinking":
            # Model chain-of-thought (opencode reasoning parts; pi thinking blocks
            # live only in pi_sessions). Kept out of the tool/compact branch so it
            # can coexist; the visualizer also reads the raw streams directly.
            run.tracer.event(EventRecord(smidja_id=run.smidja_id, phase_id=phase.phase_id,
                                         type="thinking", name=agent_name,
                                         payload={"text": (event.get("text") or "")[-2000:],
                                                  "surface": event.get("surface", ""),
                                                  "agent": agent_name}))
            return
        if event.get("type") == "usage":
            # P2 additive live-spend: the dispatcher (opencode step-finish)
            # reports tokens/cost as they happen. Trace it AND bump the session
            # row NOW so the UI's cost/token numbers move while the run is live
            # instead of staying 0 until the phase ends. Additive — the
            # existing end-of-phase add_usage still finalizes.
            tokens = int(event.get("tokens") or 0)
            cost = float(event.get("cost") or 0.0)
            run.add_usage(tokens, cost)
            run.tracer.event(EventRecord(
                smidja_id=run.smidja_id, phase_id=phase.phase_id,
                type="usage", name=agent_name, tokens=tokens,
                payload={"cost": cost, "surface": event.get("surface", ""),
                         "agent": agent_name}))
            return
        record = tracker.observe(event)
        if record is not None:
            # The call's span rides the columns; duration_ms stays in the payload as
            # pi's own authoritative number.
            run.tracer.event(EventRecord(smidja_id=run.smidja_id, phase_id=phase.phase_id,
                                         type="tool_call", name=record.pop("label"),
                                         started_at=record.pop("started_at", None),
                                         ended_at=record.pop("ended_at", None),
                                         payload={**record, "agent": agent_name}))
            return
        compact = activity.observe(event)
        if compact is not None:
            run.tracer.event(EventRecord(smidja_id=run.smidja_id, phase_id=phase.phase_id,
                                         type="compact", name=compact.pop("subtype", ""),
                                         payload={**compact, "agent": agent_name}))
    return forward


def _extract_json(text: str) -> dict:
    candidate = text
    if "```" in text:
        for block in text.split("```")[1::2]:
            block = block.removeprefix("json").strip()
            if block.startswith("{"):
                candidate = block
                break
    start, end = candidate.find("{"), candidate.rfind("}")
    if start == -1 or end <= start:
        raise ValueError("no JSON object found in the response")
    return json.loads(candidate[start:end + 1])


def _parse_with_retries(run, phase: Phase, call: AgentCall, result, send):
    """Parse the final response against the declared output type; on failure,
    continue the SAME session with a correction (bounded)."""
    for attempt in range(1, JSON_FIX_ATTEMPTS + 2):
        try:
            payload = _extract_json(result.text)
            return call.output_type.model_validate(payload), attempt
        except Exception as error:
            # G4 additive fallback — a truncated/mistyped Literal value (e.g.
            # `"Succes"` from a model that clipped the enum mid-token) is
            # repaired to the unique full literal BEFORE we re-prompt, so the
            # run survives on the SAME session instead of spending a correction
            # round on a typo. Strict path first; this only runs when that fails.
            repaired = _lenient_literal_repair(_extract_json(result.text),
                                               call.output_type)
            if repaired is not None:
                try:
                    return call.output_type.model_validate(repaired), attempt
                except Exception:
                    pass  # repair didn't help — fall through to the correction
            _persist_envelope(run, phase, phase.params.owner, call, None, attempt,
                              valid=False, raw=result.text)
            if attempt > JSON_FIX_ATTEMPTS:
                raise RuntimeError(
                    f"{phase.params.owner} never produced valid "
                    f"{call.output_type.__name__} JSON: {error}") from error
            run.console.retry(phase.params.owner, attempt, JSON_FIX_ATTEMPTS,
                              f"invalid {call.output_type.__name__} JSON: {error}")
            # Send back the EXACT error AND a concrete, filled-in example of the
            # envelope, so the model fixes rather than guesses. A model that
            # emitted prose needs to SEE the target shape, not just be told it
            # was wrong — small/local models can't infer a schema from a name.
            example = _envelope_example(call.output_type, result.text)
            result = send(
                f"Your previous response was not valid JSON for the required "
                f"structure.\n\nError: {error}\n\n"
                f"The response must be EXACTLY one JSON object — no prose, no "
                f"markdown code fences, no trailing text — with these fields: "
                f"{', '.join(call.output_type.model_fields.keys())}.\n\n"
                f"Here is the exact shape with YOUR content filled in:\n"
                f"{example}\n\n"
                f"Reply with ONLY that JSON object.")


def _lenient_literal_repair(payload: dict, output_type) -> dict | None:
    """Additive G4 repair: for each Literal-typed envelope field whose value is
    a PREFIX of exactly one allowed literal, substitute the full literal.

    Handles `"Succes"`→`"success"`, `"fail"` already valid, `"f"`→`"fail"`, and
    leaves everything else untouched. Returns None when nothing changed (so the
    caller keeps the strict error path). Never loosens the strict path — a value
    that is NOT a unique prefix is left alone and fails as before.
    """
    from typing import get_args, get_origin

    changed = False
    for name, field in output_type.model_fields.items():
        if name not in payload or not isinstance(payload[name], str):
            continue
        ann = field.annotation
        if get_origin(ann) is not Literal:
            continue
        allowed = {a for a in get_args(ann) if isinstance(a, str)}
        if not allowed:
            continue
        raw = payload[name]
        if raw in allowed:
            continue
        # Case-insensitive unique prefix match — `"Succes"` → `"success"`,
        # `"FAIL"` → `"fail"` — so a model that clipped or mistyped the enum
        # casing survives without a correction round.
        low = raw.lower()
        matches = [a for a in allowed if a.lower().startswith(low)]
        if len(matches) == 1:
            payload[name] = matches[0]
            changed = True
    return payload if changed else None


def _envelope_example(output_type, raw_text: str) -> str:
    """Build a concrete, prefilled JSON example of the output envelope so the
    model can correct its format instead of guessing the schema.

    Uses the model's own words from `raw_text` where they fit, so the retry
    keeps the work the model already did and only fixes the envelope.
    """
    import json as _json

    fields = {name: None for name in output_type.model_fields.keys()}
    for name in fields:
        ann = output_type.model_fields[name].annotation
        tname = getattr(ann, "__name__", str(ann))
        if tname in ("str",):
            fields[name] = "…"
        elif tname in ("bool",):
            fields[name] = False
        elif tname in ("int", "float"):
            fields[name] = 0
        elif "list" in tname.lower():
            fields[name] = []
        elif "dict" in tname.lower():
            fields[name] = {}
    # Prefer the model's own summary/changed_files if it mentioned them.
    for name, hint in (("summary", "Summary:"), ("changed_files", "changed"),
                       ("status", "success"), ("commit_message", "commit")):
        if name not in fields:
            continue
        for line in raw_text.splitlines():
            low = line.lower()
            if hint.lower() in low and ":" in line:
                val = line.split(":", 1)[1].strip().strip('"').strip("'")
                if val:
                    fields[name] = val if not isinstance(fields[name], list) else [val]
                    break
    return _json.dumps(fields, indent=2)


def _persist_envelope(run, phase: Phase, agent_name: str, call: AgentCall,
                      envelope: Optional[EnvelopeBase], attempt: int,
                      valid: bool, raw: str = "") -> None:
    payload_json = envelope.model_dump_json(indent=2) if envelope else json.dumps({"raw": raw[-2000:]})
    run.tracer.envelope_row(phase, agent_name, call.output_type.__name__,
                            payload_json, valid, attempt)
    if envelope:
        record = {"agent_name": agent_name, "purpose": resolve(run.cfg, agent_name).purpose,
                  "output_type": call.output_type.__name__, "attempt": attempt,
                  **envelope.model_dump()}
        (run.session_dir / agent_name / "envelope.json").write_text(json.dumps(record, indent=2))
