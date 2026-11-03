#!/usr/bin/env bash
# note.sh — append a DATED section to an existing document in the home (append-only, Rule 06).
#
#   note.sh <home-relative-doc> "<heading>" "<body>"
#
# Never rewrites: the section is appended whole. A correction cites the old entry.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
hoard="$(bash "$ROOT/bin/vault/hodd.sh" path 2>/dev/null || true)"; [ -n "$hoard" ] || { echo "note: no home" >&2; exit 1; }
HOME_DIR="$(dirname "$hoard")"
doc="${1:-}"; head="${2:-}"; body="${3:-}"
case "${doc:-}" in -h|--help|"") sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
[ -f "$HOME_DIR/$doc" ] || { printf 'note: no such document: %s\n' "$HOME_DIR/$doc" >&2; exit 1; }
{ printf '\n---\n\n%s\n\n%s\n' "$head" "$body"; } >> "$HOME_DIR/$doc"
printf 'appended to %s\n' "$doc"
