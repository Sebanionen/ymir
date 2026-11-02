#!/usr/bin/env bash
# room.sh — the record of a room: append an utterance, or read what was said.
#
# A room is defined by WHO MAY HEAR IT, and its record is a file: append-only JSONL under
# `hodd/state/assistant/rooms/<room>.jsonl`. Nothing enters a room except through this door,
# and nothing leaves a record except by reading it. There is no rewrite and no delete — a
# conversation that exists only in a chat window does not exist.
#
# The registry (`hodd/identity/assistant/rooms.yaml`) names each room's members and its
# Telegram face. A speaker who is not named in a room's members is refused: a bot that was
# merely added to a group does not thereby belong to the conversation.
#
# CLI:
#   room.sh rooms                                  # the registry, one row per room
#   room.sh append --room R --speaker S --text "…" [--role ROLE] [--addressed a,b] [--reply-to N]
#   room.sh list --room R [--since N] [--addressed AGENT] [--limit N]
#   room.sh for --agent AGENT [--since N]          # every line addressed to an agent, all rooms
#   room.sh next-id --room R
#
# Exit: 0 ok · 2 usage · 3 room unknown · 4 unknown speaker · 5 store error · 6 refused at the door (markup / working stream)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo root, found by walking up to the tree that holds .pi and RULES — never counted in
# "../", because this shelf was moved once (bin/assistant/ -> systems/skirnir/, plan 149) and
# 25 scripts kept the old depth, so every $ROOT/bin/... pointed into systems/ instead (2026-11-02).
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)"
# shellcheck source=bin/vault/hoard-lib.sh
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true

VERSION="1.0.0"

usage() { sed -n '3,26p' "$0" | sed 's/^# \{0,1\}//'; }

home_or_die() {
  local h=""
  declare -f ymir_home_root >/dev/null 2>&1 && ymir_home_root h 2>/dev/null
  [ -n "$h" ] || h="${YMIR_HOME:-}"
  [ -n "$h" ] || { printf 'room[1]{error}: "the hoard is unresolved — set YMIR_HOME"\n' >&2; exit 5; }
  printf '%s' "$h"
}

H="$(home_or_die)"
REG="$H/hodd/identity/assistant/rooms.yaml"
STORE="$H/hodd/state/assistant/rooms"

case "${1-}" in -v|--version) printf '%s\n' "$VERSION"; exit 0 ;; -h|--help|"") usage; exit 0 ;; esac
CMD="$1"; shift

# room_field <room> <key> — read a field out of the registry (members come back comma-joined)
room_field() {
  python3 - "$REG" "$1" "$2" <<'PY'
import sys, yaml
reg, room, key = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    data = yaml.safe_load(open(reg)) or {}
except FileNotFoundError:
    print("MISSING"); raise SystemExit(0)
except Exception:
    print("BROKEN"); raise SystemExit(0)
for row in data.get("rooms", []) or []:
    if str(row.get("id")) == room:
        val = row.get(key)
        if isinstance(val, list):
            print(",".join(str(v) for v in val))
        elif val is None:
            print("")
        else:
            print(val)
        raise SystemExit(0)
print("UNKNOWN")
PY
}

need_room() {
  local f; f="$(room_field "$1" id)"
  case "$f" in
    UNKNOWN) printf 'room[1]{error}: "no such room in the registry: %s" · help: "room.sh rooms"\n' "$1" >&2; exit 3 ;;
    MISSING|BROKEN) printf 'room[1]{error}: "the registry is %s: %s"\n' "$f" "$REG" >&2; exit 5 ;;
  esac
}

# member <room> <speaker> → 0 if the speaker may speak in the room
member() {
  case ",$(room_field "$1" members)," in *",$2,"*) return 0 ;; esac
  case ",$(room_field "$1" agents)," in *",$2,"*) return 0 ;; esac
  return 1
}

