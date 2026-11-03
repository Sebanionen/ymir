#!/usr/bin/env bash
# weave-features.sh — FEATURES.md is WOVEN from fragments, never hand-edited.
#
#   bin/records/weave-features.sh            re-weave FEATURES.md from its fragments
#   bin/records/weave-features.sh --check    exit 1 when FEATURES.md is stale
#   bin/records/weave-features.sh --install  seat the merge driver for this clone
#
# WHY (Þættir, plan 174; the Allfather 2026-11-03: *"FEATURES.md always colliding
# … do features.md to some kind of folder structure"*): FEATURES.md is the one
# document EVERY feature touches, so two branches always append to the same tail
# and git calls it a conflict. It is now generated:
#
#   docs/features/_catalogue/_header.md   the doctrine above the sections
#   docs/features/_catalogue/_sections.md the section order: <order> | <title> | <slug>
#   docs/features/_catalogue/entries/     ONE FILE PER ENTRY — the collision-free unit
#
# A new feature adds its OWN entry file (never an edit to a shared line), so two
# features in two branches touch two files and merge without a conflict.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CAT="$ROOT/docs/features/_catalogue"
OUT="$ROOT/FEATURES.md"
[ -f "$CAT/_header.md" ] || { echo "weave-features: no header fragment" >&2; exit 2; }
[ -f "$CAT/_sections.md" ] || { echo "weave-features: no section order" >&2; exit 2; }

if [ "${1:-}" = "--install" ]; then
  git -C "$ROOT" config merge.regenerate.driver \
    "bash \"$ROOT/bin/records/regenerate-on-merge.sh\" %O %A %B %L %P"
  printf 'seated merge.regenerate.driver for this clone\n'
  exit 0
fi

tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
cat "$CAT/_header.md" > "$tmp"
while IFS='|' read -r order title slug; do
  order="$(printf '%s' "$order" | tr -d ' ')"; title="$(printf '%s' "$title" | sed 's/^ *//;s/ *$//')"; slug="$(printf '%s' "$slug" | tr -d ' ')"
  case "$order" in ''|\#*) continue ;; esac
  printf '\n## %s\n' "$title" >> "$tmp"
  for f in "$CAT/entries/$order"-*.md; do
    [ -f "$f" ] || continue
    sed -n '4,$p' "$f" >> "$tmp"
  done
done < "$CAT/_sections.md"

if [ "${1:-}" = "--check" ]; then
  if cmp -s "$tmp" "$OUT"; then printf 'FEATURES.md is current (%s entries)\n' "$(ls "$CAT"/entries/*.md 2>/dev/null | wc -l)"; exit 0; fi
  printf 'FEATURES.md is STALE — run bin/records/weave-features.sh\n' >&2; exit 1
fi
cp "$tmp" "$OUT"
printf 'wove FEATURES.md from %s entries in %s sections\n' "$(ls "$CAT"/entries/*.md 2>/dev/null | wc -l)" "$(grep -c '^[0-9]' "$CAT/_sections.md")"
