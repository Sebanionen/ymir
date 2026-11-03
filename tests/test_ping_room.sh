#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
DOOR="$ROOT/bin/thing/ping-room.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL %s — %s\n' "$1" "${2-}"; }
check(){ local n=$1; shift; if "$@" >/dev/null 2>&1; then ok "$n"; else bad "$n"; fi; }
refute(){ local n=$1; shift; if "$@" >/dev/null 2>&1; then bad "$n" "expected failure"; else ok "$n"; fi; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export YMIR_HOME="$TMP/home"; mkdir -p "$YMIR_HOME"
mkdir -p "$TMP/bin"
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/tailscale"; chmod +x "$TMP/bin/tailscale"
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/cloudflared"; chmod +x "$TMP/bin/cloudflared"
export PATH="$TMP/bin:$PATH"

export PING_CMD="python3 -m http.server 3011" PING_PORT=3011
check "start raises a room" "$DOOR" start --port 3011 --mode local --title Test
check "status says up" bash -c "'$DOOR' status | grep -qP 'room\tup'"
check "url is the local room" bash -c "'$DOOR' url | grep -q '127.0.0.1:3011'"
refute "a second start is refused" "$DOOR" start --port 3011 --mode local
check "stop lowers the room" "$DOOR" stop
check "status says down" bash -c "'$DOOR' status | grep -qP 'room\tdown'"

check "start in tailnet mode" "$DOOR" start --port 3011 --mode tailnet
check "tailnet url is https magicdns" bash -c "'$DOOR' url | grep -q '^https://.*<host>.tailnet.ts.net'"
check "claim is refused without a raised room after stop" bash -c "'$DOOR' stop >/dev/null; '$DOOR' claim >/dev/null 2>&1; test \$? -ne 0"
check "start for claim" "$DOOR" start --port 3011 --mode local
check "claim records the host" "$DOOR" claim
check "claim file names ping.zerwiz.org" bash -c "grep -q 'ping.zerwiz.org' '$YMIR_HOME/hodd/state/thing/claim.json'"
python3 - "$YMIR_HOME/hodd/state/thing/claim.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['host']='other-host'; json.dump(d,open(p,'w'))
PY
refute "a live claim held elsewhere is refused" "$DOOR" claim
check "release clears the claim" "$DOOR" release
check "release is idempotent" "$DOOR" release
check "final stop" "$DOOR" stop

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"; [ "$FAIL" -eq 0 ]
