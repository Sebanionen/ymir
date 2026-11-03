#!/usr/bin/env bash
# model-eindri.test.sh — placement by role and errand routing (plan 51 P5).
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MP="$ROOT/bin/model/model-placement.sh"
ER="$ROOT/bin/agents/eindri-route.sh"
fail=0
ok()  { printf 'ok - %s\n' "$1"; }
bad() { printf 'not ok - %s\n' "$1" >&2; fail=1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat >"$TMP/f.json" <<'EOF'
{"heart":"h1","hosts":{
  "h1":{"roles":["heart"],"tailnet":"h1.<host>.tailnet.ts.net"},
  "f1":{"roles":["forge"],"tailnet":"f1.<host>.tailnet.ts.net"},
  "d1":{"roles":["dev"],"tailnet":"d1.<host>.tailnet.ts.net"}}}
EOF
export YMIR_FLEET_REGISTRY="$TMP/f.json"

# placement: the forge rail is reported
out="$(YMIR_HOST=d1 bash "$MP" 2>/dev/null)"
printf '%s' "$out" | grep -q 'f1.<host>.tailnet.ts.net:8080' && ok "forge rail listed from the registry" || bad "placement: $out"
printf '%s' "$out" | grep -q '"h1.<host>.tailnet.ts.net' && bad "a non-forge host appeared as a rail" || ok "only forge hosts are rails"

# routing by kind
out="$(YMIR_HOST=d1 bash "$ER" model 2>/dev/null)"
printf '%s' "$out" | grep -q '"model","f1"' && ok "model errand routes to the forge" || bad "model route: $out"
out="$(YMIR_HOST=d1 bash "$ER" record 2>/dev/null)"
printf '%s' "$out" | grep -q '"record","h1"' && ok "record errand routes to the heart" || bad "record route: $out"
out="$(YMIR_HOST=d1 bash "$ER" ui 2>/dev/null)"
printf '%s' "$out" | grep -q '"ui","d1"' && ok "ui errand routes to a dev body" || bad "ui route: $out"

# an unmatched kind defaults to any, this machine first
out="$(YMIR_HOST=d1 bash "$ER" nonsense 2>/dev/null)"
printf '%s' "$out" | grep -q '"nonsense","d1' && ok "unmatched kind defaults to any, local first" || bad "unmatched: $out"

# json parses
YMIR_HOST=d1 bash "$ER" model --json 2>/dev/null \
  | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>JSON.parse(s))' 2>/dev/null \
  && ok "route json parses" || bad "route json did not parse"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES"
exit "$fail"
