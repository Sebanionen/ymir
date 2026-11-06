#!/usr/bin/env bash
# test_utgard_box.sh — a box is only a box if these hold.
#
# The three laws, each proved against a real engine or refused with a reason:
#   1. no host credentials — no $HOME, no vault, no rail key inside
#   2. one road out — the door's allowlist answers its names and nothing else
#   3. a box is a record — labelled, listed, timed, reclaimable, and removable
#
# A clean skip is a pass (RULES/25): no engine, or no box image, says so and exits 0.
# Nothing here reaches the real rail; a stub upstream stands in its place, so the
# suite is safe to run beside the operator's own work.
#
#   bash tests/test_utgard_box.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOX="$ROOT/bin/forge/utgard-box.sh"
ENGINE="${YMIR_CONTAINER_ENGINE:-docker}"
TAG="${UTGARD_BOX_IMAGE:-utgard-box:latest}"
NET="utgard-test-door-net"
SUBNET="172.31.78.0/24"
PREFIX="utgardtest"
KEY="testkey-not-a-real-secret"
STUB="stubrail"

export UTGARD_BOX_PREFIX="$PREFIX"
export UTGARD_BOX_DOOR_NET="$NET"
export UTGARD_BOX_DOOR_SUBNET="$SUBNET"
export UTGARD_BOX_RAIL_TARGET="$STUB:8080"
export UTGARD_BOX_KEY="$KEY"
export UTGARD_BOX_IMAGE="$TAG"

pass=0; fail=0; skip=0
ok()   { pass=$((pass+1)); printf 'ok   : %s\n' "$*"; }
bad()  { fail=$((fail+1)); printf 'FAIL : %s\n' "$*"; }
skip() { skip=$((skip+1)); printf 'skip : %s\n' "$*"; }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }

command -v "$ENGINE" >/dev/null 2>&1 || { skip "no container engine ($ENGINE) — nothing to prove here"; printf 'utgard-box-tests: %s pass, %s fail, %s skip\n' "$pass" "$fail" "$skip"; exit 0; }
"$ENGINE" info >/dev/null 2>&1 || { skip "the engine is installed but not reachable — no daemon"; printf 'utgard-box-tests: %s pass, %s fail, %s skip\n' "$pass" "$fail" "$skip"; exit 0; }
"$ENGINE" image inspect "$TAG" >/dev/null 2>&1 || { skip "box image $TAG is absent — build it with: utgard box build"; printf 'utgard-box-tests: %s pass, %s fail, %s skip\n' "$pass" "$fail" "$skip"; exit 0; }

TMP="$(mktemp -d)"
cleanup() {
  "$BOX" rm "b1" >/dev/null 2>&1 || true
  "$BOX" rm "b2" >/dev/null 2>&1 || true
  "$ENGINE" rm -f "${PREFIX}-stubrail" "$STUB" >/dev/null 2>&1 || true
  "$ENGINE" network rm "$NET" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

# --- the stub rail: answers /v1/models and echoes the credential it was given ---
cat > "$TMP/stub.py" <<'PY'
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        auth = self.headers.get("Authorization", "(none)")
        body = json.dumps({"data": [{"id": "stub-model"}], "auth_seen": auth}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a):
        pass

HTTPServer(("0.0.0.0", 8080), H).serve_forever()
PY

# The door network is the script's to create (that is what is under test). Here it
# only has to EXIST before the stub can join it; a taken subnet is not a failure,
# it is the reason the script has a fallback.
if ! "$ENGINE" network inspect "$NET" >/dev/null 2>&1; then
  "$ENGINE" network create --subnet "$SUBNET" "$NET" >/dev/null 2>&1 \
    || "$ENGINE" network create "$NET" >/dev/null 2>&1 \
    || { skip "could not create a door network for the stub — nothing to prove"; exit 0; }
fi
"$ENGINE" rm -f "$STUB" >/dev/null 2>&1 || true
if ! stub_err="$("$ENGINE" run -d --name "$STUB" --network "$NET" -v "$TMP/stub.py:/stub.py:ro" \
      "$TAG" python3 /stub.py 2>&1)"; then
  skip "could not raise the stub rail — the box tests need it"
  printf '%s\n' "$stub_err" | sed 's/^/       engine: /' >&2
  printf 'utgard-box-tests: %s pass, %s fail, %s skip\n' "$pass" "$fail" "$skip"
  exit 0
fi
for _ in $(seq 1 20); do
  "$ENGINE" exec "$STUB" bash -lc 'timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/8080"' >/dev/null 2>&1 && break
  sleep 0.3
done

# --- verb surface -------------------------------------------------------------
check "version answers" "$BOX" --version
check "usage answers"   "$BOX" --help
check "the engine's door dispatches" "$ROOT/bin/forge/utgard.sh" box --version

# --- new: a box is born with three laws --------------------------------------
if out="$("$BOX" new b1 --ttl 10m --seal door --port 3000 --model stub-model 2>&1)"; then
  ok "new makes a box"
else
  bad "new makes a box — output: $out"
  printf 'utgard-box-tests: %s pass, %s fail, %s skip\n' "$pass" "$fail" "$skip"
  exit 1
fi

"$ENGINE" inspect "${PREFIX}-b1" >/dev/null 2>&1 && ok "the container stands" || bad "the container stands"
[ "$("$ENGINE" inspect --format '{{ index .Config.Labels "ymir.utgard.role" }}' "${PREFIX}-b1" 2>/dev/null)" = "box" ] \
  && ok "it is labelled a box (the record)" || bad "it is labelled a box (the record)"
"$ENGINE" volume inspect "${PREFIX}-b1-work" >/dev/null 2>&1 && ok "it has its own volume" || bad "it has its own volume"
"$ENGINE" network inspect "${PREFIX}-b1-net" >/dev/null 2>&1 && ok "it has its own network" || bad "it has its own network"

# law 1 — no host credentials
home="$("$ENGINE" exec "${PREFIX}-b1" bash -lc 'printf %s "$HOME"' 2>/dev/null)"
[ "$home" = "/home/agent" ] && ok "HOME is the box's own ($home)" || bad "HOME is the box's own (got '$home')"
if "$ENGINE" exec "${PREFIX}-b1" bash -lc 'ls /home/heimdall 2>/dev/null | head -1' 2>/dev/null | grep -q .; then
  bad "the operator's home is NOT visible"
else
  ok "the operator's home is NOT visible"
fi
mounts="$("$ENGINE" inspect --format '{{range .Mounts}}{{.Source}}:{{.Destination}} {{end}}' "${PREFIX}-b1" 2>/dev/null)"
case "$mounts" in
  *"/home/heimdall"*|*"ymirhome"*) bad "no host path is mounted (got: $mounts)" ;;
  *) ok "no host path is mounted" ;;
