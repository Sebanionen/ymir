#!/usr/bin/env bash
# hermes-seat.sh — seat Ymir's tools into Hermes, the same packets the other harnesses get.
#
#   bin/seat/hermes-seat.sh            seat (idempotent)
#   bin/seat/hermes-seat.sh --check    exit 1 when Hermes lacks a packet
#
# WHY (the Allfather, 2026-11-03): *"hermes should also be one of the harnesses we
# support like pi, claude, opencode etc … so hermes gets all the tools needed from
# ymir installed."* Hermes is an adopted worker runtime with its own brain, memory and
# subagents; without Ymir's MCP packets it cannot see the well, the tickets, the
# recordings, the memory or the mesh.
#
# ONE LIST. The packets are read from the same source every harness uses —
# `~/.pi/agent/mcp-adapter.json` — so a door added once is seated everywhere, never a
# second list that drifts. Hermes' own config is plain YAML; `hermes mcp add` is
# discovery-first and wants a terminal, so a scripted seat writes the same map the CLI
# writes — merge-preserving and idempotent: a LIVE entry is never overwritten.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
command -v hermes >/dev/null 2>&1 || { printf 'hermes-seat: hermes is not installed\n' >&2; exit 1; }

CFG="${YMIR_MCP_ADAPTER:-$HOME/.pi/agent/mcp-adapter.json}"
[ -r "$CFG" ] || { printf 'hermes-seat: no packet list at %s\n' "$CFG" >&2; exit 1; }
HERMES_YAML="${HERMES_CONFIG:-$HOME/.hermes/config.yaml}"

seat() {
  python3 - "$CFG" "$HERMES_YAML" <<'PY'
import json, sys, os
cfg, out = sys.argv[1], sys.argv[2]
d = json.load(open(cfg))
srv = d.get('servers') or d.get('mcpServers') or {}
try:
    import yaml
except Exception:
    print('hermes-seat: PyYAML missing — install python3-yaml'); raise SystemExit(1)
cur = {}
if os.path.exists(out):
    cur = yaml.safe_load(open(out)) or {}
cur.setdefault('mcp_servers', {})
have = cur['mcp_servers']
added = 0
for name, c in srv.items():
    if name in have:
        continue
    if 'url' in c:
        have[name] = {'url': c['url'], 'enabled': True}
    elif 'command' in c:
        e = {'command': c['command'], 'args': c.get('args') or [], 'enabled': True}
        if c.get('env'):
            e['env'] = c['env']
        have[name] = e
    added += 1
if added:
    tmp = out + '.seat.tmp'
    with open(tmp, 'w') as fh:
        yaml.safe_dump(cur, fh, sort_keys=False)
    os.replace(tmp, out)
print(f'hermes-seat: {added} packet(s) written to {out} ({len(have)} total)')
PY
  ( cd "$ROOT" && hermes skills trust >/dev/null 2>&1 ) && printf 'hermes-seat: the house skills tree is trusted in %s\n' "$ROOT"
}

check() {
  python3 - "$CFG" "$HERMES_YAML" <<'PY'
import json, sys, os
cfg, out = sys.argv[1], sys.argv[2]
d = json.load(open(cfg))
srv = d.get('servers') or d.get('mcpServers') or {}
have = set()
if os.path.exists(out):
    try:
        import yaml
        have = set(((yaml.safe_load(open(out)) or {}).get('mcp_servers') or {}).keys())
    except Exception:
        have = set()
missing = sorted(set(srv) - have)
for m in missing:
    print(f'hermes-seat: missing {m}')
print('hermes-seat: every packet is seated' if not missing else f'hermes-seat: {len(missing)} missing')
raise SystemExit(1 if missing else 0)
PY
}

case "${1:-}" in
  -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//' | head -12; exit 0 ;;
  --check) check ;;
  ""|--apply|apply) seat ;;
  *) printf 'error: unknown action %s\nhelp: hermes-seat.sh [--check]\n' "$1" >&2; exit 2 ;;
esac
