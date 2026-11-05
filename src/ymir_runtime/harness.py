"""Hamr — which harness wears this errand, and the exact line that launches it.

The engine owns the *choice* and the *line*; it does not own how a harness
behaves (that is `bin/fleet/hamr-harness.sh` and the harness itself). Resolution is
the machine's, never a repo template's, and the provenance is always named:

  1. an explicit flag                      → "explicit flag"
  2. `config/eindri-harness`               → "config/eindri-harness (this machine)"
  3. the fleet law                         → local model → pi · hosted → opencode

A harness outside `VERIFIED` is refused unless the caller supplies a raw launch
command (a harness value containing whitespace) — the deliberate escape hatch the
old door already has, kept so a new adapter can be trialled without a code change.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable, Mapping, Sequence

from . import paths, proc

VERIFIED = ("opencode", "pi", "pi-signed")

LOCAL_PROVIDER_HINTS = ("llama", "lmstudio", "apodex")

Catalog = Callable[[], Iterable[str]]
Probe = Callable[[str], str]


@dataclass(frozen=True)
class HarnessSelection:
    name: str
    model: str
    effort: str
    provenance: str
    model_provenance: str
    raw_launch: str = ""

    @property
    def is_raw(self) -> bool:
        return bool(self.raw_launch)

    @property
    def is_verified(self) -> bool:
        return self.name in VERIFIED

    @property
    def is_local(self) -> bool:
        provider = self.model.split("/", 1)[0] if "/" in self.model else ""
        if not provider:
            return False
        return any(hint in provider for hint in LOCAL_PROVIDER_HINTS)


def default_catalog(*, runner: proc.Runner = proc.run) -> list[str]:
    """The live pi catalog as `provider/model` tokens; empty when pi is absent."""
    result = runner(["pi", "--list-models"])
    if not proc.ok(result):
        return []
    tokens: list[str] = []
    for line in (result.stdout or "").splitlines():
        parts = line.split()
        if len(parts) >= 2:
            tokens.append(f"{parts[0]}/{parts[1]}")
    return tokens


def read_config(config_dir: str | Path | None) -> tuple[str, str, str]:
    """The machine's `config/eindri-harness` line: `<harness> [<model>] [<effort>]`."""
    if not config_dir:
        return "", "", ""
    path = Path(config_dir) / "eindri-harness"
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return "", "", ""
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        fields = stripped.split()
        harness = fields[0] if fields else ""
        model = fields[1] if len(fields) > 1 else ""
        effort = fields[2] if len(fields) > 2 else ""
        if harness == "default":
            harness = ""
        return harness, model, effort
    return "", "", ""


def first_local(tokens: Iterable[str]) -> str:
    """The shell road's heuristic, kept: a served local model id carries `@`."""
    for token in tokens:
        if "@" in token:
            return token
    return ""


def is_assignment(part: str) -> bool:
    head, sep, _ = part.partition("=")
    return bool(sep) and head.isidentifier()


def servable(harness_name: str, model: str, tokens: Sequence[str]) -> bool:
    """Can this harness serve this model on this machine?"""
    if not model or model == "default":
        return True
    if model.endswith("/") or any(marker in model for marker in ("<", " ", "your-model")):
        return False
    return model in tokens


