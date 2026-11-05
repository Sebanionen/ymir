#!/usr/bin/env bash
# hlidskjalf-usage.sh — what the HARNESSES spent, not just the smithy.
#
# The Statistics gate counted only smithy runs (smidja.db), so a machine burning
# tokens through opencode and pi from morning to night reported "No runs yet". The
# sessions are the usage; this reads them.
#
#   bin/desktop/hlidskjalf-usage.sh [--days N]   # JSON, aggregated
#
# SOURCES (verified on this machine):
#   opencode  ~/.local/share/opencode/opencode.db  (SQLite, Drizzle)
#             session / message / part; usage lives in message.data as JSON:
#             {role, modelID, providerID, cost, tokens:{total,input,output,
#              reasoning,cache:{read,write}}}. cost is stored 0 - tokens are truth.
#   pi        ~/.pi/agent/sessions/**/*.jsonl
#
# BOUNDED BY CONSTRUCTION: the db here is 37 GB and holds 132k messages. Nothing
# loads rows into the UI - the aggregation is one SQL statement with json_extract,
# a time window, and a hard row cap, and the result is small by definition.
set -u

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1-}" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

DAYS="${YMIR_USAGE_DAYS:-30}"
while [ $# -gt 0 ]; do
  case "$1" in --days) DAYS="${2:-30}"; shift 2 ;; *) shift ;; esac
done

DAYS="$DAYS" python3 - <<'PY'
import json, os, sqlite3, sys, glob
from datetime import datetime, timedelta, timezone

days = int(os.environ.get("DAYS", "30"))
since_ms = int((datetime.now(timezone.utc) - timedelta(days=days)).timestamp() * 1000)
out = {"window_days": days, "sources": {}, "totals": {}, "by_model": []}

oc = os.path.expanduser("~/.local/share/opencode/opencode.db")
if os.path.exists(oc):
    try:
        c = sqlite3.connect("file:%s?mode=ro" % oc, uri=True)
        c.execute("PRAGMA query_only=ON")
        # One statement, aggregated in the engine: never the rows, only the sums.
        rows = c.execute("""
            select coalesce(json_extract(data,'$.modelID'),'unknown') model,
                   count(*) msgs,
                   sum(coalesce(json_extract(data,'$.tokens.input'),0)) input,
                   sum(coalesce(json_extract(data,'$.tokens.output'),0)) output,
                   sum(coalesce(json_extract(data,'$.tokens.cache.read'),0)) cache_read,
                   sum(coalesce(json_extract(data,'$.tokens.cache.write'),0)) cache_write,
                   sum(coalesce(json_extract(data,'$.tokens.reasoning'),0)) reasoning
            from message
            where json_extract(data,'$.tokens') is not null
              and coalesce(json_extract(data,'$.time.created'), 0) >= ?
            group by model order by (sum(coalesce(json_extract(data,'$.tokens.input'),0))
                                   + sum(coalesce(json_extract(data,'$.tokens.output'),0))) desc
            limit 40
        """, (since_ms,)).fetchall()
        rows = [r for r in rows if r[1]]
        out["sources"]["opencode"] = {
            "model": "harness",
            "messages": sum(r[1] for r in rows),
            "input": sum(r[2] for r in rows), "output": sum(r[3] for r in rows),
            "cache_read": sum(r[4] for r in rows), "cache_write": sum(r[5] for r in rows),
            "reasoning": sum(r[6] for r in rows),
        }
        out["by_model"] += [
            {"source": "opencode", "model": r[0], "messages": r[1], "input": r[2],
             "output": r[3], "cache_read": r[4], "cache_write": r[5], "reasoning": r[6]}
            for r in rows
        ]
    except Exception as e:
        out["sources"]["opencode"] = {"error": str(e)[:120]}

# pi keeps TWO stores: the agent home and the older tree beside it. Scanning only
# one under-reported the harness by an order of magnitude (75 messages against 657
# session files), which is how a "small number" masks a missing source.
pi_files = []
for root in ("~/.pi/agent/sessions", "~/.pi/sessions"):
    pi_files += glob.glob(os.path.expanduser(root + "/**/*.jsonl"), recursive=True)
