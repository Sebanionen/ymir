#!/usr/bin/env bash
# adapter-test.sh — the Telegram layer's own suite: tiers, the addressee rule, bans, typing, limits.
#
#   bin/assistant/adapter-test.sh
#
# The walls suite proves the ENGINE. This proves the MOUTH: who is answered, who is ignored, and that
# a bot message can never start a loop. A stub stands in for api.telegram.org (TELEGRAM_API_BASE).
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo root, found by walking up to the tree that holds .pi and RULES — never counted in
# "../", because this shelf was moved once (bin/assistant/ -> systems/skirnir/, plan 149) and
# 25 scripts kept the old depth, so every $ROOT/bin/... pointed into systems/ instead (2026-11-02).
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)"
TMP="$(mktemp -d)"; export YMIR_HOME="$TMP/home" SKIRNIR_NO_ESCALATE=1
# the hoard is RESOLVED, never guessed (Rule 07)
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
real_home=""; ymir_home_root real_home 2>/dev/null || true
S="$YMIR_HOME/hodd/state/assistant"; I="$YMIR_HOME/hodd/identity/assistant"
mkdir -p "$S" "$I/approved"
[ -n "$real_home" ] && cp "$real_home/hodd/identity/assistant/approved/"*.md "$I/approved/" 2>/dev/null || true
[ -n "$real_home" ] && cp "$real_home/hodd/identity/assistant/grants.yaml" "$I/grants.yaml" 2>/dev/null || true
cat > "$I/groups.yaml" <<'YAML'
groups:
  - id: "-100"
    name: "Test group"
    tier: collaborator
YAML
printf 'banned: ["-200"]\n' > "$I/banned.yaml"
bash "$SCRIPT_DIR/kb-export.sh" >/dev/null 2>&1
fails=0; pass(){ printf '  PASS %s\n' "$1"; }; fail(){ printf '  FAIL %s — %s\n' "$1" "$2" >&2; fails=$((fails+1)); }

cat > "$TMP/api-fixture.py" <<'PY'
import json, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
CAP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sent.jsonl")
def load_updates():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "updates.json")
    try:
        return json.load(open(path))
    except Exception:
        return []
class H(BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('content-length', 0)); body = self.rfile.read(n).decode()
        method = self.path.rsplit('/', 1)[-1]
        if method == "getUpdates":
            out = {"ok": True, "result": load_updates()}
            json.dump([], open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "updates.json"), "w"))
        else:
            open(CAP, "a").write(json.dumps({"method": method, "body": body}) + "\n")
            out = {"ok": True, "result": {"message_id": 1}}
        data = json.dumps(out).encode()
        self.send_response(200); self.send_header('content-type','application/json'); self.end_headers()
        self.wfile.write(data)
    def log_message(self, *a): pass
HTTPServer(('127.0.0.1', 18456), H).serve_forever()
PY

updates() {  # <json>
  printf '%s' "$1" > "$TMP/updates.json"
}
run_once() { TELEGRAM_API_BASE="http://127.0.0.1:18456" SKIRNIR_TELEGRAM_BOT_TOKEN="1:x" \
  TELEGRAM_OWNER_ID="111" python3 "$SCRIPT_DIR/telegram.py" --once >/dev/null 2>&1; }
sent() { wc -l < "$TMP/sent.jsonl" 2>/dev/null | tr -d ' '; }

echo "adapter-test — the mouth"
# 1 · the owner's DM is answered, and typing is shown first
updates '[{"update_id":1,"message":{"message_id":1,"from":{"id":111,"is_bot":false},"chat":{"id":111,"type":"private"},"text":"hi"}}]'
python3 "$TMP/api-fixture.py" >/dev/null 2>&1 & API_FIXTURE=$!; sleep 1
run_once
grep -q '"method": "sendChatAction"' "$TMP/sent.jsonl" 2>/dev/null && pass "typing is shown" || fail "typing" "no sendChatAction"
grep -q '"method": "sendMessage"' "$TMP/sent.jsonl" 2>/dev/null && pass "the owner's DM is answered" || fail "owner DM" "no reply"

# 2 · a group message without his name is IGNORED
: > "$TMP/sent.jsonl"
updates '[{"update_id":2,"message":{"message_id":2,"from":{"id":111},"chat":{"id":-100,"type":"group"},"text":"just chatting"}}]'
run_once
[ "$(sent)" = "0" ] && pass "an unaddressed group message is ignored" || fail "addressee rule" "$(sent) sent"

# 3 · a group message WITH his name is answered
updates '[{"update_id":3,"message":{"message_id":3,"from":{"id":111},"chat":{"id":-100,"type":"group"},"text":"skirnir are you there?"}}]'
run_once
grep -q '"method": "sendMessage"' "$TMP/sent.jsonl" 2>/dev/null && pass "an addressed group message is answered" || fail "addressed group" "no reply"

# 4 · a banned chat is not answered at all
: > "$TMP/sent.jsonl"
updates '[{"update_id":4,"message":{"message_id":4,"from":{"id":999},"chat":{"id":-200,"type":"group"},"text":"skirnir hi"}}]'
run_once
[ "$(sent)" = "0" ] && pass "a banned chat is refused silently" || fail "ban" "$(sent) sent"

# 5 · another bot never starts a conversation
updates '[{"update_id":5,"message":{"message_id":5,"from":{"id":777,"is_bot":true},"chat":{"id":111,"type":"private"},"text":"skirnir hello"}}]'
run_once
[ "$(sent)" = "0" ] && pass "a bot message is ignored (no loop)" || fail "bot loop" "$(sent) sent"

kill "$API_FIXTURE" 2>/dev/null
echo
if [ "$fails" -eq 0 ]; then echo "adapter-test: the mouth holds"; rm -rf "$TMP"; exit 0; fi
echo "adapter-test: $fails failure(s)" >&2; rm -rf "$TMP"; exit 1
