#!/usr/bin/env bash
# lock-ask.sh — a read-only agent asks the LOCK OWNER for work, and the owner answers.
#
# WHY (the Allfather, 2026-11-06): *"any read only agent should be able to message the owner
# of the lock and ask if they can do tasks."* A judge may not write, may not edit and may not
# merge — that is its charter and it stays. What it lacked was a MOUTH: a way to say "may I
# take this task" to the one process on this machine that holds the lock and the arm, and to
# hear the answer. Without it a read-only agent is silent by construction, and silence reads
# as consent to whoever is waiting.
#
# THE GROUND IS THE HOUSE'S OWN, never a new bus:
#   the lock     the machine-global lock, resolved by bin/vault/gleipnir-lock-lib.sh (one live
#                primary per machine; the path is never written here)
#   the arm      $STATE/.arm.lease                                        (pid, starttime, state=)
#   the queue    <state>/.wake-queue                                      (the arm's own inbox, drained into the session)
#   the asks     $STATE/asks/<ask-id>.jsonl                               (one file per ask, append-only)
#   the inbox    $STATE/asks/<agent>.inbox.jsonl                          (the owner's answers, appended)
#   the room     $HOME/hodd/rooms/the-fleet/<speaker>.jsonl               (the durable trace, as seat-wire writes it)
#
# FOUR LAWS THIS DOOR HOLDS:
#   1 · AN ASK IS NOT A GRANT. The owner's answer is the owner's word — never the Allfather's,
#       never a licence to merge, deploy or spend. A merge still needs RULES/08 and his hand.
#   2 · ONE ANSWER PER ASK. A second answer is refused by name, not silently overwritten.
#   3 · THE OWNER ANSWERS, NOBODY ELSE. `answer` proves the caller descends from the live lock
#       owner; a stranger with the file path cannot speak as the owner.
#   4 · A REFUSAL NAMES THE ROAD. No lock, a dead owner, a lock and an arm that disagree — each
#       is reported as what it is, never as "nothing to do".
#
# Usage:
#   lock-ask.sh who                                  # the lock, the arm, the queue, and me
#   lock-ask.sh ask "<question>" [--task <id>] [--as <agent>] [--json]
#   lock-ask.sh list [--all] [--json]                # open asks (or every ask)
#   lock-ask.sh inbox [<agent>] [--all] [--json]     # answers for me (or the named agent)
#   lock-ask.sh answer <ask-id> "<text>" [--json]    # the lock owner only
#   lock-ask.sh close <ask-id> [--as <agent>]        # the asker marks an answer read
#   lock-ask.sh --version
#
# Exit: 0 ok · 1 a fault (named) · 2 usage · 3 refused (the reason names the road).
set -u
VERSION="1.0.0"
SELF="$(basename "$0")"

case "${1-}" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help|"") sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"

# The home and the state are RESOLVED, never guessed (Rule 04/07, defaults-guard).
if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  for _c in "$ROOT/bin/vault/hoard-lib.sh" "$SCRIPT_DIR/../vault/hoard-lib.sh"; do
    [ -r "$_c" ] && { . "$_c"; YMIR_HOARD_LIB_LOADED=1; break; }
  done
  unset _c
fi
HOME_DIR=""; hoard_state_dir HOME_DIR 2>/dev/null || true
STATE="${HOME_DIR:-${YMIR_STATE_DIR:-}}"
[ -n "$STATE" ] || { printf 'lock-ask: the state dir is unresolved — bin/vault/hoard-lib.sh names it\n' >&2; exit 1; }

STATE_DOOR="$ROOT/bin/records/ymir-state.sh"
# The lock's own library, so this door never re-implements where the lock lives (Gleipnir's shim
# exists for exactly that: one implementation, many readers).
for _gl in "$ROOT/bin/vault/gleipnir-lock-lib.sh" "$SCRIPT_DIR/../vault/gleipnir-lock-lib.sh"; do
  [ -r "$_gl" ] && { . "$_gl"; break; }
