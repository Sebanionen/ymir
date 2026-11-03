#!/usr/bin/env bash
# integration.sh — the REAL fleet checks, not fixtures.
#
# Reusable: run it on any seat. Every check reports pass | fail | skip with a reason.
# A `skip` means the service is not configured on this seat, never that the code is
# assumed broken. A `fail` is a defect.
#
# Usage: bash tests/integration.sh [--json]
# Env: YMIR_HOME · MANAGANDR_CACHE · VEXA_API_URL · VEXA_API_KEY ·
#      TELEGRAM_BOT_TOKEN · PING_PUBLIC_URL · SNOTRA_MCP_URL · PING_TAILNET_URL
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
JSON=0; [ "${1-}" = "--json" ] && JSON=1
PASS=0; FAIL=0; SKIP=0; ROWS=()
row(){ ROWS+=("$1|$2|$3"); case "$2" in pass) PASS=$((PASS+1));; fail) FAIL=$((FAIL+1));; skip) SKIP=$((SKIP+1));; esac; }
pass(){ row "$1" pass "$2"; }
fail(){ row "$1" fail "$2"; }
skip(){ row "$1" skip "$2"; }

YMIR_HOME="${YMIR_HOME:-$HOME/Documents/ymirhome}"
PING_PUBLIC_URL="${PING_PUBLIC_URL:-https://ping.zerwiz.org}"
PING_TAILNET_URL="${PING_TAILNET_URL:-https://<host>.<host>.tailnet.ts.net:3000}"
SNOTRA_MCP_URL="${SNOTRA_MCP_URL:-http://<host>.<host>.tailnet.ts.net:8321/mcp}"
MANAGANDR_CACHE="${MANAGANDR_CACHE:-$YMIR_HOME/hodd/state/calendar/cache.json}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# 1 — the store against a real filesystem
if [ -x "$ROOT/bin/time/snotra/snotra-store.sh" ]; then
  H="$TMP/home"; mkdir -p "$H"
  if YMIR_HOME="$H" "$ROOT/bin/time/snotra/snotra-store.sh" new work "integration" --title "Integration" >/dev/null 2>&1 \
     && YMIR_HOME="$H" "$ROOT/bin/time/snotra/snotra-store.sh" index >/dev/null 2>&1 \
     && YMIR_HOME="$H" "$ROOT/bin/time/snotra/snotra-store.sh" verify --all >/dev/null 2>&1; then
    pass store "real fs: new, index, verify"
  else fail store "real fs contract failed"; fi
else skip store "snotra-store.sh not present"; fi

# 2 — auto-join against the REAL calendar cache
if [ -r "$MANAGANDR_CACHE" ]; then
  N=$(python3 -c "import json;print(len(json.load(open('$MANAGANDR_CACHE')).get('events',[])))" 2>/dev/null || echo 0)
  NOW=$(python3 -c "import json;print(json.load(open('$MANAGANDR_CACHE')).get('as_of',''))" 2>/dev/null)
  if [ "$N" -gt 0 ] && [ -n "$NOW" ] && YMIR_HOME="$TMP/aj" AUTOJOIN_NOW="$NOW" "$ROOT/bin/time/snotra/snotra-autojoin.sh" scan --events "$MANAGANDR_CACHE" >/dev/null 2>&1; then
    J=$(python3 -c "import json;d=json.load(open('$TMP/aj/hodd/state/snotra/autojoin-plan.json'));print(len(d['plan']))" 2>/dev/null || echo 0)
    pass autojoin "real cache: $N events, $J planned (cache as_of $NOW)"
  else fail autojoin "real cache present but scan failed"; fi
else skip autojoin "no calendar cache at $MANAGANDR_CACHE"; fi

# 3 — Google calendar LIVE (the grant, not the cache)
if command -v node >/dev/null && [ -r "$ROOT/tools/calendar/reader.mjs" ]; then
  out="$(timeout 45 bash "$ROOT/bin/time/snotra/calendar-ask.sh" --refresh probe 2>/dev/null || true)"
  st="$(printf '%s' "$out" | python3 -c "import json,sys;print(json.load(sys.stdin).get('status'))" 2>/dev/null || echo unknown)"
  reason="$(printf '%s' "$out" | python3 -c "import json,sys;print(json.load(sys.stdin).get('reason') or '')" 2>/dev/null || true)"
  if [ "$st" = ok ]; then pass calendar "live refresh ok"
  else fail calendar "live refresh $st${reason:+ ($reason)}"; fi
