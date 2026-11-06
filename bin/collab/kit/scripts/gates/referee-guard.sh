#!/usr/bin/env bash
# referee-guard — the gates, the hooks and the wards are the referee. A change to one of them must be explained.
#
# A player may fix the referee: the houses' own record is full of honest repairs to a gate. What is refused is a
# SILENT one — because a gate quietly weakened looks exactly like a gate that passes.
#
# Usage: referee-guard.sh <base> [head]     exit 0 allowed · 1 unexplained · 2 usage
set -u
base="${1:-}"; head="${2:-HEAD}"
[ -n "$base" ] || { printf 'referee-guard: usage: referee-guard.sh <base> [head]\n' >&2; exit 2; }

touched=$(git diff --name-only "$base" "$head" -- scripts/gates scripts/wards .githooks 2>/dev/null)
[ -z "$touched" ] && exit 0

note=$(git diff --name-only "$base" "$head" -- docs/fixes 2>/dev/null)
said=$(git log --format='%B' "$base..$head" 2>/dev/null | grep -ciE 'ward|gate|hook|guard')

if [ -n "$note" ] && [ "$said" -gt 0 ]; then
  printf 'referee-guard: allowed — the referee changed and the range explains it\n'
  exit 0
fi

printf 'referee-guard refused: the referee is changed with no explanation\n' >&2
printf '  touched:\n' >&2
printf '%s\n' "$touched" | sed 's/^/    /' >&2
printf '  a note under docs/fixes/ and a word in the message (ward, gate, hook) are what make it reviewable\n' >&2
exit 1