done
unset _gl
die()  { printf 'lock-ask: %s\n' "$*" >&2; exit 1; }
usage(){ printf 'lock-ask: %s\n' "$*" >&2; exit 2; }
refuse(){ printf 'lock-ask: REFUSED — %s\n' "$*" >&2; exit 3; }
now()  { date -u +%Y-%m-%dT%H:%M:%SZ; }
json_escape() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' ; }

# ── the lock and the arm ───────────────────────────────────────────────────────────────────────
lock_path() {
  local p=""
  if command -v gleipnir_lock_path >/dev/null 2>&1; then
    gleipnir_lock_path p 2>/dev/null || true
  fi
  if [ -z "$p" ] && [ -x "$STATE_DOOR" ]; then
    p="$("$STATE_DOOR" lock lock-path 2>/dev/null || true)"
  fi
  [ -n "$p" ] || return 1
  printf '%s' "$p"
}
lock_owner_pid() {
  local p; p="$(lock_path)"
  [ -r "$p" ] || return 1
  local pid; pid="$(head -1 "$p" 2>/dev/null | tr -dc '0-9')"
  [ -n "$pid" ] || return 1
  printf '%s' "$pid"
}
pid_starttime() { awk '{print $22}' "/proc/$1/stat" 2>/dev/null; }
pid_alive_since() {  # <pid> <starttime>
  local pid=$1 st=${2-} cur
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  [ -r "/proc/$pid/stat" ] || return 1
  cur="$(pid_starttime "$pid")"
  [ -n "$st" ] && [ "$cur" != "$st" ] && return 1
  return 0
}
# The lock's recorded starttime is a sibling file written by the one lock implementation.
lock_starttime() { local p; p="$(lock_path)"; sed -n '1p' "$p.starttime" 2>/dev/null | tr -dc '0-9'; }

lease_field() {  # <field>
  local f=$1 l="$STATE/.arm.lease"
  [ -r "$l" ] || return 1
  sed -n "s/.*\b$f=\([^ ]*\).*/\1/p" "$l" | head -1
}
arm_pid()     { lease_field pid; }
arm_session() { lease_field session; }
arm_state()   { lease_field state; }

# ── who is asking ──────────────────────────────────────────────────────────────────────────────
seat_primary() {
  local f="$HOME/.pi/agent/extensions/.ymir-seat"
  [ -r "$f" ] && sed -n 's/^primary=//p' "$f" | head -1
}
self_agent() {
  printf '%s' "${YMIR_AGENT:-${YMIR_SMITH:-$(seat_primary || true)}}"
}
is_descendant_of() {  # <ancestor> <pid> — the answer may only come from under the owner
  local anc=$1 pid=$2 hops=0 ppid
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  while [ "$hops" -lt 40 ]; do
    [ "$pid" = "$anc" ] && return 0
    [ -r "/proc/$pid/stat" ] || return 1
    ppid="$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null)"
    case "$ppid" in ''|0|1|*[!0-9]*) return 1 ;; esac
    pid=$ppid; hops=$((hops + 1))
  done
  return 1
}

