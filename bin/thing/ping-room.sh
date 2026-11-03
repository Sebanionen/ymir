#!/usr/bin/env bash
# ping-room.sh — Þing on demand: raise a MiroTalk room on the computer you are on.
#
# The room must never be assumed. It is raised when a meeting needs it, published by
# Tailscale Serve/Funnel or the ping.zerwiz.org tunnel claim, and lowered after.
#
# Usage:
#   ping-room.sh start [--port N] [--mode local|tailnet|public] [--title T]
#   ping-room.sh stop
#   ping-room.sh status
#   ping-room.sh url
#   ping-room.sh claim   # ping.zerwiz.org via the Cloudflare tunnel
#   ping-room.sh release
#
# Env:
#   YMIR_HOME             the hoard (default: the one resolver's answer)
#   PING_MIROTALK_DIR     a MiroTalk checkout (default: ~/thing/mirotalk if present)
#   PING_CMD              override the room command (tests); PORT is exported
#   PING_IMAGE            docker image to run when no checkout exists
#   PING_STATE            state file (default <home>/hodd/state/thing/room.json)
#
# Exit: 0 ok · 1 error · 2 usage · 3 refused (already raised / claim held)
set -euo pipefail
VERSION="1.0.0"
case "${1-}" in -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help|"") sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac

if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  _yh="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  for _i in 1 2 3 4 5; do [ -n "$_yh" ] || break
    if [ -r "$_yh/bin/vault/hoard-lib.sh" ]; then . "$_yh/bin/vault/hoard-lib.sh"; YMIR_HOARD_LIB_LOADED=1; break; fi
    if [ -r "$_yh/hoard-lib.sh" ]; then . "$_yh/hoard-lib.sh"; YMIR_HOARD_LIB_LOADED=1; break; fi
    _yh="$(cd "$_yh/.." 2>/dev/null && pwd)"; done
  unset _yh _i
fi
ymir_home_root YMIR_HOME 2>/dev/null || true
YMIR_HOME="${YMIR_HOME:?YMIR_HOME unresolved}"
STATE="${PING_STATE:-$YMIR_HOME/hodd/state/thing/room.json}"
mkdir -p "$(dirname "$STATE")"
ROOM_DIR="${PING_MIROTALK_DIR:-$HOME/thing/mirotalk}"
PORT="${PING_PORT:-3010}"
MODE="local"; TITLE="Þing"; ACTION="${1-}"

die(){ printf 'error: %s\n' "$*" >&2; exit 1; }
usage(){ sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
json(){ python3 - "$@" <<'PY'
import json,sys
p=sys.argv[1]; cmd=sys.argv[2]
try: d=json.load(open(p))
except Exception: d={}
if cmd=="get":
    v=d
    for k in sys.argv[3].split('.'):
        if not isinstance(v,dict) or k not in v: sys.exit(1)
        v=v[k]
    print(v)
elif cmd=="set":
    d[sys.argv[3]]=sys.argv[4]
    json.dump(d,open(p,'w'),indent=2)
PY
}
alive(){ local pid; pid="$(json "$STATE" get pid 2>/dev/null || true)"; [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; }
public_url(){ local host; host="$(hostname)"; printf 'https://%s.<host>.tailnet.ts.net' "$host"; }

cmd_start(){
  while [ $# -gt 0 ]; do case "$1" in
    --port) PORT="${2-}"; shift 2 ;;
    --mode) MODE="${2-}"; shift 2 ;;
    --title) TITLE="${2-}"; shift 2 ;;
    *) die "unknown option: $1" ;; esac; done
  case "$MODE" in local|tailnet|public) ;; *) die "mode must be local|tailnet|public" ;; esac
  alive && { printf 'refused\troom already raised\tpid:%s\n' "$(json "$STATE" get pid)"; exit 3; }
  local cmd=""
  if [ -n "${PING_CMD:-}" ]; then cmd="$PING_CMD"
  elif [ -d "$ROOM_DIR" ]; then cmd="node $ROOM_DIR/app/src/server.js"
  elif [ -n "${PING_IMAGE:-}" ] && command -v docker >/dev/null; then cmd="docker run --rm -p 127.0.0.1:$PORT:3000 -e PORT=3000 $PING_IMAGE"
  else die "no MiroTalk: set PING_MIROTALK_DIR, PING_IMAGE, or PING_CMD"; fi
  local log="$YMIR_HOME/hodd/state/thing/room.log"
  ( export PORT HOST=127.0.0.1 NODE_ENV=production; exec $cmd ) >>"$log" 2>&1 &
  local pid=$!
  sleep 2
  kill -0 "$pid" 2>/dev/null || die "room failed to start — see $log"
  local url="http://127.0.0.1:$PORT"
  if [ "$MODE" != local ]; then
    if command -v tailscale >/dev/null; then
      if [ "$MODE" = public ]; then tailscale funnel --bg "$PORT" >>"$log" 2>&1 || die "tailscale funnel failed"; else tailscale serve --bg "$PORT" >>"$log" 2>&1 || die "tailscale serve failed"; fi
      url="$(public_url)"
    else die "mode $MODE needs tailscale"; fi
  fi
  python3 - "$STATE" "$pid" "$url" "$MODE" "$TITLE" "$PORT" <<'PY'
