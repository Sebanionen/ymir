#!/usr/bin/env bash
# test_telegram_buttons.sh — the button grammar, proved both ways.
#
# A button is only useful if it renders, and the bridge gives NO error when it
# does not. So this test asserts the round trip (emit → check passes), and then
# asserts that every shape that looks plausible but does nothing is REFUSED:
#
#   1. the legacy colon form `<!--telegram_button: label|prompt-->`
#   2. an indented wrapper (must be column zero)
#   3. an enabled button with no prompt
#   4. an unknown style
#   5. nine buttons in one row
#   6. more than six buttons in a reply
#   7. an unclosed matrix
#
# Usage: test_telegram_buttons.sh
# Exit: 0 all pass · 1 a failure.
set -u
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/../../.." && pwd)
DOOR="$ROOT/bin/notify/telegram-buttons.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }
expect_ok()   { local why=$1; shift; if "$@" >"$TMP/out" 2>"$TMP/err"; then ok "$why"; else bad "$why" "$(tail -1 "$TMP/err")"; fi; }
expect_fail() { local why=$1; shift; if "$@" >"$TMP/out" 2>"$TMP/err"; then bad "$why" "expected a finding, got a clean pass"; else ok "$why"; fi; }

printf 'telegram button grammar\n'

expect_ok "the door reports a version" "$DOOR" --version

"$DOOR" emit --button "📜 Bearings|Give me my bearings." --button "🗂 Open work|Show what is open." >"$TMP/footer.txt"
grep -q '^<!-- telegram_button \[{' "$TMP/footer.txt" && ok "emit writes a footer wrapper at column zero" || bad "emit writes a footer wrapper" "$(cat "$TMP/footer.txt")"
expect_ok "a footer wrapper checks clean" "$DOOR" check "$TMP/footer.txt"

"$DOOR" emit --in-body --button "✅ Yes|Do it." --button "❌ No|Do not." >"$TMP/body.txt"
grep -q '^```telegram_button$' "$TMP/body.txt" && ok "emit --in-body writes a fence at column zero" || bad "emit --in-body writes a fence"
expect_ok "an in-body fence checks clean" "$DOOR" check "$TMP/body.txt"

printf '%s\n' 'Some prose.' '' '<!--telegram_button: 📜 Bearings|Give me bearings-->' >"$TMP/legacy.txt"
expect_fail "the legacy colon form is refused" "$DOOR" check "$TMP/legacy.txt"
grep -q "legacy colon form" "$TMP/out" && ok "the finding names the colon form" || bad "the finding names the colon form" "$(cat "$TMP/out")"

printf '%s\n' '  <!-- telegram_button [{A|a}{B|b}] -->' >"$TMP/indent.txt"
expect_fail "an indented wrapper is refused" "$DOOR" check "$TMP/indent.txt"

printf '%s\n' '<!-- telegram_button [{A|a}{B|}] -->' >"$TMP/noprompt.txt"
expect_fail "an enabled button with no prompt is refused" "$DOOR" check "$TMP/noprompt.txt"

printf '%s\n' '<!-- telegram_button [{A|a|warn}{B|b}] -->' >"$TMP/style.txt"
expect_fail "an unknown style is refused" "$DOOR" check "$TMP/style.txt"

printf '%s\n' '<!-- telegram_button [[{B1|p}{B2|p}{B3|p}{B4|p}{B5|p}{B6|p}{B7|p}{B8|p}{B9|p}]] -->' >"$TMP/nine.txt"
expect_fail "nine buttons in one row are refused" "$DOOR" check "$TMP/nine.txt"
grep -q "Telegram allows 8" "$TMP/out" && ok "the finding names Telegram's eight-per-row limit" || bad "the finding names the row limit" "$(cat "$TMP/out")"
long=()
for i in 1 2 3 4 5 6 7 8 9; do long+=(--button "B$i|prompt $i"); done
"$DOOR" emit --allow-many "${long[@]}" >"$TMP/chunked.txt"
expect_ok "emit chunks a long list into legal rows" "$DOOR" check --allow-many "$TMP/chunked.txt"
grep -q '\]\[' "$TMP/chunked.txt" && ok "the chunked wrapper has two rows" || bad "the chunked wrapper has two rows" "$(cat "$TMP/chunked.txt")" 

expect_fail "more than six buttons in a reply are refused" "$DOOR" emit \
  --button "A|a" --button "B|b" --button "C|c" --button "D|d" --button "E|e" --button "F|f" --button "G|g"

printf '%s\n' '<!-- telegram_button [{A|a}{B|b} -->' >"$TMP/unclosed.txt"
expect_fail "an unclosed matrix is refused" "$DOOR" check "$TMP/unclosed.txt"

printf '%s\n' 'Prose with no controls at all.' >"$TMP/none.txt"
expect_ok "a reply with no buttons is not a fault" "$DOOR" check "$TMP/none.txt"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
