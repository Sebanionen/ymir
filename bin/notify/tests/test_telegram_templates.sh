#!/usr/bin/env bash
# The ward for the Telegram templates: every shape here must be one the bridge can render
# and one a phone can read. A template that drifts fails this test, not the next message.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
dir="$root/.agents/templates/telegram"
ok=0; fail=0
for f in "$dir"/*.md; do
  [ -e "$f" ] || continue
  base=$(basename "$f")
  [ "$base" = "README.md" ] && continue
  if bash "$root/bin/notify/telegram-buttons.sh" check "$f" >/tmp/.tbtn.$$ 2>&1; then ok=$((ok+1)); else fail=$((fail+1)); echo "FAIL $base (buttons)"; head -3 /tmp/.tbtn.$$; fi
  if python3 "$root/bin/notify/telegram-format.py" --check < "$f" >/tmp/.tfmt.$$ 2>&1; then ok=$((ok+1)); else fail=$((fail+1)); echo "FAIL $base (format)"; head -3 /tmp/.tfmt.$$; fi
  rm -f /tmp/.tbtn.$$ /tmp/.tfmt.$$
done
printf 'telegram-templates: %s ok / %s fail\n' "$ok" "$fail"
[ "$fail" = 0 ]
