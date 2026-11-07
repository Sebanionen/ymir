#!/usr/bin/env bash
# reviews-shelf — a review nobody can find is a review that did not happen.
#
# Three checks: every review is named after the pull request it judges, every review appears on the shelf index, and the baton
# names the newest one — because a person starting work reads the baton first, not the folder.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="$ROOT/docs/audit"
INDEX="$DIR/README.md"
BATON="$ROOT/handoff/CURRENT.md"

reviews="$(ls -1 "$DIR" 2>/dev/null | grep 'review-of-pr' || true)"
[ -n "$reviews" ] || { printf 'reviews-shelf: none yet\n'; exit 0; }

bad="$(printf '%s\n' "$reviews" | grep -vE '^[0-9]{4}-[0-9]{2}-[0-9]{2}-review-of-pr[0-9]+\.md$' || true)"
if [ -n "$bad" ]; then
  printf 'reviews-shelf refused: not named <date>-review-of-pr<N>.md:\n%s\n' "$bad" >&2; exit 1
fi

unlisted=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  grep -q "$f" "$INDEX" 2>/dev/null || unlisted="$unlisted\n  $f"
done <<< "$reviews"
if [ -n "$unlisted" ]; then
  printf 'reviews-shelf refused: missing from docs/audit/README.md:%b\n' "$unlisted" >&2; exit 1
fi

newest="$(printf '%s\n' "$reviews" | sort -r | head -1)"
if ! grep -q "$newest" "$BATON" 2>/dev/null; then
  printf 'reviews-shelf refused: the baton does not name the newest review (%s)\n  a review nobody is pointed at is a file, not a review\n' "$newest" >&2
  exit 1
fi
printf 'reviews-shelf: %s review(s), indexed, newest named by the baton\n' "$(printf '%s\n' "$reviews" | grep -c .)"
