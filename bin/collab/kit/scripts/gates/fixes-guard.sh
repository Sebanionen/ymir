#!/usr/bin/env bash
# fixes-guard — a behaviour change leaves a note, or says why it did not need one.
#
# Called from pre-push with the range being pushed: it refuses when the range touches code and adds no file under docs/fixes/.
#   bash scripts/gates/fixes-guard.sh <base-sha> <head-sha>
set -uo pipefail
base="${1:-}"; head="${2:-HEAD}"
[ -z "$base" ] && exit 0

if [ "${YMIR_SKIP_FIXES_GUARD:-0}" = "1" ]; then
  printf 'fixes-guard: skipped at the operator'"'"'s word\n'
  exit 0
fi

changed="$(git diff --name-only "$base..$head" 2>/dev/null)"
notes="$(printf '%s\n' "$changed" | grep -c '^docs/fixes/.*\.md$' || true)"
# The code shelves of every repository the kit goes into — Node, Elixir, shell. Appended 2026-11-06: the first
# version named only `backend|src|scripts|shared`, which is one project's shape, so in an Elixir repository the
# guard inspected nothing and refused nothing while looking like it was watching.
code="$(printf '%s\n' "$changed" | grep -cE '^(\.githooks|apps|backend|bin|config|lib|priv|rel|scripts|shared|src|test|tests)/' || true)"

if [ "${code:-0}" -gt 0 ] && [ "${notes:-0}" -eq 0 ]; then
  printf 'fixes-guard refused: this push changes code and adds no fix note.\n'
  printf '  write one:  bash scripts/fixes.sh record --component=<api|data|ui|mail|gates|docs> --title="…"\n'
  printf '  or, if it truly carries no behaviour:  YMIR_SKIP_FIXES_GUARD=1 git push …  and say why in the commit\n' >&2
  exit 1
fi
printf 'fixes-guard: %s code file(s), %s note(s)\n' "${code:-0}" "${notes:-0}"
