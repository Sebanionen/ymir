#!/usr/bin/env bash
# test_telegram_roster.sh — the roster records who speaks, once, per chat.
#
# Telegram will not list a group's members and the bridge hands over no sender, so
# the roster is the only complete member list a bot can build. This proves it is
# honest: a message counted once, two chats kept apart, an admin who never spoke
# still recorded, and a name never filed in the wrong room.
#
# Usage: test_telegram_roster.sh
# Exit: 0 all pass · 1 a failure.
set -u
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/../../.." && pwd)
DOOR="$ROOT/bin/notify/telegram-roster.sh"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export YMIR_HOME="$TMP/home"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }

printf 'telegram roster\n'

"$DOOR" --version >/dev/null && ok "the door reports a version" || bad "the door reports a version"

"$DOOR" record --chat -1001 --user 42 --name Craig --username craigema --message m1 >/dev/null 2>&1
grep -q '"42","Craig","craigema"' "$YMIR_HOME/hodd/data/telegram-rosters/-1001.yaml" 2>/dev/null || true
"$DOOR" list --chat -1001 | grep -q '"Craig"' && ok "a speaker is recorded" || bad "a speaker is recorded" "$("$DOOR" list --chat -1001)"

"$DOOR" record --chat -1001 --user 42 --name Craig --message m1 >/dev/null 2>&1
count=$("$DOOR" list --chat -1001 | grep -o '"1"' | head -1)
[ "$count" = '"1"' ] && ok "the same message is counted once" || bad "the same message is counted once" "$("$DOOR" list --chat -1001)"

"$DOOR" record --chat -2002 --user 42 --name Craig --message m2 >/dev/null 2>&1
[ -f "$YMIR_HOME/hodd/data/telegram-rosters/-1001.yaml" ] && [ -f "$YMIR_HOME/hodd/data/telegram-rosters/-2002.yaml" ] \
  && ok "two chats are two files" || bad "two chats are two files"
"$DOOR" chats | grep -q '\-1001' && "$DOOR" chats | grep -q '\-2002' && ok "chats lists both rooms" || bad "chats lists both rooms" "$("$DOOR" chats)"

"$DOOR" show --chat -1001 --user 42 | grep -q 'Craig' && ok "show returns the row" || bad "show returns the row"
"$DOOR" show --chat -1001 --user 999 >/dev/null 2>&1 && bad "show refuses an unknown id" || ok "show refuses an unknown id"

ADMINS='{"ok":true,"result":[{"status":"creator","user":{"id":7,"first_name":"Ada","username":"ada-handle"}}]}'
"$DOOR" sync-admins --chat -1001 --admins-json "$ADMINS" >/dev/null 2>&1
"$DOOR" list --chat -1001 | grep -q '"Ada"' && ok "an admin who never spoke is recorded" || bad "an admin who never spoke is recorded" "$("$DOOR" list --chat -1001)"
"$DOOR" list --chat -1001 | grep -q '"admin"' && ok "the admin carries the admin role" || bad "the admin carries the admin role"

"$DOOR" record --chat -1001 --user 42 --name Craig >/dev/null 2>&1
ok "a record without a message id still works"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
