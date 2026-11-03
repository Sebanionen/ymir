#!/usr/bin/env bash
# rail-resolve.test.sh — the living rail resolver (plan 51, Parts 9a/9b/9c).
#
# A synthetic registry and a stub rail prove the DECISION without the private
# registry or the real fleet: the alive box serves, a dropped box is declined,
# and a mocked registry flips the answer. The key is proven to be a REFERENCE.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RR="$ROOT/bin/model/rail-resolve.sh"
fail=0
ok()  { printf 'ok - %s\n' "$1"; }
bad() { printf 'not ok - %s\n' "$1" >&2; fail=1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PORT=$(( (RANDOM % 20000) + 20000 ))

# a stub rail: the cheap keyless /health answers 200, everything else 404
python3 - "$PORT" <<'PY' &
import http.server, socketserver, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        code = 200 if self.path == "/health" else 404
        self.send_response(code); self.end_headers()
        self.wfile.write(b"ok" if code == 200 else b"no")
    def log_message(self, *a): pass
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("127.0.0.1", int(sys.argv[1])), H) as s:
    s.serve_forever()
PY
STUB=$!
for _ in $(seq 1 30); do
  curl -fsS -m 1 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && break
  sleep 0.1
done

out="$(bash "$RR" --version)"
[ "$out" = "1.0.0" ] && ok "version" || bad "version: $out"

# a mocked registry where THIS box is the rail: the stub serves
cat >"$TMP/up.json" <<EOF
{"heart":"selfbox","rails":["selfbox"],"hosts":{"selfbox":{"roles":["dev"],"tailnet":"selfbox.<host>.tailnet.ts.net"}}}
EOF
out="$(YMIR_HOST=selfbox YMIR_FLEET_REGISTRY="$TMP/up.json" YMIR_RAIL_PORT="$PORT" \
  LLAMA_SWAP_API_KEY=SUPERSECRET bash "$RR" resolve 2>/dev/null)"
printf '%s' "$out" | grep -q "127.0.0.1:$PORT/v1" && ok "the alive box serves" || bad "alive: $out"
printf '%s' "$out" | grep -q 'LLAMA_SWAP_API_KEY' && ok "the key is a reference" || bad "key ref: $out"
printf '%s' "$out" | grep -q 'SUPERSECRET' && bad "the key VALUE leaked" || ok "no key value in the answer"

# the same box dropped: a declined answer, and never a fake URL
cat >"$TMP/down.json" <<'EOF'
{"heart":"selfbox","rails":["faraway"],"hosts":{"selfbox":{"roles":["dev"]},"faraway":{"roles":["dev"],"lan":"192.0.2.1"}}}
EOF
out="$(YMIR_HOST=selfbox YMIR_FLEET_REGISTRY="$TMP/down.json" YMIR_RAIL_TIMEOUT=1 bash "$RR" resolve 2>/dev/null)"; rc=$?
[ "$rc" -eq 1 ] && ok "a declined answer exits 1" || bad "declined exit: $rc"
printf '%s' "$out" | grep -q 'rail_declined' && ok "declined names the reason" || bad "declined: $out"
printf '%s' "$out" | grep -q '192.0.2.1:8080/v1' && bad "declined printed a fake URL" || ok "no fake URL in a declined answer"

# a mocked registry flips the answer
out_up="$(YMIR_HOST=selfbox YMIR_FLEET_REGISTRY="$TMP/up.json" YMIR_RAIL_PORT="$PORT" bash "$RR" resolve --json 2>/dev/null)"
out_down="$(YMIR_HOST=selfbox YMIR_FLEET_REGISTRY="$TMP/down.json" YMIR_RAIL_TIMEOUT=1 bash "$RR" resolve --json 2>/dev/null)"
python3 - "$out_up" "$out_down" <<'PY' && ok "the answer flips with liveness" || bad "the answer did not flip"
import json, sys
up = json.loads(sys.argv[1]); down = json.loads(sys.argv[2])
assert up["serving"] and up["serving"]["url"].startswith("http://127.0.0.1:")
assert down["serving"] is None
PY

# status reports the ranked set — the live box AND the dropped one
cat >"$TMP/mixed.json" <<EOF
{"heart":"selfbox","rails":["selfbox","faraway"],"hosts":{"selfbox":{"roles":["dev"],"tailnet":"selfbox.<host>.tailnet.ts.net"},"faraway":{"roles":["dev"],"lan":"192.0.2.1"}}}
EOF
out="$(YMIR_HOST=selfbox YMIR_FLEET_REGISTRY="$TMP/mixed.json" YMIR_RAIL_PORT="$PORT" YMIR_RAIL_TIMEOUT=1 bash "$RR" status 2>/dev/null)"
printf '%s' "$out" | grep -q '"selfbox","127.0.0.1","http://127.0.0.1:' && ok "status lists the live box" || bad "status live: $out"
printf '%s' "$out" | grep -q '"faraway"' && ok "status lists the dropped box" || bad "status dead: $out"

kill "$STUB" 2>/dev/null || true
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES"
exit "$fail"