room_line() {  # <speaker> <text>
  local sh="$HOME_DIR/../hodd/bin/room.sh" speaker=$1 text=$2
  [ -r "$sh" ] || sh="${HOME_DIR%/state}/hodd/bin/room.sh"
  if [ -x "$sh" ]; then "$sh" say the-fleet "$speaker" "$text" >/dev/null 2>&1 || true; return 0; fi
  local room="${HOME_DIR%/state}/hodd/rooms/the-fleet/$speaker.jsonl"
  mkdir -p "$(dirname "$room")" 2>/dev/null || return 0
  python3 - "$room" "$speaker" "$text" <<'PY' 2>/dev/null || true
import json, sys, datetime, pathlib
p, speaker, text = sys.argv[1], sys.argv[2], sys.argv[3]
line = {"ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "from": speaker, "text": text, "reply_to": None}
with open(p, "a") as f:
    f.write(json.dumps(line) + "\n")
PY
}

# ── who ────────────────────────────────────────────────────────────────────────────────────────
cmd_who() {
  local lp pid pst live lpid lsession lstate agree me
  lp="$(lock_path)"
  pid="$(lock_owner_pid || true)"; pst="$(lock_starttime || true)"
  live=no; [ -n "$pid" ] && pid_alive_since "$pid" "$pst" && live=yes
  lpid="$(arm_pid || true)"; lsession="$(arm_session || true)"; lstate="$(arm_state || true)"
  agree=unknown
  case "${lsession:-}" in
    ""|none|null) agree="unknown (the arm names no session)" ;;
    *)
      if [ -n "$pid" ]; then
        [ "$pid" = "$lsession" ] && agree=yes || agree="NO (lock pid $pid, arm session $lsession)"
      fi ;;
  esac
  me="$(self_agent)"
  printf 'lock[7]{lock,owner_pid,live,arm_pid,arm_session,agree,queue}:\n  "%s","%s","%s","%s","%s","%s","%s/.wake-queue"\n' \
    "$lp" "${pid:-none}" "$live" "${lpid:-none}" "${lsession:-none}" "$agree" "${lstate:-$STATE}"
  printf 'me[1]{agent,descends_from_owner}:\n  "%s","%s"\n' "${me:-unknown}" \
    "$(if [ -n "$pid" ] && is_descendant_of "$pid" "$$"; then printf yes; else printf no; fi)"
  case "$agree" in
    yes|unknown*) : ;;
    *)
    printf 'finding[1]{what,why}:\n  "the lock and the arm disagree","the arm drains a queue the lock owner may not read — a wake written to it is a message into a room nobody stands in"\n' ;;
  esac
  return 0
}

# ── ask ────────────────────────────────────────────────────────────────────────────────────────
cmd_ask() {
  local text="" task="" as="" json=0
  while [ $# -gt 0 ]; do case "$1" in
    --task) task="${2:-}"; shift 2 ;;
    --as)   as="${2:-}"; shift 2 ;;
    --json) json=1; shift ;;
    *) if [ -z "$text" ]; then text="$1"; else text="$text $1"; fi; shift ;;
  esac; done
  [ -n "$text" ] || usage 'ask needs a question: lock-ask.sh ask "may I take PR 552"'
  case "$text" in *$'\e'*|*$'\r'*|*$'\n'*) die 'refusing text with control sequences — one plain line only' ;; esac
  [ "${#text}" -le 4000 ] || die 'refusing text longer than 4000 characters — one line, not a file'

  local pid pst live lsession lstate queue me id f ts
  pid="$(lock_owner_pid || true)"; pst="$(lock_starttime || true)"
  [ -n "$pid" ] || refuse "there is NO lock on this machine — nobody holds it, so there is nobody to ask; a read-only agent waits for a primary rather than deciding for one"
  live=no; pid_alive_since "$pid" "$pst" && live=yes
  [ "$live" = yes ] || refuse "the lock names pid '$pid', which is not a live process — a dead owner cannot answer, and a question into a dead queue is a message in a bottle"
  lsession="$(arm_session || true)"; lstate="$(arm_state || true)"
  queue="${lstate:-$STATE}/.wake-queue"
  [ -d "${lstate:-$STATE}" ] || refuse "the arm lease names state '$lstate', which does not exist — the queue path cannot be resolved from it"
  case "${lsession:-}" in
    ""|none|null) : ;;   # the arm names no session; the queue it drains is still its own `state=`
    *) [ "$lsession" = "$pid" ] || refuse "the lock owner (pid $pid) and the arm (session $lsession) DISAGREE — a wake would be written to a queue the lock owner does not drain; fix the lease first (bin/pi/syn-watch.sh) and ask again" ;;
  esac

  me="${as:-$(self_agent)}"; [ -n "$me" ] || me=unknown
  mkdir -p "$STATE/asks" || die "cannot create the asks shelf $STATE/asks"
  ts="$(now)"
  id="ask-$(printf '%s' "$ts" | tr -d ':-' )-$(printf '%04x' "$((RANDOM % 65536))")"
  f="$STATE/asks/$id.jsonl"
  python3 - "$f" "$id" "$me" "$ts" "$task" "$text" <<'PY' || die "the ask could not be written to $f"
import json, sys
f, i, who, ts, task, text = sys.argv[1:7]
with open(f, "a") as fh:
    fh.write(json.dumps({"kind": "ask", "id": i, "from": who, "at": ts,
                         "task": task or None, "text": text}) + "\n")
