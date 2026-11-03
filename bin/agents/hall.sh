#!/usr/bin/env bash
# hall.sh — the whole house in ONE read: the seat, the doors, the queue, the last runes.
#
#   hall.sh [--runes N]
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
hoard="$(bash "$ROOT/bin/vault/hodd.sh" path 2>/dev/null || true)"; HOME_DIR="$(dirname "${hoard:-/}")"
n="${2:-5}"
printf 'hall[4]{what,detail}:\n'
printf '  "seat","%s"\n' "$(sed -n 's/^primary=/primary=/p' "$HOME/.pi/agent/extensions/.ymir-seat" 2>/dev/null | head -1)$( [ -f "$HOME/.pi/agent/extensions/.ymir-seat" ] && printf ' host=%s' "$(sed -n 's/^host=//p' "$HOME/.pi/agent/extensions/.ymir-seat")")"
printf '  "doors","%s shell doors listed in bin/README.md"\n' "$(grep -cE '^\| [a-z0-9._-]+\.sh \|' "$ROOT/bin/README.md" 2>/dev/null)"
printf '  "queue","%s pending wake(s)"\n' "$(bash "$ROOT/bin/time/saga-wake-drain.sh" 2>/dev/null | sed -n 's/^wake queue: \([0-9]*\) pending/\1/p' | head -1)"
if [ -f "$HOME_DIR/hodd/memory/runes_audit.md" ]; then
  printf '  "runes","%s (last: %s)"\n' "$(wc -l < "$HOME_DIR/hodd/memory/runes_audit.md")" "$(tail -1 "$HOME_DIR/hodd/memory/runes_audit.md" | cut -c1-60)"
fi
