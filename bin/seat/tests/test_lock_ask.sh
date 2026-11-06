#!/usr/bin/env bash
# The ward for bin/seat/lock-ask.sh — a read-only agent asks the lock owner, and only the
# owner answers.
#
# WHY (the Allfather, 2026-11-06): a judge that may not write must still be able to ASK.
# These proofs are the ones that keep the door honest:
#   · an ask lands in the owner's own queue, with an id, and the asker is on the record;
#   · the OWNER answers and the asker reads it; a process outside the owner's tree cannot;
#   · one answer per ask — a second is refused by name, never written over the first;
#   · closing marks it read;
#   · a dead owner, no lock at all, and a lock that disagrees with the arm are each REFUSED
#     with the road named — never reported as "nothing to do".
#
# Written as functions, not nested `bash -c` strings: the door's own refusals are the
# subject, so the harness must not be the thing that breaks (paid for once tonight).
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
DOOR="$root/bin/seat/lock-ask.sh"
ok=0; fail=0
t() { local n=$1; shift; if ( "$@" ) >/tmp/.la.$$ 2>&1; then ok=$((ok+1)); printf 'ok   %s\n' "$n"; else fail=$((fail+1)); printf 'FAIL %s\n' "$n"; sed -n '1,5p' /tmp/.la.$$; fi; }

# A hermetic machine: its own state shelf, its own lock, its own lease. The lock owner is
# THIS shell's pid, so a child process descends from it and may answer — the exact relation
# the door is meant to test.
D="$(mktemp -d)"
mkdir -p "$D/state" "$D/xdg/ymir"
own_lock() {
  printf '%s\n' "$$" > "$D/xdg/ymir/brokk.lock"
  awk '{print $22}' "/proc/$$/stat" > "$D/xdg/ymir/brokk.lock.starttime"
  printf 'pid=1 starttime=0 gen=1 mode=test session=%s heartbeat=0 state=%s\n' "$$" "$D/state" > "$D/state/.arm.lease"
}
own_lock
export YMIR_STATE_DIR="$D/state" XDG_STATE_HOME="$D/xdg"

last_ask() {  # <asker> — the newest ask id for that asker, answered or not
  python3 - "$D/state/asks" "$1" <<'PY2'
import glob, json, sys
d, who = sys.argv[1], sys.argv[2]
best = None
for p in sorted(glob.glob(d + "/ask-*.jsonl")):
    for line in open(p):
        line = line.strip()
        if not line: continue
        r = json.loads(line)
        if r.get("kind") == "ask" and r.get("from") == who:
            best = r["id"]
print(best or "")
PY2
}

ask_id() {  # <asker> — the newest open ask id for that asker
  python3 - "$D/state/asks" "$1" <<'PY'
import glob, json, sys
d, who = sys.argv[1], sys.argv[2]
best = None
for p in sorted(glob.glob(d + "/ask-*.jsonl")):
    ask = ans = None
    for line in open(p):
        line = line.strip()
        if not line: continue
        r = json.loads(line)
        if r.get("kind") == "ask": ask = r
        elif r.get("kind") == "answer": ans = r
    if ask and ask.get("from") == who and not ans:
        best = ask["id"]
print(best or "")
PY
}

p_who() {
  bash "$DOOR" who | grep -q '"yes"' && bash "$DOOR" who | grep -q 'descends_from_owner'
}

p_ask_lands() {
  bash "$DOOR" ask 'may I judge PR 552' --task pr-552 --as forseti >/dev/null || return 1
  grep -q 'lock-ask ask-' "$D/state/.wake-queue" || return 1
  grep -h '"kind": "ask"' "$D"/state/asks/ask-*.jsonl | grep -q '"from": "forseti"'
}

p_owner_answers() {
  local id; id="$(ask_id forseti)"
  [ -n "$id" ] || return 1
  bash "$DOOR" answer "$id" 'judge it, do not merge' >/dev/null || return 1
  bash "$DOOR" inbox forseti | grep -q 'judge it, do not merge'
}

p_second_answer_refused() {
  local id; id="$(last_ask forseti)"
  [ -n "$id" ] || return 1
  bash "$DOOR" answer "$id" 'again' >/tmp/.la2 2>&1
  local rc=$?
  [ "$rc" = 3 ] && grep -q 'ALREADY answered' /tmp/.la2
}

p_stranger_refused() {
  bash "$DOOR" ask 'may I touch the record' --as huginn >/dev/null || return 1
  local id; id="$(ask_id huginn)"
  [ -n "$id" ] || return 1
  setsid --fork bash -c "bash '$DOOR' answer '$id' nope >/tmp/.la3 2>&1"
  sleep 0.4
  grep -q 'does not descend from the lock owner' /tmp/.la3
}

p_close_marks_read() {
  local id; id="$(last_ask forseti)"
  [ -n "$id" ] || return 1
  bash "$DOOR" close "$id" --as forseti >/dev/null || return 1
  bash "$DOOR" inbox forseti --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["unread"]==0, d'
}

p_dead_owner_refused() {
  printf '999999\n' > "$D/xdg/ymir/brokk.lock"
  printf 'pid=999999 starttime=1 gen=1 mode=test session=999999 state=%s\n' "$D/state" > "$D/state/.arm.lease"
  bash "$DOOR" ask 'anyone there' >/tmp/.la4 2>&1
  local rc=$?
  own_lock
  [ "$rc" = 3 ] && grep -q 'not a live process' /tmp/.la4
}

p_no_lock_refused() {
  rm -f "$D/xdg/ymir/brokk.lock"
  bash "$DOOR" ask 'anyone there' >/tmp/.la5 2>&1
  local rc=$?
  own_lock
  [ "$rc" = 3 ] && grep -q 'there is NO lock' /tmp/.la5
}

p_disagree_refused() {
  printf 'pid=1 starttime=0 gen=1 mode=test session=424242 heartbeat=0 state=%s\n' "$D/state" > "$D/state/.arm.lease"
  bash "$DOOR" ask 'anyone there' >/tmp/.la6 2>&1
  local rc=$?
  own_lock
  [ "$rc" = 3 ] && grep -q 'DISAGREE' /tmp/.la6
}

t "who reports the lock, the arm and that they agree" p_who
t "an ask lands in the owner's queue with an id, and the asker is on the record" p_ask_lands
t "the owner answers, and the asker reads it" p_owner_answers
t "a second answer to the same ask is REFUSED by name" p_second_answer_refused
t "a process outside the owner's tree cannot answer" p_stranger_refused
t "closing marks the answer read" p_close_marks_read
t "a dead owner cannot be asked" p_dead_owner_refused
t "no lock at all is a refusal that names the road" p_no_lock_refused
t "a lock and an arm that disagree are refused, not guessed" p_disagree_refused

rm -rf "$D" /tmp/.la.$$ /tmp/.la2 /tmp/.la3 /tmp/.la4 /tmp/.la5 /tmp/.la6
printf 'lock-ask door: %s ok / %s fail\n' "$ok" "$fail"
[ "$fail" = 0 ]
