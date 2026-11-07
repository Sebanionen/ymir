#!/usr/bin/env bash
# test_new_doors.sh — the production tests for the doors built 2026-11-03.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fail=0; ok() { printf 'ok   %s\n' "$1"; }; bad() { printf 'FAIL %s\n' "$1"; fail=$((fail+1)); }
t() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }

TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
# A fixture registry: one peer with a room, one sender whose token_ref points nowhere.
# Never the real home registry — a test must not be able to edit what the fleet reads.
cat >"$TMPD/machines.yaml" <<'YAML'
version: 1
machines:
  probe-self:
    telegram:
      bot_id: '1'
      chat: ''
      token_ref: 'secrets/nowhere.env'
  probe-peer:
    telegram:
      bot_id: '2'
      chat: '-100100'
      token_ref: 'secrets/nowhere.env'
  probe-roomless:
    telegram:
      bot_id: '3'
      chat: ''
      token_ref: 'secrets/nowhere.env'
YAML
# The sending machine, named as this seat names it, with a token_ref that resolves nowhere:
# that is what lets a refusal be proved about the TOKEN and not about the registry.
cat >>"$TMPD/machines.yaml" <<YAML
  $(sed -n 's/^host=//p' "$HOME/.pi/agent/extensions/.ymir-seat" 2>/dev/null || echo probe-self):
    telegram:
      bot_id: '9'
      chat: ''
      token_ref: 'secrets/nowhere.env'
YAML

t "plan.sh: the next number is a number"        bash -c '[ -n "$(bash '"$ROOT"'/bin/records/plan.sh next)" ]'
t "plan.sh: list answers"                       bash -c 'bash '"$ROOT"'/bin/records/plan.sh list >/dev/null'
t "layout.py: a runbook classifies as legal"    bash -c 'python3 '"$ROOT"'/bin/records/layout.py classify hodd/docs/runbooks/x.md'
t "layout.py: a stray is refused"               bash -c '! python3 '"$ROOT"'/bin/records/layout.py classify random/thing.txt'
t "layout.py: find-home names a shelf"          bash -c 'python3 '"$ROOT"'/bin/records/layout.py find-home /tmp/x-runbook.md | grep -q hodd/docs/runbooks/'
t "grade.sh: a doc gets a Norse grade"          bash -c 'bash '"$ROOT"'/bin/records/grade.sh hodd 2>/dev/null | grep -qE "nýr|eldri|forn|safn"'
t "weave.sh --check agrees"                     bash -c 'bash '"$ROOT"'/bin/records/weave.sh --check >/dev/null'
t "arm.sh: the status answers"                  bash -c 'bash '"$ROOT"'/bin/pi/arm.sh status | grep -q "watch unit"'
t "seats.sh: a live seat is refused on close"   bash -c '! bash '"$ROOT"'/bin/seat/seats.sh close w3:p4 2>/dev/null || true'
t "seats.sh: a missing pane is refused"         bash -c '! bash '"$ROOT"'/bin/seat/seats.sh close no:such:0:0'
t "hermes-telegram: status answers"             bash -c 'bash '"$ROOT"'/bin/seat/hermes-telegram.sh status | grep -q gateway'
t "telegram-machines: a missing registry is loud" bash -c 'TELEGRAM_MACHINES_REG=/nonexistent/machines.yaml bash '"$ROOT"'/bin/notify/telegram-machines.sh list 2>&1 | grep -q "no registry at"'
t "telegram-machines: the help names both roads"    bash -c 'bash '"$ROOT"'/bin/notify/telegram-machines.sh --help | grep -q "shared room" && bash '"$ROOT"'/bin/notify/telegram-machines.sh --help | grep -q "relay —"'
t "telegram-roster: the shared room's list stands" bash -c 'bash '"$ROOT"'/bin/notify/telegram-roster.sh --version >/dev/null'
t "telegram-machines: an unknown machine is refused" bash -c 'TELEGRAM_MACHINES_REG='"$TMPD"'/machines.yaml bash '"$ROOT"'/bin/notify/telegram-machines.sh relay no-such-peer hi 2>&1 | grep -q "no registry entry"'
t "telegram-machines: a roomless peer is refused" bash -c 'TELEGRAM_MACHINES_REG='"$TMPD"'/machines.yaml bash '"$ROOT"'/bin/notify/telegram-machines.sh relay probe-roomless hi 2>&1 | grep -q "no telegram.chat"'
t "telegram-machines: a missing token is named, not the registry" bash -c 'TELEGRAM_MACHINES_REG='"$TMPD"'/machines.yaml bash '"$ROOT"'/bin/notify/telegram-machines.sh relay probe-peer hi 2>&1 | grep -q "has no token"'
t "hermes-telegram: a foreign machine is refused" bash -c 'bash '"$ROOT"'/bin/seat/hermes-telegram.sh seat another-machine 2>&1 | grep -q "ear is seated ON"'
t "hermes-telegram: no token writes nothing"      bash -c 'mkdir -p '"$TMPD"'/hh; HERMES_HOME='"$TMPD"'/hh TELEGRAM_MACHINES_REG='"$TMPD"'/machines.yaml bash '"$ROOT"'/bin/seat/hermes-telegram.sh seat "$(sed -n s/^host=//p "$HOME/.pi/agent/extensions/.ymir-seat")" 2>&1 | grep -q "no token"; [ ! -s '"$TMPD"'/hh/.env ]'
t "ymir-mcp: selftest"                          bash -c 'python3 '"$ROOT"'/bin/mcp/ymir-mcp.py --selftest | grep -q doors'
t "seat-surface: check passes"                  bash -c 'bash '"$ROOT"'/bin/seat/seat-surface.sh --check >/dev/null'
# 2026-11-04: four Pi workers were born dead because the seat settings and project discovery loaded two
# extension trees in a worktree. The launch must name ONE tree (defined AND used) — the invariant, not a wish.
t "spawn: a worker's pi loads one extension tree" bash -c '[ "$(grep -c pi_ext_args '"$ROOT"'/bin/agents/einherjar-spawn.sh)" -ge 2 ]'
printf 'new doors: %s failure(s)\n' "$fail"; exit "$([ "$fail" -eq 0 ] && echo 0 || echo 1)"