if pi_files:
    agg = {"input": 0, "output": 0, "cache_read": 0, "cache_write": 0, "messages": 0, "cost": 0.0}
    models = {}
    for f in pi_files:
        try:
            with open(f, "r", errors="ignore") as fh:
                for line in fh:
                    if '"tokens"' not in line and '"usage"' not in line:
                        continue
                    try:
                        d = json.loads(line)
                    except Exception:
                        continue
                    t = d.get("tokens") or d.get("usage") or {}
                    cost_seen = 0
                    # pi nests it one level down: {"type":"message","message":{"usage":{...}}}
                    # with camelCase cache keys. Reading only the top level counted 23
                    # messages where the session files held hundreds of turns.
                    if not t and isinstance(d.get("message"), dict):
                        t = d["message"].get("usage") or {}
                    if not t:
                        continue
                    inp = t.get("input") or t.get("input_tokens") or 0
                    outp = t.get("output") or t.get("output_tokens") or 0
                    cr = (t.get("cache") or {}).get("read") or t.get("cacheRead") or t.get("cache_read_input_tokens") or 0
                    cw = (t.get("cache") or {}).get("write") or t.get("cacheWrite") or t.get("cache_creation_input_tokens") or 0
                    agg["input"] += inp; agg["output"] += outp
                    agg["cache_read"] += cr; agg["cache_write"] += cw; agg["messages"] += 1
                    # The model pi actually used lives one level down, beside the usage:
                    # {"type":"message","message":{"model":"deepseek-v4.1-flash","usage":{...}}}
                    # Reading only the top level filed 92% of the volume under "unknown".
                    msg = d.get("message") if isinstance(d.get("message"), dict) else {}
                    m = d.get("modelID") or d.get("model") or msg.get("model") or "unknown"
                    c = t.get("cost") or {}
                    cost = c.get("total") if isinstance(c, dict) else (c or 0)
                    try:
                        cost = float(cost or 0)
                    except Exception:
                        cost = 0.0
                    agg["cost"] = agg.get("cost", 0.0) + cost
                    mm = models.setdefault(m, {"input": 0, "output": 0, "messages": 0, "cost": 0.0})
                    mm["input"] += inp; mm["output"] += outp; mm["messages"] += 1
                    mm["cost"] = mm.get("cost", 0.0) + cost
        except Exception:
            continue
    out["sources"]["pi"] = {"model": "harness", **agg}
    out["by_model"] += [{"source": "pi", "model": k, **v} for k, v in
                        sorted(models.items(), key=lambda kv: -(kv[1]["input"] + kv[1]["output"]))[:20]]

tot = {"messages": 0, "input": 0, "output": 0, "cache_read": 0, "cache_write": 0, "reasoning": 0, "cost": 0.0}
for s in out["sources"].values():
    for k in tot:
        tot[k] += int(s.get(k) or 0)
tot["total"] = tot["input"] + tot["output"]
prompt = tot["input"] + tot["cache_read"]
# local = our own hardware; online = a cloud API. By model id, honestly.
LOCAL_MARKERS = ("llama", "lmstudio", "ollama", "local")
# The registry is the truth: a model served by llama-swap or a llama.cpp seat is OUR
# hardware, whatever its id sounds like. Measured 2026-11-05: 245M tokens of pi work
# were reported as "online" because the id `deepseek-v4.1-flash` matched no marker.
LOCAL_MODELS = set()
LOCAL_PROVIDERS = set()
try:
    reg = json.load(open(os.path.expanduser("~/.pi/agent/models.json")))
    for provider, spec in (reg.get("providers") or {}).items():
        if not isinstance(spec, dict):
            continue
        if any(k in provider.lower() for k in ("llama", "local", "ollama", "lmstudio")):
            LOCAL_PROVIDERS.add(provider)
            ms = spec.get("models") or []
            # pi's registry carries models as a LIST of {id,…}; a dict is accepted too.
            entries = ms if isinstance(ms, list) else list(ms.keys())
            for e in entries:
                name = e.get("id") or e.get("name") if isinstance(e, dict) else e
                if name:
                    LOCAL_MODELS.add(str(name))
                    if str(name).endswith("-fast"):
                        LOCAL_MODELS.add(str(name)[:-5])
