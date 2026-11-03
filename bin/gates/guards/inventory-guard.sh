#!/usr/bin/env bash
# inventory-guard.sh — a register that runs in no gate is a capability that is silently absent.
#
# Rule: RULES/12 (the register must see every door at every depth) and RULES/34 (a view is
# rendered, never hand-appended — and a rendered view that nobody checks is a document).
#
# The bin/ + backend indexes ARE derived and their `--check` exists — and until 2026-10-23
# `bin/gates/guards.sh` never called it, so outside CI the register could rot freely. Worse:
# the generator itself was not reproducible (its caller scan read its own output), so a
# `--check` would have failed on a correct tree. Both are fixed; this ward is the proof that
# the fix stays fixed.
#
#   inventory-guard.sh check   # the ward
#   inventory-guard.sh         # alias for check
#
# Exit: 0 current · 1 stale (with the register's own advice) · 2 usage.
set -u

VERSION="1.0.0"
_root() {
  local d; d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [ "$d" != "/" ]; do
    [ -d "$d/.pi" ] && [ -d "$d/RULES" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
}
ROOT="$(_root)"
INV="$ROOT/bin/gates/inventory.sh"

case "${1-}" in
  -v|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  check|"") ;;
  *) printf 'error: unknown action %s\nhelp: inventory-guard.sh [check]\n' "${1-}" >&2; exit 2 ;;
esac

if [ ! -r "$INV" ]; then
  printf 'inventory-guard[1]{finding,detail}:\n  "no generator","%s is missing — the register cannot be checked"\n' "${INV#"$ROOT"/}"
  exit 1
fi

# The generator's own word, carried up rather than swallowed: its message names the remedy.
if out="$(bash "$INV" --check 2>&1)"; then
  printf 'inventory-guard[1]{finding,detail}:\n  "none","every register is current — %s"\n' \
    "$(printf '%s' "$out" | grep -c . ) row(s) of verdict"
  exit 0
fi

printf 'inventory-guard[1]{finding,detail}:\n  "a register is stale","%s"\n' \
  "$(printf '%s' "$out" | grep -E 'is STALE' | tr '\n' ' ' | cut -c1-160)"
printf 'help: run bin/gates/inventory.sh (once; it is reproducible) and commit the register in the same change\n' >&2
exit 1
