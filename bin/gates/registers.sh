#!/usr/bin/env bash
# registers.sh — every generated register, through one door.
#
# The house keeps two registers that describe the tree: `bin/README.md` (the bin
# inventory, with `.agents/backend/README.md` beside it) and
# `.agents/assets/agents/capabilities.md` (the capability register). They are
# written by two different generators, checked by two different gates, and named
# almost the same — so a change that adds a door half-regenerates the tree, and
# the half it forgot goes red in CI only, where the person pushing cannot see it.
# That is not a theory: it happened on 2026-11-03 (PR 487), and it made four
# collaborators' PRs show a failure that was ours.
#
# This door is the list. A generator is added HERE and nowhere else; `generate`
# runs them all, `check` asks each whether its register is current. The ward
# (`bin/gates/guards/registers-guard.sh`) calls `check`, so `guards.sh` and CI
# judge the same set.
#
# Usage:
#   registers.sh list       # the generators, in order
#   registers.sh generate   # run every generator (writes the registers)
#   registers.sh check      # is every register current? 0 yes, 1 no, 3 unavailable
#   registers.sh --version
#
# Order matters for the one known trap: `inventory.sh` enumerates TRACKED files,
# so a register written before `git add` records a tree without the new doors.
# Write, stage, generate, commit, push.
set -u
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/../.." && pwd)
VERSION="1.0.0"

# ONE list: every generator that writes a register from the tree.
GENERATORS=(
  "bin/gates/inventory.sh"
  "bin/gates/capabilities.sh"
)

check_one() { # <generator> — 0 current, 1 stale
  case "$1" in
    *inventory.sh) bash "$ROOT/bin/gates/inventory.sh" --check >/dev/null 2>&1 ;;
    *capabilities.sh) bash "$ROOT/bin/gates/capabilities.sh" --check >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

generate_one() { # <generator>
  case "$1" in
    *inventory.sh) bash "$ROOT/bin/gates/inventory.sh" >/dev/null 2>&1 ;;
    *capabilities.sh) bash "$ROOT/bin/gates/capabilities.sh" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

case "${1:-}" in
  list)
    printf 'registers[%d]{generator}:\n' "${#GENERATORS[@]}"
    for g in "${GENERATORS[@]}"; do printf '  "%s"\n' "$g"; done
    ;;
  generate)
    [ ${#GENERATORS[@]} -gt 0 ] || { printf 'unavailable: no generators are declared\n' >&2; exit 3; }
    rc=0
    for g in "${GENERATORS[@]}"; do
      if generate_one "$g"; then printf 'wrote  %s\n' "$g"; else printf 'failed %s\n' "$g" >&2; rc=1; fi
    done
    exit "$rc"
    ;;
  check)
    [ ${#GENERATORS[@]} -gt 0 ] || { printf 'unavailable: no generators are declared\n' >&2; exit 3; }
    stale=0
    printf 'registers[%d]{generator,state}:\n' "${#GENERATORS[@]}"
    for g in "${GENERATORS[@]}"; do
      if check_one "$g"; then printf '  "%s","current"\n' "$g"; else printf '  "%s","STALE"\n' "$g"; stale=1; fi
    done
    if [ "$stale" -ne 0 ]; then
      printf 'registers: a register is stale — run bin/gates/registers.sh generate, then commit it in the same change\n' >&2
    fi
    exit "$stale"
    ;;
  --version|-v) printf 'registers.sh %s\n' "$VERSION" ;;
  -h|--help|"")
    sed -n '2,27p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    ;;
  *)
    printf 'error: unknown verb %s\nhelp: registers.sh [list|generate|check|--version]\n' "${1:-}" >&2
    exit 2
    ;;
esac
