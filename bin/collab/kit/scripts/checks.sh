#!/usr/bin/env bash
# checks.sh — run this repository's own cheap checks, whatever language it is written in.
#
#   bash scripts/checks.sh doctor   # what a commit runs: is the tree coherent?
#   bash scripts/checks.sh test     # what a push runs: does the tree still work?
#
# The kit goes into Node, Elixir and shell repositories, so the hooks must not assume one of them. This door
# probes for the repository's own check and runs that; it never invents a command and never guesses a tool.
# A repository with no check of its own is a SKIP that says so — a clean skip is a pass, a silent green is a
# lie (RULES/25).
#
# First match wins:
#   1. scripts/doctor.sh · scripts/test.sh   a repository that names its own doors
#   2. package.json                         npm run check / typecheck, npm run test
#   3. mix.exs                              mix compile --warnings-as-errors, mix test
#   4. nothing                              skip, printed plainly
#
# Exit: 0 passed or skipped · non-zero a check failed · 2 usage.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2

what="${1:-doctor}"
case "$what" in doctor|test) ;; *) printf 'usage: checks.sh doctor|test\n' >&2; exit 2 ;; esac

skipped() {
  printf 'checks[%s]: skipped — %s; this is a skip, not a pass\n' "$what" "$1"
  exit 0
}

step() {
  printf 'checks[%s]: %s\n' "$what" "$*"
  "$@" || { printf '\nchecks[%s] refused: "%s" failed\nhelp: fix it, or commit with --no-verify and say why in the message\n' "$what" "$*" >&2; exit 1; }
}

# 1 — the repository names its own doors
if [ -x scripts/doctor.sh ] || [ -x scripts/test.sh ]; then
  if [ "$what" = doctor ] && [ -x scripts/doctor.sh ]; then step ./scripts/doctor.sh; fi
  if [ "$what" = test ] && [ -x scripts/test.sh ]; then step ./scripts/test.sh; fi
  skipped "this repository's own scripts/ covers the other half"
fi

# 2 — node
if [ -f package.json ] && command -v npm >/dev/null 2>&1; then
  if [ "$what" = doctor ]; then
    step npm run --silent check
    step npm run --silent typecheck
  else
    step npm run --silent test
  fi
  exit 0
fi

# 3 — elixir
if [ -f mix.exs ] && command -v mix >/dev/null 2>&1; then
  if [ "$what" = doctor ]; then
    step mix compile --warnings-as-errors
  else
    step mix test
  fi
  exit 0
fi

# 4 — nothing to run
if [ -f mix.exs ] && ! command -v mix >/dev/null 2>&1; then
  skipped "this is an Elixir repository and mix is not installed on this machine"
fi
if [ -f package.json ] && ! command -v npm >/dev/null 2>&1; then
  skipped "this is a Node repository and npm is not installed on this machine"
fi
skipped "no package.json, no mix.exs and no scripts/doctor.sh"