cmd_rooms() {
  python3 - "$REG" <<'PY'
import sys, yaml
try:
    data = yaml.safe_load(open(sys.argv[1])) or {}
except FileNotFoundError:
    print('room[1]{error}: "no registry — the house has no rooms yet"'); raise SystemExit(5)
rooms = data.get("rooms", []) or []
print(f'rooms[{len(rooms)}]{{id,title,members,telegram,tier,addressed_only}}:')
for r in rooms:
    members = ",".join(str(m) for m in (r.get("members") or []))
    print(f'  "{r.get("id")}","{r.get("title","")}","{members}",'
          f'"{r.get("telegram") or "—"}","{r.get("tier","collaborator")}",'
          f'"{str(bool(r.get("addressed_only", True))).lower()}"')
PY
}

cmd_append() {
  local room="" speaker="" text="" role="" addressed="" reply=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --room) room=${2-}; shift 2 ;;
      --speaker) speaker=${2-}; shift 2 ;;
      --text) text=${2-}; shift 2 ;;
      --role) role=${2-}; shift 2 ;;
      --addressed) addressed=${2-}; shift 2 ;;
      --reply-to) reply=${2-}; shift 2 ;;
      *) printf 'room[1]{error}: "unknown flag: %s"\n' "$1" >&2; exit 2 ;;
    esac
  done
  [ -n "$room" ] && [ -n "$speaker" ] && [ -n "$text" ] || {
    printf 'room[1]{error}: "append needs --room, --speaker and --text"\n' >&2; exit 2; }
  need_room "$room"
  member "$room" "$speaker" || {
    printf 'room[1]{error}: "%s is not a member of %s — the room is refused, not extended"\n' \
      "$speaker" "$room" >&2; exit 4; }
  case "$room" in *[!a-z0-9-]*) printf 'room[1]{error}: "a room id is a lowercase slug"\n' >&2; exit 2 ;; esac

  # THE WALL. A room carries deliberate words — never thinking, never tool arguments, never tool
  # results, never markup. The append-only law (Rule 06) means a bad line can never be edited out,
  # so the refusal must happen HERE, before it is a line: a model that emits its own invocation
  # syntax (DSML `<|...|>` / `<｜...｜>`, `invoke name=`, `parameter name=`) is refused, loudly,
  # with nothing written. Learned the hard way twice in one night: a verbose activity stream into a
  # Telegram group, then raw invocation markup into this record (lines 37 and 40 of the-elders).
  if ! printf '%s' "$text" | python3 -c 'import sys, re
t = sys.stdin.read()
bad = [
    r"<\|[^|]*\|>", r"<｜[^｜]*｜>", r"<\|/?\w+", r"<｜/?\w+",
    r"\binvoke\s+name\s*=", r"\bparameter\s+name\s*=", r"\btool_calls?\b",
    r"\"tool_call\"", r"\bfunction_call\b",
]
hits = [p for p in bad if re.search(p, t, re.I)]
if hits:
    sys.exit(1)
sys.exit(0)' ; then
    printf 'room[1]{error}: "REFUSED at the door — the text carries tool-invocation markup or a working stream, not deliberate words. Nothing was written (Rule 06: a line cannot be edited out later)."\n' >&2
    printf 'room[1]{hint}: "an agent that cannot produce words must say so in words; post that instead"\n' >&2
    exit 6
  fi

  mkdir -p "$STORE" || exit 5
  local f="$STORE/$room.jsonl"
  (
    flock 9 || exit 5
    python3 - "$f" "$room" "$speaker" "$role" "$addressed" "$reply" "$text" <<'PY'
import sys, json, os, time
path, room, speaker, role, addressed, reply, text = sys.argv[1:8]
last = 0
if os.path.exists(path):
    with open(path, "rb") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                last = max(last, int(json.loads(line).get("id") or 0))
            except Exception:
                continue
line = {
    "id": last + 1,
    "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "room": room,
    "speaker": speaker,
    "role": role or "",
    "addressed": [a.strip() for a in addressed.split(",") if a.strip()] if addressed else [],
    "in_reply_to": int(reply) if reply else None,
    "text": text,
}
with open(path, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(line, ensure_ascii=False) + "\n")
print(f'room_line{{id,room,speaker,addressed,chars}}:\n  "{line["id"]}","{room}","{speaker}",'
      f'"{",".join(line["addressed"]) or "—"}","{len(text)}"')
PY
  ) 9>>"$f.lock"
  local rc=$?
  rm -f "$f.lock"
  exit $rc
}

