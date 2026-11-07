#!/usr/bin/env bash
# jev-doors.sh — where the decision models answer, in one read.
#
#   bin/model/jev-doors.sh list [--json]     # the registry, with a live probe
#   bin/model/jev-doors.sh url <id>          # the base URL for one door
#   bin/model/jev-doors.sh ask <id> <state-json> <questions-json>   # one call, raw JSON back
#
# The models are not chat models: they answer `POST /v1/systemone` with typed questions.
# The registry says which door is which, what it may be used for, and its licence — so a
# gate cannot accidentally pick the non-commercial one.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
ymir_home_root HOME_DIR 2>/dev/null || { printf "%s: the home is unresolved — call bin/vault/hoard-lib.sh\n" "$(basename "$0")" >&2; exit 2; }
REG="${JEV_DOORS:-$HOME/.config/ymir/jev-doors.yaml}"
[ -r "$REG" ] || REG="$HOME_DIR/config/jev-doors.yaml"
HOST="${JEV_DOOR_HOST:-}"   # never a default host: the operator names the door (Rule 24/39)

key() { bash "$ROOT/bin/vault/hodd.sh" emit secrets/platform.env 2>/dev/null | sed -n 's/^export LLAMA_SWAP_API_KEY=//p' | head -1 | tr -d '"'"'"''; }
rows() {
  [ -r "$REG" ] || return 0
  python3 - "$REG" <<'PY'
import sys
try:
    import yaml
except Exception:
    raise SystemExit(0)
d = yaml.safe_load(open(sys.argv[1])) or {}
for door in d.get("doors") or []:
    if not isinstance(door, dict):
        continue
    print("\t".join(str(door.get(k, "")) for k in ("id","model","port","license","role","gguf")))
PY
}
[ -n "$HOST" ] || HOST="$(bash "$ROOT/bin/bridge/seat-host.sh" 2>/dev/null || true)"
case "${1-}" in
  list)
    JSON=0; [ "${2-}" = "--json" ] && JSON=1
    K="$(key)"; tmp="$(mktemp)"; rows >"$tmp"
    python3 - "$tmp" "$HOST" "$K" "$JSON" <<'PY'
import json, subprocess, sys
path, host, key, as_json = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"
out = []
for line in open(path).read().splitlines():
    if not line.strip(): continue
    ident, model, port, lic, role, gguf = (line.split("\t") + [""]*6)[:6]
    up = False
    if port and port != "null" and port != "":
        body = json.dumps({"state":"x","questions":{"q":{"type":"noul","instructions":"ok?"}}})
        r = subprocess.run(["curl","-s","-o","/dev/null","-w","%{http_code}","--max-time","4",
                            "-X","POST",f"http://{host}:{port}/v1/systemone",
                            "-H","content-type: application/json","-H",f"Authorization: Bearer {key}","-d",body],
                           capture_output=True, text=True)
        up = r.stdout.strip() == "200"
    out.append({"id": ident, "model": model, "port": port, "license": lic, "role": role,
                "gguf": gguf, "url": f"http://{host}:{port}" if port and port != "null" else None,
                "state": "up" if up else ("no-door" if not port or port == "null" else "down")})
if as_json:
    print(json.dumps({"transport":"tailscale","wire":"systemone","doors":out}, indent=1))
else:
    print(f'jev_doors[{len(out)}]{{id,model,port,license,state}}:')
    for d in out:
        print(f'  "{d["id"]}","{d["model"]}","{d["port"]}","{d["license"]}","{d["state"]}"')
PY
    rm -f "$tmp" ;;
  url)
    id="${2-}"; rows | awk -F'\t' -v want="$id" '$1==want {print $3}' | head -1 | { read -r p; [ -n "$p" ] && [ "$p" != "null" ] && printf 'http://%s:%s/v1/systemone\n' "$HOST" "$p" || printf 'jev-doors: no reachable door for %s\n' "$id" >&2; } ;;
  ask)
    id="${2-}"; state="${3-}"; questions="${4-}"
    port="$(rows | awk -F'\t' -v want="$id" '$1==want {print $3}' | head -1)"
    [ -n "$port" ] && [ "$port" != "null" ] || { printf 'jev-doors: no door for %s\n' "$id" >&2; exit 2; }
    # ONE RAIL, ON DEMAND (2026-11-06): the router names the model in the body and swaps it
    # in; four always-on units held 11.6 GiB of a 16 GiB card and starved a 35B coder.
    model="$(rows | awk -F'\t' -v want="$id" '$1==want {print $2}' | head -1 | tr '[:upper:]' '[:lower:]')"
    curl -s -X POST "http://$HOST:$port/v1/systemone" -H 'content-type: application/json' \
      -H "Authorization: Bearer $(key)" \
      -d "{\"model\":\"$model\",\"state\":$state,\"questions\":$questions}" ;;
  *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
