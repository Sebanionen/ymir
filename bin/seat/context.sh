#!/usr/bin/env bash
# context.sh — what the agent's context ACTUALLY holds, right now.
#
#   bin/seat/context.sh [--json] [--session FILE] [--window N]
#
# Why this exists: an agent that guesses its own context either stops work it could
# finish or keeps going past the window and is truncated mid-sentence. The number is
# already on disk — pi writes `usage` on every assistant turn — so this door reads it
# and prints the truth: used · window · remaining · the compaction thresholds · and
# whether a compaction has already fired in this session.
#
# The window comes from bin/seat/core-four.sh (which asks the provider registry, or the
# model catalog for a hosted model). No second table of windows exists here.
set -u
JSON=0; SESSION=""; WINDOW=""
while [ $# -gt 0 ]; do case "$1" in
  --json) JSON=1; shift ;;
  --session) SESSION="${2-}"; shift 2 ;;
  --window) WINDOW="${2-}"; shift 2 ;;
  *) shift ;;
esac; done
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

if [ -z "$SESSION" ]; then
  SESSION="${PI_SESSION_FILE:-}"
fi
if [ -z "$SESSION" ]; then
  SESSION="$(ls -t "$HOME"/.pi/agent/sessions/*/*.jsonl 2>/dev/null | head -1)"
fi
[ -n "$SESSION" ] && [ -r "$SESSION" ] || { printf 'context: no session file found (looked in ~/.pi/agent/sessions/)\n' >&2; exit 2; }

if [ -z "$WINDOW" ]; then
  WINDOW="$(bash "$ROOT/bin/seat/core-four.sh" --json 2>/dev/null | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["context"]["window"])
except Exception: print(0)')"
fi

python3 - "$SESSION" "$WINDOW" "$JSON" "$ROOT" <<'PY'
import json, os, subprocess, sys

session, window, as_json, root = sys.argv[1], int(sys.argv[2] or 0), sys.argv[3] == "1", sys.argv[4]

last = None            # the last assistant usage
turns = 0
compactions = 0
model = ""
finish = ""
with open(session, errors="ignore") as fh:
    for line in fh:
        if '"usage"' not in line and 'compact' not in line.lower():
            continue
        try:
            d = json.loads(line)
        except Exception:
            continue
        blob = json.dumps(d)
        if "compact" in blob.lower():
            compactions += 1
        msg = d.get("message") if isinstance(d.get("message"), dict) else d
        u = (d.get("usage") or (msg.get("usage") if isinstance(msg, dict) else None))
        if not isinstance(u, dict):
            continue
        turns += 1
        last = u
        model = (msg.get("model") or d.get("model") or model) if isinstance(msg, dict) else model
        finish = (msg.get("stopReason") or msg.get("finishReason") or finish) if isinstance(msg, dict) else finish

if not last:
    print("context: this session carries no usage yet — nothing has been sent", file=sys.stderr)
    sys.exit(1)

inp = int(last.get("input") or 0)
cache_r = int(last.get("cacheRead") or 0)
out = int(last.get("output") or 0)
used = inp + cache_r + out
# thresholds: the same two the status bar names (auto / force)
auto = int(window * 0.5) if window else 0
force = int(window * 0.75) if window else 0

def pct(n):
    return round(100.0 * n / window, 1) if window else 0.0

data = {
    "session": os.path.basename(session),
    "model": model or "?",
    "turns": turns,
    "context_used": used,
    "window": window,
    "percent": pct(used),
    "remaining": max(window - used, 0) if window else 0,
    "auto_compact_at": auto,
    "force_compact_at": force,
    "compactions_seen": compactions,
    "last_finish": finish or "-",
    "verdict": ("TRUNCATED — the last turn ended on the length limit" if str(finish).lower() in ("length", "max_tokens", "max-tokens")
                else "near the window — compact now" if window and used >= force
                else "past the auto threshold" if window and used >= auto
                else "room to work"),
}
if as_json:
    print(json.dumps(data))
else:
    print(f'context[8]{{field,value}}:')
    print(f'  "session","{data["session"]}"')
    print(f'  "model","{data["model"]}"')
    print(f'  "turns","{data["turns"]}"')
    print(f'  "used","{used:,} tokens · {data["percent"]}% of {window:,}"')
    print(f'  "remaining","{data["remaining"]:,}"')
    print(f'  "thresholds","auto {auto:,} · force {force:,}"')
    print(f'  "compactions seen","{compactions}"')
    print(f'  "verdict","{data["verdict"]}"')
PY
