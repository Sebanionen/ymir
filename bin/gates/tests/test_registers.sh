#!/usr/bin/env bash
# test_registers.sh — one door for every generated register.
#
# The class: two registers, two generators, two gates, and a change that
# half-regenerates the tree. This test asserts the door names every generator,
# that a stale register is DETECTED (the door must say so, not pass), and that
# generate then check comes back clean.
#
# Usage: test_registers.sh
# Exit: 0 all pass · 1 a failure.
set -u
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/../../.." && pwd)
DOOR="$ROOT/bin/gates/registers.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }

printf 'registers door\n'

"$DOOR" --version >/dev/null 2>&1 && ok "the door reports a version" || bad "the door reports a version"

count=$("$DOOR" list | grep -c '^  "bin/gates/')
[ "$count" -ge 2 ] && ok "the list names every generator ($count)" || bad "the list names every generator" "found $count"

"$DOOR" list | grep -q 'capabilities.sh' && ok "the capability generator is on the list" || bad "the capability generator is on the list"
"$DOOR" list | grep -q 'inventory.sh' && ok "the inventory generator is on the list" || bad "the inventory generator is on the list"

# A register that has drifted must be DETECTED, never passed. Touching a door's
# line count is enough: the inventory register records lines per file.
victim="$ROOT/bin/notify/telegram-buttons.sh"
cp "$victim" "$victim.bak-test"
printf '\n# drift\n' >>"$victim"
if "$DOOR" check >/dev/null 2>&1; then bad "a stale register is detected" "check passed with a drifted tree"; else ok "a stale register is detected"; fi
mv "$victim.bak-test" "$victim"

"$DOOR" generate >/dev/null 2>&1 && ok "generate runs every generator" || bad "generate runs every generator"
"$DOOR" check >/dev/null 2>&1 && ok "after generate the registers are current" || bad "after generate the registers are current" "$("$DOOR" check 2>&1 | tail -2)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