except Exception:
    pass
for m in out["by_model"]:
    mid = str(m.get("model", ""))
    m["kind"] = "local" if (mid in LOCAL_MODELS or any(k in mid.lower() for k in LOCAL_MARKERS)) else "online"

def _empty():
    return {"tokens": 0, "calls": 0, "input": 0, "output": 0, "cache_read": 0}
lo = {"local": _empty(), "online": _empty()}
for m in out["by_model"]:
    k = m.get("kind", "online")
    lo[k]["tokens"] += int(m.get("input") or 0) + int(m.get("output") or 0)
    lo[k]["calls"] += int(m.get("messages") or 0)
    lo[k]["input"] += int(m.get("input") or 0)
    lo[k]["output"] += int(m.get("output") or 0)
    lo[k]["cache_read"] += int(m.get("cache_read") or 0)
out["local_online"] = lo

# the gate's section names, filled from the harnesses
oc = out["sources"].get("opencode", {})
pi = out["sources"].get("pi", {})
out["runs"] = {
    "total": int(tot["messages"]), "success": int(tot["messages"]), "fail": 0, "running": 0,
    "success_rate": 100.0 if tot["messages"] else 0.0,
    "tokens": int(tot["input"]) + int(tot["output"]),
    "cost": round(float(tot.get("cost") or 0), 6),
    "by_source": {"opencode": int(oc.get("messages") or 0), "pi": int(pi.get("messages") or 0)},
}
out["by_chain"] = [
    {"chain": m.get("source", "harness"), "workflow": m.get("source", "harness"),
     "runs": int(m.get("messages") or 0), "success": int(m.get("messages") or 0),
     "rate": 100.0, "tokens": int(m.get("input") or 0) + int(m.get("output") or 0), "cost": round(float(m.get("cost") or 0), 6)}
    for m in out["by_model"][:12]
]

tot["cache_hit_ratio"] = round(tot["cache_read"] / prompt, 4) if prompt else 0.0
out["totals"] = tot

# THE GATE'S OWN NAMES, filled from the harnesses - so Statistics reports pi and
# opencode, and the smithy's runs stay the smithy's.
out["gate"] = {
    "totals": {
        "runs": int(tot["messages"]), "success": int(tot["messages"]), "fail": 0,
        "running": 0, "tokens": int(tot["input"]) + int(tot["output"]), "cost": round(float(tot.get("cost") or 0), 6),
    },
    "usage": {
        "input": int(tot["input"]), "output": int(tot["output"]),
        "cache_read": int(tot["cache_read"]), "cache_write": int(tot["cache_write"]),
        "total": int(tot["input"]) + int(tot["output"]),
    },
    "providers": {
        "local":  {"events": lo["local"]["calls"],  "sessions": lo["local"]["calls"],
                   "tokens": lo["local"]["tokens"],  "cost": 0,
                   "input": lo["local"]["tokens"],  "output": 0, "cache_read": 0},
        "online": {"events": lo["online"]["calls"], "sessions": lo["online"]["calls"],
                   "tokens": lo["online"]["tokens"], "cost": 0,
                   "input": lo["online"]["input"],  "output": lo["online"]["output"], "cache_read": lo["online"]["cache_read"]},
        "per_model": [
            {"model": m["model"], "agent": m.get("source", "harness"), "kind": m.get("kind", "online"),
             "cells": int(m.get("messages") or 0), "tokens": int(m.get("input") or 0) + int(m.get("output") or 0), "cost": round(float(m.get("cost") or 0), 6)}
            for m in out["by_model"]
        ],
    },
    "by_chain": out["by_chain"],
    "by_model": [
        {"model": m["model"], "agent": m.get("source", "harness"), "kind": m.get("kind", "online"),
         "cells": int(m.get("messages") or 0),
         "tokens": int(m.get("input") or 0) + int(m.get("output") or 0), "cost": round(float(m.get("cost") or 0), 6)}
        for m in out["by_model"]
    ],
}

print(json.dumps(out))
PY
