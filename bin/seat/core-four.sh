#!/usr/bin/env bash
# core-four.sh — the four dials that decide an agent's outcome, in ONE read.
#
#   bin/seat/core-four.sh [--json]
#
# context  the model's window and how much of it a session may use before compaction
# model    what the seat is actually set to (agent config, then the portable catalog)
# prompt   which instruction files are in force (AGENTS.md, skills index, the home contract)
# tools    how many doors the harness has, by source (extensions · MCP)
#
# Why: the four dials live in four files and three shelves, so an operator tunes three and
# never sees the fourth. This is the read that makes them one thing (plan 199 §5).
set -u
JSON=0
[ "${1-}" = "--json" ] && JSON=1
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
ymir_home_root HOME_DIR 2>/dev/null || { printf "%s: the home is unresolved — call bin/vault/hoard-lib.sh\n" "$(basename "$0")" >&2; exit 2; }

python3 - "$ROOT" "$HOME_DIR" "$JSON" <<'PY'
import json, os, re, sys, glob

root, home, as_json = sys.argv[1], sys.argv[2], sys.argv[3] == "1"

def read(p, limit=200000):
    try:
        return open(p, encoding="utf-8", errors="ignore").read()[:limit]
    except Exception:
        return ""

# --- model: the seat's configured agent, then the catalog line -------------
model = ""
provider = ""
t = read(os.path.expanduser("~/.pi/agent/settings.json"))
if t:
    try:
        st = json.loads(t)
        model = (st.get("defaultModel") or "").strip()
        provider = (st.get("defaultProvider") or "").strip()
        if provider and model:
            model = f"{provider}/{model}"
    except Exception:
        pass
for p in (() if model else (os.path.expanduser("~/.pi/agent/settings.json"),
          os.path.join(home, "config", "agents.yaml"))):
    t = read(p)
    if not t:
        continue
    m = re.search(r'"model"\s*:\s*"([^"]+)"', t) or re.search(r'^\s*model:\s*["\']?([^"\'\n]+)', t, re.M)
    if m:
        model = m.group(1).strip()
        break

# --- context: window and compaction thresholds -----------------------------
window, autocomp, force = 0, 0, 0
t = read(os.path.expanduser("~/.pi/agent/models.json"))
if t:
    try:
        reg = json.loads(t)
        mid = model.split("/")[-1]
        for prov in (reg.get("providers") or {}).values():
            for e in (prov.get("models") or []):
                if isinstance(e, dict) and e.get("id") == mid:
                    window = int(e.get("contextWindow") or 0)
                    break
            if window:
                break
    except Exception:
        pass
# The provider may not be in models.json (a hosted catalog). The catalog door knows.
if not window and model:
    import subprocess
    try:
        out = subprocess.run(["bash", os.path.join(root, "bin/model/catalog.sh")],
                             capture_output=True, text=True, timeout=60).stdout
        prov, mid = (model.split("/", 1) + [""])[:2]
        for line in out.splitlines():
            cells = [c.strip().strip('"') for c in line.strip().strip(",").split(",")]
            if len(cells) >= 3 and cells[0].strip('"') == prov and cells[1].strip('"').endswith(mid):
                raw = cells[2].replace("M", "000000").replace("K", "000").replace(".", "")
                digits = "".join(ch for ch in raw if ch.isdigit())
                window = int(digits) if digits else 0
                break
    except Exception:
        pass

extra = os.path.join(home, "config", "agent-runtime.env")
t = read(extra)
if t:
    for k, name in (("AUTO_COMPACT_AT", "autocomp"), ("FORCE_COMPACT_AT", "force")):
        m = re.search(rf"^{k}=(\d+)", t, re.M)
        if m:
            if name == "autocomp": autocomp = int(m.group(1))
            else: force = int(m.group(1))
if not autocomp and window:
    autocomp = int(window * 0.5)
if not force and window:
    force = int(window * 0.75)

# --- prompt: which instruction surfaces are in force ------------------------
prompts = []
for rel, label in (("AGENTS.md", "the repo contract"),
                   ("RULES/README.md", "the numbered rules"),
                   (".agents/skills/README.md", "the skill index"),
                   (".pi/extensions/README.md", "the extension shelf")):
    p = os.path.join(root, rel)
    if os.path.exists(p):
        prompts.append({"file": rel, "what": label, "lines": read(p).count("\n") + 1})
for rel, label in (("AGENTS.md", "the home contract"),):
    p = os.path.join(home, rel)
    if os.path.exists(p):
        prompts.append({"file": f"$YMIR_HOME/{rel}", "what": label, "lines": read(p).count("\n") + 1})

# --- tools: how many doors, by source --------------------------------------
ext = len(glob.glob(os.path.join(root, ".pi", "extensions", "*.ts")))
mcp = 0
for p in (os.path.expanduser("~/.pi/agent/mcp-adapter.json"),):
    t = read(p)
    if t:
        try:
            mcp = len((json.loads(t).get("mcpServers") or {}))
        except Exception:
            mcp = 0

# --- working now: live agents and panes holding a run (plan 199's metric) ----
working = {"agents": 0, "panes": 0, "states": {}}
try:
    import subprocess
    raw = subprocess.run(["herdr", "agent", "list"], capture_output=True, text=True, timeout=20).stdout
    agents = (json.loads(raw).get("result") or {}).get("agents") or []
    working["panes"] = len(agents)
    for a in agents:
        st = a.get("agent_status") or "unknown"
        working["states"][st] = working["states"].get(st, 0) + 1
        if st in ("working", "idle"):
            working["agents"] += 1
except Exception:
    pass

out = {
    "working_now": working,
    "model": model or "unset",
    "context": {"window": window, "auto_compact_at": autocomp, "force_compact_at": force},
    "prompt": prompts,
    "tools": {"extensions": ext, "mcp_servers": mcp, "total": ext + mcp},
}
if as_json:
    print(json.dumps(out))
else:
    c = out["context"]
    print(f'core_four[4]{{dial,value}}:')
    print(f'  "model","{out["model"]}"')
    print(f'  "context","window {c["window"] or "?"} · auto-compact {c["auto_compact_at"] or "?"} · force {c["force_compact_at"] or "?"}"')
    print(f'  "prompt","{len(out["prompt"])} surfaces: ' + ", ".join(p["file"] for p in out["prompt"]) + '"')
    print(f'  "tools","{out["tools"]["extensions"]} extensions · {out["tools"]["mcp_servers"]} MCP servers"')
    w = out["working_now"]
    print(f'  "working now","{w["agents"]} agents standing in {w["panes"]} panes"')
PY
