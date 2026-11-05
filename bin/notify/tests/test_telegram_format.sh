#!/usr/bin/env bash
# The ward for telegram-format: reads well, protects structure, refuses jargon.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FMT="$(cd "$here/../.." && pwd)/notify/telegram-format.py"
ok=0; fail=0
t() { # <name> <expected-substring> <input>
  local name=$1 want=$2 input=$3 out
  out="$(printf '%s' "$input" | python3 "$FMT")"
  if printf '%s' "$out" | grep -qF -- "$want"; then ok=$((ok+1)); printf 'ok   %s\n' "$name"
  else fail=$((fail+1)); printf 'FAIL %s\n  wanted: %s\n  got: %s\n' "$name" "$want" "$out"; fi
}
t "one sentence per line" "I was writing reports, not messages." "Fair. I was writing reports, not messages."
t "list item untouched" "- a list item stays" "- a list item stays"
t "fence untouched" "code stays" "\`\`\`
code stays
\`\`\`"
t "blank line kept" "" "one

two"
# --check
printf 'short line\n' | python3 "$FMT" --check >/dev/null && ok=$((ok+1)) || { fail=$((fail+1)); echo "FAIL check accepts short"; }
long="$(python3 -c 'print("x"*200)')"
printf '%s\n' "$long" | python3 "$FMT" --check >/dev/null && { fail=$((fail+1)); echo "FAIL check should refuse a long line"; } || ok=$((ok+1))
printf 'format: %s ok / %s fail\n' "$ok" "$fail"
[ "$fail" = 0 ]