def resolve(
    *,
    harness: str = "",
    model: str = "",
    effort: str = "",
    config_dir: str | Path | None = None,
    env: Mapping[str, str] | None = None,
    catalog: Catalog | None = None,
    runner: proc.Runner = proc.run,
) -> HarnessSelection:
    """Resolve harness, model and effort for one errand, with provenance."""
    environ = dict(env) if env is not None else None
    required = bool(harness) or bool(model)
    raw_launch = harness if " " in harness else ""
    if raw_launch:
        argv0 = next(
            (part for part in raw_launch.split() if not is_assignment(part)),
            raw_launch.split()[0],
        )
        return HarnessSelection(
            name=Path(argv0).name,
            model="",
            effort="",
            provenance="raw launch command (escape hatch)",
            model_provenance="",
            raw_launch=raw_launch,
        )

    prov = "explicit flag (--harness)" if harness else ""
    if not harness:
        cfg_harness, cfg_model, cfg_effort = read_config(
            config_dir if config_dir is not None else paths.resolve(environ).config
        )
        if cfg_harness:
            harness, prov = cfg_harness, "config/eindri-harness (this machine)"
        if not model and cfg_model:
            model = cfg_model
        if not effort and cfg_effort:
            effort = cfg_effort

    tokens = list(catalog()) if catalog is not None else list(default_catalog(runner=runner))

    if not harness:
        if tokens:
            harness, prov = "pi", "fleet law — a local catalog exists, so local -> pi"
        else:
            harness, prov = "opencode", "fleet law — no local catalog, hosted -> opencode"

    model_prov = "explicit flag (--model)" if (required and model) else ""
    if not model and tokens:
        local = first_local(tokens)
        if local and harness in ("pi", "pi-signed"):
            model, model_prov = local, "fleet law — first served local model from the pi catalog"
    if not model:
        model_prov = "none — the harness default is served"

    if model and tokens and not servable(harness, model, tokens):
        raise ValueError(
            f"harness '{harness}' cannot serve model '{model}' on this machine — "
            "resolve a servable token or pass an explicit provider/model"
        )
    return HarnessSelection(
        name=harness,
        model=model,
        effort=effort,
        provenance=prov,
        model_provenance=model_prov,
    )


def launcher_door() -> Path:
    """The ONE launcher generator — bin/seat/pi-launcher.sh, beside the tree's bin/."""
    return Path(__file__).resolve().parents[2] / "bin" / "seat" / "pi-launcher.sh"


def build_launch_command(
    selection: HarnessSelection,
    brief_ref: str,
    launch_cwd: str | Path | None = None,
    *,
    runner: proc.Runner = proc.run,
) -> str:
    """The exact worker line — composed by the ONE generator, never here.

    Measured 2026-11-05 (plan 190 §4.1): this builder and the shell road each
    assembled a pi command, and NEITHER of them carried `-ne` — so a worker
    seated by the engine inherited the seat's absolute extension tree through
    ~/.pi/agent/settings.json AND discovered the worktree's own, pi registered
    every tool twice, refused to load a single extension, and the errand was
    born dead while the dispatcher printed `spawned` (RULES/13). Two launchers for
    one shape is the fault; `bin/seat/pi-launcher.sh` is now the only place the
    shape exists, and both roads ask it.
    """
    if selection.is_raw:
        quoted = proc.shell_quote(brief_ref)
        if "__BRIEF__" in selection.raw_launch:
            return selection.raw_launch.replace("__BRIEF__", quoted)
        return selection.raw_launch

    model_flag = (
        f"--model {proc.shell_quote(selection.model)} "
        if selection.model and selection.model != "default"
        else ""
    )
    if selection.name in ("pi", "pi-signed"):
        door = launcher_door()
        if not door.is_file():
            raise ValueError(
                f"the launcher generator is missing at {door} — a pi seat without it would "
                "load two extension trees and refuse to start (RULES/13)"
            )
        argv = [str(door), "print", str(launch_cwd or Path.cwd())]
        if selection.model and selection.model != "default":
            argv += ["--model", selection.model]
        if selection.effort and selection.effort != "default":
            argv += ["--thinking", selection.effort]
        argv += ["--brief", brief_ref]
        completed = runner(argv)
        if not proc.ok(completed):
            raise ValueError(
                "the launcher generator refused this seat: "
                + ((completed.stderr or completed.stdout or "").strip() or "no reason given")
            )
        return completed.stdout.strip()
    if selection.name == "opencode":
        # `env` is load-bearing, not decoration. The seat writer prefixes `exec ` to
        # any shape that does not already carry it (seat.py), and `exec VAR=x cmd`
        # is not runnable shell — bash looks for a command called
        # `OPENCODE_CONFIG_CONTENT=...`. With `env` the shape is executable BOTH as a
        # plain command and after `exec`, which is why every harness's shape must be
        # self-contained: a launch shape that only works in one caller is a trap.
        return (
            "env OPENCODE_CONFIG_CONTENT="
            + proc.shell_quote('{"permission":{"*":"allow"}}')
            + f' opencode {model_flag}--prompt "$(cat {proc.shell_quote(brief_ref)})"'
        )
    raise ValueError(f"no launch shape for harness '{selection.name}'")
