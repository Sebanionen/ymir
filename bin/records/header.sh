#!/usr/bin/env bash
# header.sh — the declared-truth header of a home document: check, or apply a minimal one.
#
#   header.sh check [path]      # documents with no header or a stale one
#   header.sh apply [path]      # add a minimal header (never overwrites an existing one)
#
# kind · status · verified · verified_by · supersedes · superseded_by
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
hoard="$(bash "$ROOT/bin/vault/hodd.sh" path 2>/dev/null || true)"; [ -n "$hoard" ] || exit 1
HOME_DIR="$(dirname "$hoard")"
target="${2:-}"; [ -n "$target" ] || target="hodd"
base="$HOME_DIR/$target"; [ -e "$base" ] || base="$target"
action="${1:-check}"
missing=0
while IFS= read -r f; do
  grep -qE '^kind:' "$f" 2>/dev/null && continue
  missing=$((missing+1))
  if [ "$action" = apply ]; then
    { printf -- '---\nkind: note\nstatus: live\nverified: declared\nverified_by: %s\nsupersedes: none\nsuperseded_by: none\n---\n\n' "$(date +%F)"; cat "$f"; } > "$f.tmp" && mv "$f.tmp" "$f"
    printf 'headed %s\n' "${f#"$HOME_DIR"/}"
  else
    printf 'no header: %s\n' "${f#"$HOME_DIR"/}"
  fi
done < <(find "$base" -name '*.md' -not -path '*/.git/*' 2>/dev/null | head -400)
[ "$action" = check ] && printf 'header: %s document(s) without a header\n' "$missing"
exit 0
