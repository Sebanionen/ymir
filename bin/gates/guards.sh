#!/usr/bin/env bash
# guards.sh — every TREE ward, in one command.
#
# The pre-push hook and BOTH CI hosts call this, so the set of wards has exactly one home:
# adding a ward means adding a line here, and nowhere else. A ward judges the tree and exits
# non-zero when it finds a fault; this only aggregates.
#
# Usage:
#   guards.sh          # run every tree ward
#   guards.sh --list   # name them
#
# Exit: 0 every ward clean · 1 a ward found a fault · 2 usage.
set -u

_root() {
  local d; d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [ "$d" != "/" ]; do
    [ -d "$d/.pi" ] && [ -d "$d/RULES" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
}
ROOT="$(_root)"

# ONE list. A new tree ward appears here or it does not run anywhere.
WARDS=(runtime-guard runtime-pinned-guard defaults-guard app-folder-guard app-functional-guard rules-number-guard inventory-guard fleet-version-guard subsystem-docs-guard path-ledger-guard cron-guard features-guard vault-guard confidential-guard dead-code-guard docs-claims-guard home-contract-guard pkill-guard)

case "${1-}" in
  -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --list)    printf '%s\n' "${WARDS[@]}"; exit 0 ;;
  "")        ;;
  *)         printf 'error: unknown flag %s\nhelp: guards.sh [--list]\n' "${1-}" >&2; exit 2 ;;
esac

fail=0
printf 'guards[%s]{ward,status,finding}:\n' "${#WARDS[@]}"
for w in "${WARDS[@]}"; do
  s="$ROOT/bin/gates/guards/$w.sh"
  if [ ! -r "$s" ]; then
    printf '  "%s","MISSING","bin/gates/guards/%s.sh — a ward named in the list does not exist"\n' "$w" "$w"
    fail=1
    continue
  fi
  if out="$(bash "$s" check 2>&1)"; then
    printf '  "%s","PASS",""\n' "$w"
  else
    # The ward's own last line names the fault and its remedy; carry it up rather than
    # swallowing it, because a gate that does not say why is an obstacle.
    printf '  "%s","FAIL","%s"\n' "$w" "$(printf '%s' "$out" | grep -E '^(defaults|runtime)-guard:' | tail -1 | cut -c1-96)"
    fail=1
  fi
done

if [ "$fail" -eq 0 ]; then
  exit 0
fi
printf 'guards: a ward found a fault — see the FAIL row above\nhelp: run the failing ward directly; its message names the remedy\n' >&2
exit 1
