#!/usr/bin/env bash
# room-wall-test.sh — the room door's assertions, deterministic and offline.
#
# The room is append-only (Rule 06): a bad line can never be edited out, so the ONLY place a bad
# line can be stopped is the door. This suite proves the door stops it — and that it still lets
# deliberate words through, which is the easy half everyone forgets to test.
#
# Every case runs against a THROWAWAY home (a temp dir with its own registry and record), so the
# real rooms are never touched.
#
# Usage: systems/skirnir/services/room-wall-test.sh [--verbose]
# Exit:  0 all pass · 1 a failure
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo root, found by walking up to the tree that holds .pi and RULES — never counted in
# "../", because this shelf was moved once (bin/assistant/ -> systems/skirnir/, plan 149) and
# 25 scripts kept the old depth, so every $ROOT/bin/... pointed into systems/ instead (2026-11-02).
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)"
VERBOSE=0; [ "${1-}" = "--verbose" ] && VERBOSE=1

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/hodd/identity/assistant" "$TMP/hodd/state/assistant/rooms"
cat > "$TMP/hodd/identity/assistant/rooms.yaml" <<'YAML'
rooms:
- id: test-room
  title: a room for the wall
  members: [allfather, brokk, kvasir]
  agents: []
  telegram: null
  tier: owner
  addressed_only: true
  rate_per_hour: 60
YAML

pass=0; fail=0
check() {  # <name> <expected-rc> <actual-rc> [note]
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1)); printf '  PASS  %s\n' "$1"
  else
    fail=$((fail + 1)); printf '  FAIL  %s (expected rc %s, got %s)%s\n' "$1" "$2" "$3" "${4:+ — $4}"
  fi
}
room() { YMIR_HOME="$TMP" bash "$ROOT/systems/skirnir/services/room.sh" "$@" 2>/dev/null; }
lines() { local f="$TMP/hodd/state/assistant/rooms/test-room.jsonl"; [ -f "$f" ] && wc -l <"$f" | tr -d ' ' || echo 0; }

printf 'room_wall_test[9]{case,expectation}:\n'

# 1 · deliberate words pass
room append --room test-room --speaker brokk --text "the wall holds; plain words pass" >/dev/null; rc=$?
check "plain words are appended" 0 $rc
before=$(lines)

# 2 · fullwidth-bar DSML markup (deepseek's shape) is refused
room append --room test-room --speaker kvasir --text '<｜｜DSML｜｜> invoke name="bash"' >/dev/null; rc=$?
check "DSML fullwidth markup refused" 6 $rc

# 3 · ASCII-pipe tool call
room append --room test-room --speaker kvasir --text '<|tool|> invoke name="bash"' >/dev/null; rc=$?
check "ASCII invocation markup refused" 6 $rc

# 4 · a bare invoke/parameter pair
room append --room test-room --speaker kvasir --text 'invoke name="bash" parameter name="command"' >/dev/null; rc=$?
check "invoke/parameter pair refused" 6 $rc

# 5 · a serialised tool_calls block (a working stream, not words)
room append --room test-room --speaker kvasir --text '{"tool_calls": [{"name": "bash"}]}' >/dev/null; rc=$?
check "serialised tool_calls refused" 6 $rc

# 6 · NOTHING was written by the four refusals
after=$(lines)
check "refusals wrote nothing (append-only stays clean)" "$before" "$after" "before=$before after=$after"

# 7 · a non-member cannot speak
room append --room test-room --speaker nobody --text "let me in" >/dev/null; rc=$?
check "non-member refused" 4 $rc

# 8 · an unknown room is refused, not created
room append --room no-such-room --speaker brokk --text "hello" >/dev/null; rc=$?
check "unknown room refused" 3 $rc

# 9 · the record still holds exactly the one good line
last="$(room list --room test-room --limit 5 | tail -1)"
case "$last" in
  *"plain words pass"*) check "the record holds only deliberate words" 0 0 ;;
  *) check "the record holds only deliberate words" 0 1 "got: $last" ;;
esac

if [ "$VERBOSE" = 1 ]; then
  printf '\n  record: %s line(s)\n' "$(lines)"
  room list --room test-room --limit 5 | sed 's/^/    /'
fi

printf '\nroom_wall[2]{passed,failed}:\n  "%s","%s"\n' "$pass" "$fail"
[ "$fail" = 0 ] || exit 1