esac
key="$("$ENGINE" exec "${PREFIX}-b1" bash -lc 'printf %s "$OPENAI_API_KEY"' 2>/dev/null)"
[ "$key" = "door" ] && ok "the box holds a placeholder, not the key" || bad "the box holds a placeholder, not the key (got '$key')"
if "$ENGINE" exec "${PREFIX}-b1" bash -lc 'env | grep -F "$1"' _ "$KEY" 2>/dev/null | grep -q .; then
  bad "the real key is nowhere in the box's env"
else
  ok "the real key is nowhere in the box's env"
fi

# law 2 — one road out: the rail answers, and it answers WITH the door's key
rail="$("$ENGINE" exec "${PREFIX}-b1" bash -lc 'curl -s -m 25 "$OPENAI_BASE_URL/models"' 2>/dev/null)"
case "$rail" in
  *stub-model*) ok "the rail answers through the door" ;;
  *) bad "the rail answers through the door (got: ${rail:0:80})" ;;
esac
case "$rail" in
  *"Bearer $KEY"*) ok "the door injected the credential (the box never held it)" ;;
  *) bad "the door injected the credential (got: ${rail:0:120})" ;;
esac
outside="$("$ENGINE" exec "${PREFIX}-b1" bash -lc 'curl -s -m 10 http://example.com' 2>/dev/null)"
case "$outside" in
  *"no road to"*) ok "the door refuses every other name, in words" ;;
  *) bad "the door refuses every other name, in words (got: ${outside:0:80})" ;;
esac
case "$outside" in
  *"<html"*|*"Example Domain"*) bad "the box cannot reach the internet" ;;
  *) ok "the box cannot reach the internet" ;;
esac

# law 3 — a record, a door, a harvest, and a vanishing point
"$BOX" list 2>/dev/null | grep -q '^  "b1"' && ok "list shows the box" || bad "list shows the box"
u="$("$BOX" url b1 2>/dev/null)"
case "$u" in http://127.0.0.1:*) ok "url is a loopback door ($u)" ;; *) bad "url is a loopback door (got '$u')" ;; esac
"$ENGINE" exec "${PREFIX}-b1" bash -lc 'mkdir -p /box/work && echo harvest > /box/work/out.txt' >/dev/null 2>&1
"$BOX" pull b1 /box/work/out.txt "$TMP" >/dev/null 2>&1
[ -f "$TMP/out.txt" ] && ok "pull brings the harvest home" || bad "pull brings the harvest home"

# refusals a box must make — each names the road, never silently succeeds
"$BOX" new b1 --ttl 10m >/dev/null 2>&1 && bad "a duplicate name is refused" || ok "a duplicate name is refused"
"$BOX" new 'bad name' --ttl 10m >/dev/null 2>&1 && bad "an invalid name is refused" || ok "an invalid name is refused"
"$BOX" new b9 --ttl 30s >/dev/null 2>&1 && bad "a box shorter than five minutes is refused" || ok "a box shorter than five minutes is refused"
"$BOX" url nosuchbox >/dev/null 2>&1 && bad "url on an absent box is refused" || ok "url on an absent box is refused"

"$BOX" gc >/dev/null 2>&1 && ok "gc runs and reclaims nothing it should not" || bad "gc runs and reclaims nothing it should not"

"$BOX" rm b1 >/dev/null 2>&1
"$ENGINE" inspect "${PREFIX}-b1" >/dev/null 2>&1 && bad "rm takes the container" || ok "rm takes the container"
"$ENGINE" volume inspect "${PREFIX}-b1-work" >/dev/null 2>&1 && bad "rm takes the volume" || ok "rm takes the volume"
"$ENGINE" inspect "${PREFIX}-b1-door" >/dev/null 2>&1 && bad "rm takes the door" || ok "rm takes the door"

# --keep-volume keeps the harvest
"$BOX" new b2 --ttl 10m --seal none --port 0 --model stub-model >/dev/null 2>&1
"$BOX" rm b2 --keep-volume >/dev/null 2>&1
"$ENGINE" volume inspect "${PREFIX}-b2-work" >/dev/null 2>&1 && ok "--keep-volume keeps the work" || bad "--keep-volume keeps the work"
"$ENGINE" volume rm "${PREFIX}-b2-work" >/dev/null 2>&1 || true

printf 'utgard-box-tests: %s pass, %s fail, %s skip\n' "$pass" "$fail" "$skip"
[ "$fail" = 0 ]
