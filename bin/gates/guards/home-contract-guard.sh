#!/usr/bin/env bash
# home-contract-guard.sh — the contract that raises a user's home is checked (Rule 42).
#
# The contract is `.agents/home-contract.yaml`: one row per file the runtime READS from
# the operator's home, with the shape that ships it and the door that writes it. This ward
# delegates to `bin/gates/checks/home-contract-check.sh`, which delegates the PARSING to
# `bin/engine/home-seed.sh` — one reader of the contract, so a row that seeds correctly can
# never be judged differently.
#
# It refuses four silent faults, all measured on the day the rule was written:
#   · a row naming a template that does not ship           (a user receives nothing)
#   · a row naming a door that does not exist              (nothing ever writes it)
#   · a required home file with no shape anywhere          (the ABSENT lines of a fresh home)
#   · a TEMPLATE no row names — a shape shipped to every user and copied into no home
#
#   home-contract-guard.sh            # check
#   home-contract-guard.sh --list     # the rows, tab-separated
#
# Exit: 0 clean · 1 a finding · 2 usage.
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
CHECK="$ROOT/bin/gates/checks/home-contract-check.sh"

case "${1-}" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help|"") sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  check|--all) ;;
  --list) exec bash "$CHECK" --list ;;
  *) printf 'error: unknown action %s\nhelp: home-contract-guard.sh [check|--list]\n' "${1-}" >&2; exit 2 ;;
esac

[ -r "$CHECK" ] || {
  printf 'home-contract-guard[1]{finding,detail}:\n  "the check is missing","%s"\n' "$CHECK"
  printf 'home-contract-guard: the check named above does not exist\nhelp: bin/gates/checks/home-contract-check.sh ships with RULES/42\n' >&2
  exit 1
}

if out="$(bash "$CHECK" check 2>&1)"; then
  printf 'home-contract-guard[1]{finding,detail}:\n  "none","the contract raises a complete home"\n'
  exit 0
fi
printf '%s\n' "$out"
printf 'home-contract-guard: the contract would leave a home incomplete\nhelp: fix the rows named above; RULES/42 states what each kind owes\n' >&2
exit 1