PY

  # The wake: the arm drains this into the owner's session between turns.
  { printf 'lock-ask %s from=%s at=%s q=%s\n' "$id" "$me" "$ts" "$text"; } >>"$queue" \
    || die "the queue write to $queue failed — nothing was asked, and nothing claims it was"

  room_line "$me" "asks the lock owner (pid $pid): $text  [ask $id]"
  if [ "$json" = 1 ]; then
    printf '{"ask":"%s","from":"%s","queue":"%s","owner_pid":"%s","answer_lands":"%s/asks/%s.inbox.jsonl"}\n' \
      "$id" "$me" "$queue" "$pid" "$STATE" "$me"
  else
    printf 'ask[5]{id,from,owner_pid,queue,answer_lands}:\n  "%s","%s","%s","%s","%s/asks/%s.inbox.jsonl"\n' \
      "$id" "$me" "$pid" "$queue" "$STATE" "$me"
    printf 'law[1]{rule}:\n  "an answer is the owner'"'"'s word, not the Allfather'"'"'s — a merge still needs RULES/08 and his hand"\n'
  fi
  return 0
}

# ── answer ─────────────────────────────────────────────────────────────────────────────────────
cmd_answer() {
  local id="${1:-}"; shift || true
  local text="$*" json=0
  case "$text" in *--json*) json=1; text="${text% --json}" ;; esac
  [ -n "$id" ] && [ -n "$text" ] || usage 'answer needs: lock-ask.sh answer <ask-id> "<text>"'

  local pid pst
  pid="$(lock_owner_pid || true)"; pst="$(lock_starttime || true)"
  [ -n "$pid" ] || refuse "no lock is held on this machine — there is no owner to answer with"
  pid_alive_since "$pid" "$pst" || refuse "the lock names pid '$pid', which is not live — a dead owner does not answer"
  is_descendant_of "$pid" "$$" \
    || refuse "this process does not descend from the lock owner (pid $pid) — only the owner answers; an asker that answers itself is the loop this door exists to prevent"

  local f="$STATE/asks/$id.jsonl"
  [ -r "$f" ] || refuse "no such ask '$id' in $STATE/asks — an answer to a question nobody asked is not a record"
  if grep -q '"kind": *"answer"' "$f" 2>/dev/null; then
    refuse "ask '$id' is ALREADY answered — a second answer is refused by name, never written over the first"
  fi
  local from; from="$(python3 -c 'import json,sys;print(json.loads(open(sys.argv[1]).readline())["from"])' "$f" 2>/dev/null)"
  [ -n "$from" ] || die "ask '$id' has no readable asker — the file is malformed"
  local ts; ts="$(now)"
  python3 - "$f" "$id" "$from" "$ts" "$text" "$pid" <<'PY' || die "the answer could not be appended to $f"
import json, sys
f, i, who, ts, text, owner = sys.argv[1:7]
with open(f, "a") as fh:
    fh.write(json.dumps({"kind": "answer", "ask": i, "to": who, "at": ts,
                         "owner_pid": int(owner), "text": text}) + "\n")
PY
  local inbox="$STATE/asks/$from.inbox.jsonl"
  python3 - "$inbox" "$id" "$from" "$ts" "$text" "$pid" <<'PY' || die "the answer could not be written to the asker's inbox"
import json, sys
p, i, who, ts, text, owner = sys.argv[1:7]
with open(p, "a") as fh:
    fh.write(json.dumps({"kind": "answer", "ask": i, "from": "lock-owner", "owner_pid": int(owner),
                         "to": who, "at": ts, "text": text}) + "\n")
PY
  room_line "lock-owner" "answers $id (asked by $from): $text"
  if [ "$json" = 1 ]; then
    printf '{"answered":"%s","to":"%s","inbox":"%s"}\n' "$id" "$from" "$inbox"
  else
    printf 'answer[3]{ask,to,inbox}:\n  "%s","%s","%s"\n' "$id" "$from" "$inbox"
  fi
  return 0
}