import json,sys,datetime
p,pid,url,mode,title,port=sys.argv[1:]
json.dump({"pid":int(pid),"url":url,"mode":mode,"title":title,"port":int(port),
 "since":datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
 "host":__import__("socket").gethostname()},open(p,'w'),indent=2)
PY
  printf 'raised\t%s\tpid:%s\n' "$url" "$pid"
}

cmd_stop(){
  alive || { rm -f "$STATE"; printf 'lowered\tnothing was raised\n'; return 0; }
  local pid; pid="$(json "$STATE" get pid)"
  kill "$pid" 2>/dev/null || true
  command -v tailscale >/dev/null && { tailscale serve reset >/dev/null 2>&1 || true; tailscale funnel reset >/dev/null 2>&1 || true; }
  rm -f "$STATE"; printf 'lowered\tpid:%s\n' "$pid"
}

cmd_status(){
  if alive; then printf 'room\tup\t%s\tmode:%s\tpid:%s\n' "$(json "$STATE" get url)" "$(json "$STATE" get mode)" "$(json "$STATE" get pid)"
  else printf 'room\tdown\n'; fi
}
cmd_url(){ alive && json "$STATE" get url || { printf 'room down\n' >&2; exit 1; }; }
cmd_claim(){
  alive || die "raise the room first"
  command -v cloudflared >/dev/null || die "cloudflared not installed"
  if [ -f "$YMIR_HOME/hodd/state/thing/claim.json" ]; then
    local h; h="$(python3 -c "import json;print(json.load(open('$YMIR_HOME/hodd/state/thing/claim.json')).get('host',''))" 2>/dev/null || true)"
    [ "$h" = "$(hostname)" ] || { printf 'refused\tclaim held by %s\n' "$h"; exit 3; }
  fi
  printf '{"host":"%s","since":"%s","url":"https://ping.zerwiz.org"}\n' "$(hostname)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$YMIR_HOME/hodd/state/thing/claim.json"
  printf 'claimed\tping.zerwiz.org\t%s\n' "$(hostname)"
}
cmd_release(){ rm -f "$YMIR_HOME/hodd/state/thing/claim.json"; printf 'released\tping.zerwiz.org\n'; }

case "$ACTION" in
  start) shift; cmd_start "$@" ;;
  stop) cmd_stop ;;
  status) cmd_status ;;
  url) cmd_url ;;
  claim) cmd_claim ;;
  release) cmd_release ;;
  *) usage ;;
esac
