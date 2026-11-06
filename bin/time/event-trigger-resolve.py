#!/usr/bin/env python3
"""event-trigger-resolve — who may start a smithy, and when.

The smithy's config carries a `trigger:` block. This resolver is the ONE reader
of it; `bin/time/event-trigger.sh` is the door that acts on what it says. Two
readers of one block is how a schedule says one thing and a launcher does
another, so nothing else parses `trigger:`.

    event-trigger-resolve.py scan            every smithy config it can find
    event-trigger-resolve.py one <config>    one config, named or refused

Output is one line per config, tab-separated, empty fields as `-`:

    config  root  mode  cron  timezone  event  chain  prompt  role  error

A config with no `trigger:` block is **manual** — absent is not armed, and this
file exists so that absence can never be read as "some default nobody wrote".

Discovery: `SMIDJA_CONFIGS` (colon-separated explicit paths) when set, else
`SMIDJA_ROOTS` (colon-separated roots, default the checkout this file lives in)
scanned for the smithy's two documented homes — `smidja/smidja_*_config/` in a
stamped repo, and `apps/<name>/smidja_*_config/` in this one.

Exit: 0 the scan ran (rows may still carry an error — the door names it),
      1 a config could not be read at all, 2 usage.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

COLUMNS = ("config", "root", "mode", "cron", "timezone", "event",
           "chain", "prompt", "role", "error")
MODES = ("manual", "cron", "event")
ROLES = ("heart", "forge", "dev", "hand")


def _yaml():
    try:
        import yaml  # noqa: PLC0415 — a named refusal beats an import traceback
    except ImportError:  # pragma: no cover
        sys.stderr.write(
            'yaml[1]{missing,why}:\n'
            '  "pyyaml","the smithy config is YAML and this python has no reader — install pyyaml"\n')
        raise SystemExit(1)
    return yaml


def config_root(config: Path) -> Path:
    """The repo root a config's paths are relative to.

    A smithy config's `data_dir`, `chain` and `prompt` are all root-relative
    (RULES/36 §4), so the root is the first ancestor that is a git work tree.
    `SMIDJA_REPO_ROOT` wins when the caller knows better.
    """
    known = os.environ.get("SMIDJA_REPO_ROOT", "").strip()
    if known:
        return Path(known).resolve()
    for candidate in [config.parent, *config.parents]:
        if (candidate / ".git").exists():
            return candidate
    return config.parent


def discover() -> list[Path]:
    explicit = os.environ.get("SMIDJA_CONFIGS", "").strip()
    if explicit:
        candidates = [Path(p) for p in explicit.split(":") if p.strip()]
    else:
        here = Path(__file__).resolve()
        default_root = here.parents[2]
        roots = [Path(p) for p in os.environ.get("SMIDJA_ROOTS", "").split(":") if p.strip()]
        candidates = []
        for root in roots or [default_root]:
            candidates += sorted(root.glob("smidja/smidja_*_config/*.yaml"))
            candidates += sorted(root.glob("apps/*/smidja_*_config/*.yaml"))
    seen, out = set(), []
    for path in candidates:
        resolved = path.resolve()
        if resolved in seen or not resolved.is_file():
            continue
        seen.add(resolved)
        out.append(resolved)
    return out


def read_trigger(config: Path) -> list[str]:
    """Return the COLUMNS row for one config. Never raises on a bad block."""
    yaml = _yaml()
    row = {name: "-" for name in COLUMNS}
    row["config"] = str(config)
    row["root"] = str(config_root(config))

    try:
        document = yaml.safe_load(config.read_text(encoding="utf-8")) or {}
    except Exception as exc:  # a config that will not parse is named, not skipped
        row["error"] = f"unreadable: {type(exc).__name__}: {exc}".replace("\t", " ")
        return [row[name] for name in COLUMNS]

    if not isinstance(document, dict):
        row["error"] = "not a mapping at the top level"
        return [row[name] for name in COLUMNS]

    block = document.get("trigger")
    if block is None:
        row["mode"] = "manual"          # absent is manual: nothing is armed by surprise
        return [row[name] for name in COLUMNS]

    if isinstance(block, str):          # the short form: `trigger: manual`
        block = {"mode": block}
    if not isinstance(block, dict):
        row["error"] = "trigger: is neither a name nor a mapping"
        return [row[name] for name in COLUMNS]

    mode = str(block.get("mode", "manual")).strip() or "manual"
    row["mode"] = mode
    for key in ("cron", "timezone", "event", "chain", "prompt", "role"):
        value = block.get(key)
        if value is not None and str(value).strip():
            row[key] = str(value).strip().replace("\t", " ")

    if mode not in MODES:
        row["error"] = f"mode {mode!r} is not one of {'|'.join(MODES)}"
    elif mode == "cron" and row["cron"] == "-":
        row["error"] = "mode cron names no cron expression"
    elif mode == "cron" and row["role"] == "-":
        row["error"] = ("mode cron names no role — an ungated row runs on every seat of "
                        "every machine, so say trigger.role: heart|forge|dev|hand")
    elif mode == "event" and row["event"] == "-":
        row["error"] = "mode event names no event"
    elif row["role"] != "-" and row["role"] not in ROLES:
        row["error"] = f"role {row['role']!r} is not one of {'|'.join(ROLES)}"
    return [row[name] for name in COLUMNS]


def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        sys.stderr.write(__doc__)
        return 0 if len(argv) >= 2 else 2

    action = argv[1]
    if action == "scan":
        paths = discover()
        if not paths:
            sys.stderr.write(
                'smithy[0]{say}:\n'
                '  "no smithy config was found — set SMIDJA_CONFIGS or SMIDJA_ROOTS"\n')
            return 1
        for path in paths:
            print("\t".join(read_trigger(path)))
        return 0

    if action == "one":
        if len(argv) < 3:
            sys.stderr.write("usage: event-trigger-resolve.py one <config>\n")
            return 2
        config = Path(argv[2])
        if not config.is_file():
            sys.stderr.write(f'config "{config}": not a file\n')
            return 1
        print("\t".join(read_trigger(config.resolve())))
        return 0

    sys.stderr.write(f"unknown action {action!r} — scan | one\n")
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
