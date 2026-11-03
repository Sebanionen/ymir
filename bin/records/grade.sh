#!/usr/bin/env bash
# grade.sh — Dellingr: how fresh is a document? A Norse grade from measurable signals only.
#
#   grade.sh <home-relative doc|shelf> [--eldri N] [--forn N]
#
# nýr (fresh) · eldri (aging, over --eldri days) · forn (old, over --forn days) · safn (archive:
# declares a successor). Nothing is deleted for being old — an old document MOVES (Rule 11).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
hoard="$(bash "$ROOT/bin/vault/hodd.sh" path 2>/dev/null || true)"; [ -n "$hoard" ] || exit 1
HOME_DIR="$(dirname "$hoard")"
eldri=90; forn=365; target=""
while [ $# -gt 0 ]; do case "$1" in --eldri) eldri="$2"; shift 2 ;; --forn) forn="$2"; shift 2 ;; *) target="$1"; shift ;; esac; done
[ -n "$target" ] || { printf 'usage: grade.sh <doc|shelf>\n' >&2; exit 2; }
p="$HOME_DIR/$target"; [ -e "$p" ] || p="$target"
now=$(date +%s)
grade_one() {
  local f=$1 age succ
  age=$(( (now - $(stat -c %Y "$f" 2>/dev/null || echo "$now")) / 86400 ))
  succ="$(sed -n 's/^superseded_by:[[:space:]]*//p' "$f" 2>/dev/null | head -1)"
  if [ -n "$succ" ] && [ "$succ" != none ]; then g=safn
  elif [ "$age" -ge "$forn" ]; then g=forn
  elif [ "$age" -ge "$eldri" ]; then g=eldri
  else g=nýr; fi
  printf '%-6s %4sd  %s\n' "$g" "$age" "${f#"$HOME_DIR"/}"
}
if [ -d "$p" ]; then find "$p" -name '*.md' -not -path '*/.git/*' 2>/dev/null | head -300 | while read -r f; do grade_one "$f"; done
else grade_one "$p"; fi
