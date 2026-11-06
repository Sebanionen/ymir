"""escalate.py — the severity ladder (plan 98 §'the severity ladder').

    escalate.py --finding <json> [--severity CRITICAL] [--dry-run]

Ladder, as the Allfather set it:
    medium      -> the local MTP            (qwen3.6-35b-a3b@q4_k_xl-mtp, this rail)
    high        -> the local MTP, or a fleet rail when it would evict his model
    critical    -> deepseek-v4.1-flash      (opencode-go, online)
    unreachable -> down the ladder, LOUDLY: the caller is told it reasoned alone.

The payload is redacted by redact.py before it leaves: argv redacted, sensitive
paths hashed, no content. Nothing sensitive is ever sent.

Exit: 0 an answer · 1 no rung could answer · 2 usage.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

PI_DIR = os.path.expanduser("~/.pi/agent")


def _read_json(path: str) -> dict:
    try:
        with open(path) as handle:
            return json.load(handle) or {}
    except Exception:
        return {}


def _auth_key(provider: str) -> str:
    return ((_read_json(os.path.join(PI_DIR, "auth.json")).get(provider) or {}).get("key") or "")


def _provider_base(provider: str) -> str:
    override = os.environ.get("GARMR_ESCALATE_BASE")
    if override:
        return override.rstrip("/")
    for name in ("models.json", "models-store.json"):
        data = _read_json(os.path.join(PI_DIR, name))
        providers = data.get("providers") or data
        entry = providers.get(provider) or {}
        base = entry.get("baseUrl") or entry.get("base_url")
        if base:
            return base.rstrip("/")
    return ""


def _budget_path() -> str:
    return os.path.join(common.state_dir(), "budget.json")


def _budget_allow(cfg: dict) -> bool:
    limits = (cfg.get("escalate", {}).get("budget") or {})
    per_day = int(limits.get("online_calls_per_day", 0) or 0)
    if per_day <= 0:
        return False
    today = time.strftime("%Y-%m-%d")
    state = _read_json(_budget_path()) or {}
    if state.get("date") != today:
        state = {"date": today, "calls": 0}
    if state.get("calls", 0) >= per_day:
        return False
    state["calls"] = state.get("calls", 0) + 1
    os.makedirs(common.state_dir(), exist_ok=True)
    with open(_budget_path(), "w") as handle:
        json.dump(state, handle)
    return True


def rungs_for(severity: str, cfg: dict) -> list[str]:
    esc = cfg.get("escalate", {})
    level = severity.upper()
    if level == "CRITICAL":
        first = esc.get("critical", "online")
        order = [first, "online", "local", "fleet"]
    elif level == "HIGH":
        first = esc.get("high", "local-or-fleet")
        order = ["fleet", "local"] if first == "local-or-fleet" else [first, "fleet", "local"]
    else:
        first = esc.get("medium", "local")
        order = ["local", "fleet"] if first == "local" else [first, "local"]
    seen, out = set(), []
    for rung in order:
        if rung in ("local", "fleet", "online") and rung not in seen:
            seen.add(rung)
            out.append(rung)
    return out


def payload(finding: dict, context: list[dict]) -> str:
    """The redacted timeline: shape without content (plan 98 redaction law)."""
    lines = []
    for row in context[-40:]:
        lines.append(json.dumps({
            "ts": row.get("ts"), "kind": row.get("kind"), "comm": row.get("comm"),
            "pid": row.get("pid"), "uid": row.get("uid"), "target": row.get("target"),
            "argv": row.get("argv"), "peer": row.get("peer"), "addr": row.get("addr"),
        }, sort_keys=True))
    lines.append(json.dumps(finding, sort_keys=True))
    text = "\n".join(lines)
    return text[:4096]


SYSTEM = (
    "You are the reasoner a home guardian wakes for a serious security finding. "
    "You receive a REDACTED timeline: no file contents, no secrets, hashed sensitive "
    "paths. Say in at most three sentences what most likely happened, how confident "
    "you are, and the one next check a human should run. If the evidence is thin, say "
    "so plainly instead of inventing a story."
)


def _resolve(tier: str) -> str:
    """The seat's own answer to "which model", never a literal in this file (RULES/25)."""
    root = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
    door = os.path.join(root, "bin", "model", "agent-model.sh")
    try:
        out = subprocess.run(["bash", door, "forseti", "--tier", tier, "--plain"],
                             capture_output=True, text=True, timeout=25)
        return out.stdout.strip() if out.returncode == 0 else ""
    except Exception:
        return ""


def ask(rung: str, cfg: dict, body: str) -> dict | None:
    esc = cfg.get("escalate", {})
    if rung == "online":
        if not _budget_allow(cfg):
            return None
        spec = str(esc.get("online") or _resolve("fast")).split("/", 1)
        provider, model = (spec + [""])[:2]
        ordering = [provider]
    elif rung == "local":
        provider, model = "llama-swap", str(esc.get("local") or _resolve("local"))
        ordering = ["llama-swap"]
    else:
        model = str(esc.get("local", ""))
        ordering = [p for p in (esc.get("fleet") or []) if p]
    for provider in ordering:
        base = _provider_base(provider)
        key = _auth_key(provider)
        if not base or not key:
            continue
        request = json.dumps({
            "model": model,
            "messages": [{"role": "system", "content": SYSTEM}, {"role": "user", "content": body}],
            "max_tokens": 220,
            "temperature": 0,
        }).encode()
        req = urllib.request.Request(
            f"{base}/chat/completions", data=request,
            headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"})
        try:
            timeout = int(os.environ.get("GARMR_ESCALATE_TIMEOUT", "120"))
            with urllib.request.urlopen(req, timeout=timeout) as response:
                data = json.load(response)
            text = (data.get("choices") or [{}])[0].get("message", {}).get("content", "").strip()
            if text:
                return {"rung": rung, "provider": provider, "model": model, "text": text}
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, ValueError, KeyError):
            continue
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Garmr's severity ladder")
    parser.add_argument("--finding", required=True, help="a finding as JSON, or @file")
    parser.add_argument("--severity")
    parser.add_argument("--context", help="extra findings as JSON lines (@file)")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    cfg = common.load_config()
    raw = args.finding
    finding = _read_json(raw[1:]) if raw.startswith("@") else json.loads(raw)
    context = []
    if args.context:
        ctx_raw = args.context[1:] if args.context.startswith("@") else args.context
        if os.path.isfile(ctx_raw):
            context = [_read_json_line(line) for line in open(ctx_raw) if line.strip()]
        else:
            context = [json.loads(line) for line in ctx_raw.splitlines() if line.strip()]
    severity = (args.severity or finding.get("severity") or "HIGH").upper()
    body = payload(finding, context)

    for rung in rungs_for(severity, cfg):
        if args.dry_run:
            print(f"rung={rung} model={cfg.get('escalate', {}).get('local' if rung != 'online' else 'online')}")
            return 0
        answer = ask(rung, cfg, body)
        if answer:
            print(common.emit({**answer, "severity": severity, "payload_bytes": len(body)}))
            return 0

    # Degrade loudly: the caller must know it reasoned alone.
    if cfg.get("escalate", {}).get("degrade_loudly", True):
        print(common.emit({"rung": "rules", "severity": severity, "text": "",
                           "degraded": True,
                           "reason": "no rung could answer; the template stands alone"}))
    return 1


def _read_json_line(line: str) -> dict:
    try:
        return json.loads(line)
    except ValueError:
        return {}


if __name__ == "__main__":
    sys.exit(main())
