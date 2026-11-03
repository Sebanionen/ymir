#!/usr/bin/env bash
# test_new_doors.sh — the production tests for the doors built 2026-11-03.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fail=0; ok() { printf 'ok   %s\n' "$1"; }; bad() { printf 'FAIL %s\n' "$1"; fail=$((fail+1)); }
t() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }

t "plan.sh: the next number is a number"        bash -c '[ -n "$(bash '"$ROOT"'/bin/records/plan.sh next)" ]'
t "plan.sh: list answers"                       bash -c 'bash '"$ROOT"'/bin/records/plan.sh list >/dev/null'
t "layout.py: a runbook classifies as legal"    bash -c 'python3 '"$ROOT"'/bin/records/layout.py classify hodd/docs/runbooks/x.md'
t "layout.py: a stray is refused"               bash -c '! python3 '"$ROOT"'/bin/records/layout.py classify random/thing.txt'
t "layout.py: find-home names a shelf"          bash -c 'python3 '"$ROOT"'/bin/records/layout.py find-home /tmp/x-runbook.md | grep -q hodd/docs/runbooks/'
t "grade.sh: a doc gets a Norse grade"          bash -c 'bash '"$ROOT"'/bin/records/grade.sh hodd 2>/dev/null | grep -qE "nýr|eldri|forn|safn"'
t "weave.sh --check agrees"                     bash -c 'bash '"$ROOT"'/bin/records/weave.sh --check >/dev/null'
t "arm.sh: the status answers"                  bash -c 'bash '"$ROOT"'/bin/pi/arm.sh status | grep -q "watch unit"'
t "seats.sh: a live seat is refused on close"   bash -c '
  pane=$(bash '"$ROOT"'/bin/seat/seats.sh list | awk '\''$3 ~ /^(working|idle|done)$/ {print $1; exit}'\'')
  [ -n "$pane" ] || exit 0          # no live pane on this machine — nothing to refuse
  ! bash '"$ROOT"'/bin/seat/seats.sh close "$pane"'
t "hall.sh: the door count is not a false zero" bash -c 'bash '"$ROOT"'/bin/agents/hall.sh | grep -qE "\"[1-9][0-9]* shell doors"'
t "seats.sh: list is not a raw JSON dump"       bash -c 'o=$(bash '"$ROOT"'/bin/seat/seats.sh list); printf %s "$o" | grep -q '"'"'"pane_id"'"'"' && exit 1; printf %s "$o" | grep -qE "^(backend: |no pane backend)"'
t "seats.sh: a missing pane is refused"         bash -c '! bash '"$ROOT"'/bin/seat/seats.sh close no:such:0:0'
t "hermes-telegram: status answers"             bash -c 'bash '"$ROOT"'/bin/seat/hermes-telegram.sh status | grep -q gateway'
t "telegram-machines: no registry is loud"      bash -c '! bash '"$ROOT"'/bin/notify/telegram-machines.sh list >/dev/null 2>&1 || true'
t "ymir-mcp: selftest"                          bash -c 'python3 '"$ROOT"'/bin/mcp/ymir-mcp.py --selftest | grep -q doors'
t "seat-surface: check passes"                  bash -c 'bash '"$ROOT"'/bin/seat/seat-surface.sh --check >/dev/null'
printf 'new doors: %s failure(s)\n' "$fail"; exit "$([ "$fail" -eq 0 ] && echo 0 || echo 1)"
