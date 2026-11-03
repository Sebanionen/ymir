#!/usr/bin/env bash
# mcp-config.test.sh — the harness MCP config points at THIS body's gateway
# (plan 51 P6), never at the heart directly, so a heart-address change never
# moves the seat's config.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
M="$ROOT/bin/bridge/mcp-config.sh"
fail=0
ok()  { printf 'ok - %s\n' "$1"; }
bad() { printf 'not ok - %s\n' "$1" >&2; fail=1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat >"$TMP/a.json" <<'EOF'
{"heart":"h1","hosts":{"h1":{"roles":["heart"],"tailnet":"h1.<host>.tailnet.ts.net"},"d1":{"roles":["dev"],"tailnet":"d1.<host>.tailnet.ts.net"}}}
EOF
cat >"$TMP/b.json" <<'EOF'
{"heart":"h2","hosts":{"h2":{"roles":["heart"],"tailnet":"h2.<host>.tailnet.ts.net","lan":"192.0.2.9"},"d1":{"roles":["dev"],"tailnet":"d1.<host>.tailnet.ts.net"}}}
EOF

# every record server points at the local gateway, and the heart is absent
out="$(YMIR_HOST=d1 YMIR_FLEET_REGISTRY="$TMP/a.json" bash "$M" 2>/dev/null)"
printf '%s' "$out" | grep -q '127.0.0.1:8316/mcp/well' && ok "well points at the gateway" || bad "well: $out"
printf '%s' "$out" | grep -q '127.0.0.1:8316/mcp/bolthorn' && ok "bolthorn points at the gateway" || bad "bolthorn: $out"
printf '%s' "$out" | grep -q '127.0.0.1:8316/mcp/skuld' && ok "skuld points at the gateway" || bad "skuld: $out"
printf '%s' "$out" | grep -q 'h1.<host>.tailnet.ts.net' && bad "config leaked the heart address" || ok "no heart address in the config"

# the config OUTLIVES a heart-address change: two registries, one config
out_b="$(YMIR_HOST=d1 YMIR_FLEET_REGISTRY="$TMP/b.json" bash "$M" 2>/dev/null)"
[ "$out" = "$out_b" ] && ok "config is identical across two different hearts" || bad "config moved with the heart"

# the gateway port is configurable
out="$(MCP_GATEWAY_PORT=9999 bash "$M" 2>/dev/null)"
printf '%s' "$out" | grep -q '127.0.0.1:9999/mcp/well' && ok "gateway port is honored" || bad "port override: $out"

# parses as JSON, with or without a registry
YMIR_HOST=d1 YMIR_FLEET_REGISTRY="$TMP/a.json" bash "$M" 2>/dev/null \
  | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>JSON.parse(s))' 2>/dev/null \
  && ok "config parses as JSON" || bad "config did not parse"
out="$(YMIR_FLEET_REGISTRY=/nonexistent/f.json bash "$M" 2>/dev/null)"
printf '%s' "$out" | grep -q '127.0.0.1:8316/mcp/well' && ok "no registry -> gateway default" || bad "no registry: $out"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES"
exit "$fail"
