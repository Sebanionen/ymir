"""common.py — the one resolver for Garmr's settings and paths (Rule 07).

Nothing here forks a second opinion about where the home is: it asks the same
environment the rest of the house asks, falls back to the repo's example, then to
the built-in defaults, and reports which source each value came from.
"""
from __future__ import annotations

import json
import os
import socket
import time

DEFAULTS = {
    "seat": "",
    "hound": {
        "findings": "/var/log/ymir/garmr/findings.jsonl",
        "audit_log": "/var/log/audit/audit.log",
        "poll_seconds": 60,
        "doors_seconds": 300,
        "max_bytes": 5 * 1024 * 1024,
    },
    "allow": {
        "sensitive_readers": [],
        "program_dirs": ["/usr/", "/opt/", "/bin/", "/sbin/", "/nix/"],
        "writable_dirs": ["/tmp/", "/var/tmp/", "/dev/shm/"],
        "listen_ports": [],
        "peer_hosts": ["127.0.0.1", "::1"],
    },
    "alert": {"desktop": True, "phone": "none"},
    "escalate": {
        "medium": "local",
        "high": "local-or-fleet",
        "critical": "online",
        "fleet": [],
        # Empty means RESOLVE on this seat (bin/model/agent-model.sh); a literal here would be
        # a promise another machine cannot keep (RULES/25, plan 206 §11).
        "local": "",
        "online": "",
        "on": "high",
        "announce_eviction": True,
        "degrade_loudly": True,
        "budget": {"online_calls_per_day": 0, "online_usd_per_day": 0},
    },
    "integrity": {"nightly": True, "watch": ["RULES/", "bin/ward/"]},
}


def repo_root() -> str:
    """The ymir checkout: this file lives at <root>/bin/ward/garmr/common.py."""
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.abspath(os.path.join(here, "..", "..", ".."))


def ymir_home() -> str:
    """Resolve the hoard, never assume it (Rule 07/25).

    The one owner of that answer is `bin/vault/hoard-lib.sh`; ask it, then fall back
    to the environment, and only then to a documented default.
    """
    env = os.environ.get("YMIR_HOME")
    if env:
        return os.path.expanduser(env)
    lib = os.path.join(repo_root(), "bin", "vault", "hoard-lib.sh")
    if os.path.isfile(lib):
        try:
            import subprocess
            out = subprocess.run(
                ["bash", "-c",
                 f'. "{lib}" >/dev/null 2>&1; out=""; ymir_home_root out 2>/dev/null; printf "%s" "$out"'],
                capture_output=True, text=True, timeout=10).stdout.strip()
            if out and os.path.isdir(out):
                return out
        except Exception:
            pass
    # No guessed home: if neither the env nor the resolver answers, say so rather
    # than invent a path (defaults-guard; Rule 07/25 — one resolver, one default).
    raise SystemExit("garmr: the hoard is unresolved — set YMIR_HOME or run from a checkout "
                     "whose bin/vault/hoard-lib.sh can answer")


def state_dir() -> str:
    env = os.environ.get("GARMR_STATE_DIR")
    if env:
        return os.path.expanduser(env)
    return os.path.join(ymir_home(), "hodd", "state", "garmr")


def pause_marker() -> str:
    """The pause marker is ROOT's, so no ordinary process can silence the hound."""
    env = os.environ.get("GARMR_PAUSE_MARKER")
    if env:
        return os.path.expanduser(env)
    return "/var/log/ymir/garmr/PAUSED"


def config_path() -> str:
    env = os.environ.get("GARMR_CONFIG")
    if env:
        return os.path.expanduser(env)
    home_cfg = os.path.join(ymir_home(), "config", "guardian.yaml")
    if os.path.isfile(home_cfg):
        return home_cfg
    return os.path.join(repo_root(), "config", "guardian.yaml.example")


def _merge(base: dict, over: dict) -> dict:
    out = dict(base)
    for key, value in (over or {}).items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key] = _merge(out[key], value)
        else:
            out[key] = value
    return out


def load_config() -> dict:
    path = config_path()
    data: dict = {}
    try:
        import yaml  # PyYAML is on this box; degrade quietly if a seat lacks it

        with open(path) as handle:
            data = yaml.safe_load(handle) or {}
    except Exception:
        data = {}
    merged = _merge(DEFAULTS, data if isinstance(data, dict) else {})
    merged["seat"] = merged.get("seat") or socket.gethostname()
    merged["_config_path"] = path
    return merged


def now_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%S%z")


def emit(obj: dict) -> str:
    return json.dumps(obj, ensure_ascii=False, sort_keys=True)


def rotate(path: str, max_bytes: int) -> None:
    """Past the cap, MOVE the file aside — never truncate (Rule 11: never delete)."""
    try:
        if max_bytes and os.path.getsize(path) >= max_bytes:
            stamp = time.strftime("%Y%m%dT%H%M%SZ")
            os.rename(path, f"{path[:-6]}.{stamp}.jsonl" if path.endswith(".jsonl") else f"{path}.{stamp}")
    except OSError:
        pass


def prune_rotations(path: str, keep: int) -> int:
    """Keep the newest `keep` rotated siblings; RETIRE the older ones.

    Written 2026-10-31 at the Allfather's word: *"we cant store 20gb of findings for ever"*.
    The rotation it complements only ever MOVED a file aside (Rule 11: never truncate, never
    lose a record), so a noisy audit source grew without bound — 3,960 rotated files, 20 GB,
    and a hound spending a quarter of a core reading it. This is the retention that rotation
    was missing.

    The distinction these two rules draw, and the reason both can be true at once:

      * the RECORDS this house keeps by law — the runes ledger, the well, plans, fixes, the
        hoard — are APPEND-ONLY and are never retired by a sweeper (RULES/06, RULES/20);
      * the OBSERVATION LOG is not a record but a sensor trace, and a sensor trace without
        a retention policy is a disk that fills and a CPU that never idles.

    Retention is bounded and declared (`hound.keep_rotations`), never silent: it returns how
    many files were retired so a caller can say so, and it never touches the live file.
    """
    if keep is None or int(keep) <= 0:
        return 0
    directory = os.path.dirname(path) or "."
    stem = os.path.basename(path)
    prefix = stem[:-6] if stem.endswith(".jsonl") else stem
    try:
        siblings = sorted(
            (os.path.join(directory, name) for name in os.listdir(directory) if name.startswith(prefix) and name != stem),
            key=lambda p: os.path.getmtime(p),
            reverse=True,
        )
    except OSError:
        return 0
    retired = 0
    for stale in siblings[max(0, int(keep)):]:
        try:
            os.unlink(stale)
            retired += 1
        except OSError:
            continue
    return retired


def heartbeat(state: str, name: str = "hound") -> None:
    os.makedirs(state, exist_ok=True)
    with open(os.path.join(state, f"{name}.heartbeat"), "w") as handle:
        handle.write(now_iso())


def append_findings(path: str, rows: list[dict]) -> None:
    if not rows:
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a") as handle:
        for row in rows:
            handle.write(emit(row) + "\n")