cmd_list() {
  local room="" since=0 addressed="" limit=40
  while [ $# -gt 0 ]; do
    case "$1" in
      --room) room=${2-}; shift 2 ;;
      --since) since=${2-0}; shift 2 ;;
      --addressed) addressed=${2-}; shift 2 ;;
      --limit) limit=${2-40}; shift 2 ;;
      *) printf 'room[1]{error}: "unknown flag: %s"\n' "$1" >&2; exit 2 ;;
    esac
  done
  [ -n "$room" ] || { printf 'room[1]{error}: "list needs --room"\n' >&2; exit 2; }
  need_room "$room"
  local f="$STORE/$room.jsonl"
  [ -f "$f" ] || { printf 'room[1]{room,lines}:\n  "%s",0\n' "$room"; exit 0; }
  python3 - "$f" "$since" "$addressed" "$limit" <<'PY'
import sys, json
path, since, addressed, limit = sys.argv[1], int(sys.argv[2] or 0), sys.argv[3], int(sys.argv[4] or 40)
rows = []
for line in open(path, encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    try:
        row = json.loads(line)
    except Exception:
        continue
    if int(row.get("id") or 0) <= since:
        continue
    if addressed and addressed not in (row.get("addressed") or []):
        continue
    rows.append(row)
rows = rows[-limit:]
print(f'room_lines[{len(rows)}]{{id,ts,speaker,addressed,reply_to,text}}:')
for r in rows:
    text = " ".join(str(r.get("text", "")).split())[:200].replace('"', "'")
    print(f'  "{r["id"]}","{r.get("ts","")}","{r.get("speaker","")}",'
          f'"{",".join(r.get("addressed") or []) or "—"}","{r.get("in_reply_to") or "—"}","{text}"')
PY
}

cmd_for() {
  local agent="" since=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --agent) agent=${2-}; shift 2 ;;
      --since) since=${2-0}; shift 2 ;;
      *) printf 'room[1]{error}: "unknown flag: %s"\n' "$1" >&2; exit 2 ;;
    esac
  done
  [ -n "$agent" ] || { printf 'room[1]{error}: "for needs --agent"\n' >&2; exit 2; }
  python3 - "$STORE" "$agent" "$since" <<'PY'
import sys, json, os, glob
store, agent, since = sys.argv[1], sys.argv[2], int(sys.argv[3] or 0)
rows = []
for path in sorted(glob.glob(os.path.join(store, "*.jsonl"))):
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except Exception:
            continue
        if int(row.get("id") or 0) <= since:
            continue
        if agent in (row.get("addressed") or []):
            rows.append(row)
rows.sort(key=lambda r: r.get("ts", ""))
print(f'room_for[{len(rows)}]{{room,id,speaker,text}}:')
for r in rows[-40:]:
    text = " ".join(str(r.get("text", "")).split())[:200].replace('"', "'")
    print(f'  "{r.get("room")}","{r["id"]}","{r.get("speaker","")}","{text}"')
PY
}

cmd_next_id() {
  local room=${2-}
  [ -n "$room" ] || { printf 'room[1]{error}: "next-id needs --room"\n' >&2; exit 2; }
  need_room "$room"
  python3 - "$STORE/$room.jsonl" <<'PY'
import sys, json, os
last = 0
path = sys.argv[1]
if os.path.exists(path):
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if line:
            try: last = max(last, int(json.loads(line).get("id") or 0))
            except Exception: pass
print(last + 1)
PY
}

case "$CMD" in
  rooms) cmd_rooms "$@" ;;
  append) cmd_append "$@" ;;
  list) cmd_list "$@" ;;
  for) cmd_for "$@" ;;
  next-id) cmd_next_id "$@" ;;
  *) printf 'room[1]{error}: "unknown command: %s" · help: "room.sh --help"\n' "$CMD" >&2; exit 2 ;;
esac