else skip calendar "node or reader missing"; fi

# 4 — Þing public HTTPS
code=$(curl -sS -o "$TMP/ping.html" -w '%{http_code}' -m 20 -L "$PING_PUBLIC_URL" 2>/dev/null || echo 000)
if [ "$code" = 200 ] && grep -qi "Þing\|thing" "$TMP/ping.html"; then
  pass ping-public "200 from $PING_PUBLIC_URL"
elif [ "$code" = 000 ]; then skip ping-public "unreachable: $PING_PUBLIC_URL"
else fail ping-public "HTTP $code from $PING_PUBLIC_URL"; fi

# 5 — MCP face: initialize, then tools/list (real streamable HTTP)
if command -v curl >/dev/null; then
  hdr="$TMP/h"; : > "$hdr"
  init=$(curl -sS -m 20 -D "$hdr" -X POST "$SNOTRA_MCP_URL" \
    -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"integration","version":"1"}}}' 2>/dev/null || true)
  sid=$(awk 'BEGIN{IGNORECASE=1}/^mcp-session-id:/{gsub(/\r/,"");print $2}' "$hdr" | tail -1)
  if [ -n "$init" ] && [ -n "$sid" ]; then
    tl=$(curl -sS -m 20 -X POST "$SNOTRA_MCP_URL" -H "mcp-session-id: $sid" \
      -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
      -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' 2>/dev/null || true)
    n=$(printf '%s' "$tl" | python3 -c "
import json,sys
raw=sys.stdin.read()
for line in raw.splitlines():
    if line.startswith('data: '): raw=line[6:]
d=json.loads(raw); print(len(d['result']['tools']))" 2>/dev/null || echo 0)
    [ "${n:-0}" -ge 4 ] && pass mcp "initialize + $n tools at $SNOTRA_MCP_URL" || fail mcp "tools/list returned ${n:-0} tools"
  else fail mcp "initialize failed at $SNOTRA_MCP_URL"; fi
else skip mcp "curl missing"; fi

# 6 — Vexa: only meaningful with a real endpoint and key
if [ -n "${VEXA_API_URL:-}" ] && [ -n "${VEXA_API_KEY:-}" ]; then
  code=$(curl -sS -o /dev/null -w '%{http_code}' -m 15 -H "Authorization: Bearer $VEXA_API_KEY" "${VEXA_API_URL%/}/health" 2>/dev/null || echo 000)
  [ "$code" = 200 ] && pass vexa "health 200 at $VEXA_API_URL" || fail vexa "health HTTP $code"
else
  skip vexa "VEXA_API_URL/VEXA_API_KEY unset — install Vexa Lite and set both"
fi

# 7 — Telegram: real getMe when a token is present
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
  ok=$(curl -sS -m 15 "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/getMe" 2>/dev/null | python3 -c "import json,sys;print(json.load(sys.stdin).get('ok'))" 2>/dev/null || echo False)
  [ "$ok" = True ] && pass telegram "getMe ok" || fail telegram "getMe refused"
else
  skip telegram "TELEGRAM_BOT_TOKEN unset — create a bot and pair an owner"
fi

if [ "$JSON" = 1 ]; then
  printf '{"pass":%d,"fail":%d,"skip":%d,"checks":[' "$PASS" "$FAIL" "$SKIP"
  first=1; for r in "${ROWS[@]}"; do IFS='|' read -r n s e <<< "$r"; [ $first = 1 ] || printf ','; first=0; printf '{"name":"%s","status":"%s","evidence":"%s"}' "$n" "$s" "${e//\"/\'}"; done
  printf ']}\n'
else
  printf 'integration[%d]{check,status,evidence}:\n' "${#ROWS[@]}"
  for r in "${ROWS[@]}"; do IFS='|' read -r n s e <<< "$r"; printf '  "%s","%s","%s"\n' "$n" "$s" "${e//\"/\'}"; done
  printf '\n%d pass, %d fail, %d skip\n' "$PASS" "$FAIL" "$SKIP"
fi
[ "$FAIL" -eq 0 ]