# ── inbox ──────────────────────────────────────────────────────────────────────────────────────
cmd_inbox() {
  local who="" all=0 json=0
  while [ $# -gt 0 ]; do case "$1" in
    --all) all=1; shift ;; --json) json=1; shift ;;
    *) [ -z "$who" ] && who="$1"; shift ;;
  esac; done
  [ -n "$who" ] || who="$(self_agent)"
  [ -n "$who" ] || who=unknown
  local f="$STATE/asks/$who.inbox.jsonl"
  [ -r "$f" ] || { printf 'inbox[1]{agent,answers}:\n  "%s","0"\n' "$who"; return 0; }
  python3 - "$f" "$who" "$all" "$json" "$STATE/asks/$who.seen" <<'PY'
import json, sys, os
f, who, allf, js, seenp = sys.argv[1:6]
rows = []
for line in open(f):
    line = line.strip()
    if not line: continue
    try: rows.append(json.loads(line))
    except Exception: continue
seen = set()
if os.path.exists(seenp):
    seen = {l.strip() for l in open(seenp) if l.strip()}
out = rows if allf == "1" else [r for r in rows if r.get("ask") not in seen]
if js == "1":
    print(json.dumps({"agent": who, "answers": out, "unread": len(out)})); raise SystemExit
print(f'inbox[2]{{agent,unread}}:\n  "{who}","{len(out)}"')
for r in out:
    print(f'answer[3]{{ask,at,text}}:\n  "{r.get("ask")}","{r.get("at")}","{r.get("text","").replace(chr(34), chr(39))}"')
PY
}

# ── list ──────────────────────────────────────────────────────────────────────────────────────
cmd_list() {
  local all=0 json=0
  while [ $# -gt 0 ]; do case "$1" in --all) all=1; shift ;; --json) json=1; shift ;; *) shift ;; esac; done
  python3 - "$STATE/asks" "$all" "$json" <<'PY'
import json, sys, os, glob
d, allf, js = sys.argv[1:4]
rows = []
for p in sorted(glob.glob(os.path.join(d, "ask-*.jsonl"))):
    ask = ans = None
    for line in open(p):
        line = line.strip()
        if not line: continue
        try: r = json.loads(line)
        except Exception: continue
        if r.get("kind") == "ask": ask = r
        elif r.get("kind") == "answer": ans = r
    if not ask: continue
    state = "answered" if ans else "open"
    if allf != "1" and state != "open": continue
    rows.append({"id": ask.get("id"), "from": ask.get("from"), "at": ask.get("at"),
                 "task": ask.get("task"), "text": ask.get("text"), "state": state,
                 "answer": (ans or {}).get("text")})
if js == "1":
    print(json.dumps({"asks": rows})); raise SystemExit
print(f'asks[2]{{open,shown}}:\n  "{sum(1 for r in rows if r["state"]=="open")}","{len(rows)}"')
for r in rows:
    print(f'ask[5]{{id,from,at,state,text}}:\n  "{r["id"]}","{r["from"]}","{r["at"]}","{r["state"]}","{(r["text"] or "").replace(chr(34), chr(39))}"')
PY
}

# ── close ─────────────────────────────────────────────────────────────────────────────────────
cmd_close() {
  local id="${1:-}" who=""
  shift || true
  [ -n "$id" ] || usage 'close needs an ask id'
  while [ $# -gt 0 ]; do case "$1" in --as) who="${2:-}"; shift 2 ;; *) shift ;; esac; done
  [ -n "$who" ] || who="$(self_agent)"; [ -n "$who" ] || who=unknown
  [ -r "$STATE/asks/$id.jsonl" ] || refuse "no such ask '$id'"
  mkdir -p "$STATE/asks"
  printf '%s\n' "$id" >>"$STATE/asks/$who.seen"
  printf 'closed[2]{ask,by}:\n  "%s","%s"\n' "$id" "$who"
}

case "${1-}" in
  who)    shift; cmd_who "$@" ;;
  ask)    shift; cmd_ask "$@" ;;
  answer) shift; cmd_answer "$@" ;;
  inbox)  shift; cmd_inbox "$@" ;;
  list)   shift; cmd_list "$@" ;;
  close)  shift; cmd_close "$@" ;;
  *) usage "unknown action '${1-}' — who | ask | list | inbox | answer | close" ;;
esac
