#!/usr/bin/env bash
# runtime-deploy.sh — move the PINNED runtime checkout to the merged tree, and prove what is running.
#
#   bin/engine/runtime-deploy.sh --check     what the units run, against origin/<branch>; changes nothing
#   bin/engine/runtime-deploy.sh            fetch, move the pinned checkout, install its dependencies,
#                                           restart the units, prove each one, print the commit
#   bin/engine/runtime-deploy.sh --help
#
# WHY. On 2026-11-02 ten systemd user units were found executing files from the operator's WORKING tree — the
# directory agents check branches out in — so a `git checkout` changed the code the scheduler, the well, the
# model bridge, the MCP face, the warden and the assistant were running, with no approval and no restart
# (RULES/02 §7). This is the door that ends that: the units point at a checkout that only ever stands on the
# default branch, and this verb moves it and proves the result.
#
# Configuration (Rule 07 — resolved, never hardcoded):
#   $YMIR_HOME/config/runtime.env   YMIR_RUNTIME_DIR · YMIR_RUNTIME_UNITS · YMIR_RUNTIME_BRANCH
#   GIMLE-style defaults: <home>/ymir-runtime · the ten units · main
set -uo pipefail

ROOT="$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
home=""
declare -f ymir_home_root >/dev/null 2>&1 && ymir_home_root home 2>/dev/null
[ -n "$home" ] || home="${YMIR_HOME:-}"
conf="${home:+$home/config/runtime.env}"
[ -n "$conf" ] && [ -r "$conf" ] && . "$conf"

RUN_DIR="${YMIR_RUNTIME_DIR:-$HOME/ymir-runtime}"
BRANCH="${YMIR_RUNTIME_BRANCH:-main}"
UNITS="${YMIR_RUNTIME_UNITS:-bifrost calendar-watch garmr-brain housewatch mcp-gateway mimir nornir skirnir-telegram skirnir-timer ymir-syn-watch}"

action="deploy"
case "${1:-}" in
  -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --check) action="check" ;;
  ""|--deploy) ;;
  *) printf 'error: unknown action %s\nhelp: runtime-deploy.sh [--check]\n' "$1" >&2; exit 2 ;;
esac

[ -d "$RUN_DIR/.git" ] || {
  printf 'FAIL\tno pinned checkout\tthere is no git checkout at %s — the units are running a working tree\n' "$RUN_DIR"
  printf 'help\tgit clone https://github.com/zerwiz/ymir %s && re-point the units\n' "$RUN_DIR"
  exit 1; }

running=$(git -C "$RUN_DIR" rev-parse --short HEAD 2>/dev/null | tr -d '[:space:]')
git -C "$RUN_DIR" fetch -q origin "$BRANCH" || {
  printf 'FAIL\tthe checkout could not fetch\tgit -C %s fetch origin %s failed\n' "$RUN_DIR" "$BRANCH"; exit 1; }
merged=$(git -C "$RUN_DIR" rev-parse --short "origin/$BRANCH" | tr -d '[:space:]')

if [ "$action" = "check" ]; then
  if [ "$running" = "$merged" ]; then
    printf 'deployed\t%s\t%s\tthe pinned runtime stands on origin/%s\n' "$running" "$merged" "$BRANCH"; exit 0
  fi
  printf 'STALE\trunning=%s merged=%s\trun runtime-deploy.sh\n' "$running" "$merged"; exit 1
fi

# 1. the pinned checkout moves — never a working tree, and never a merge commit of its own
git -C "$RUN_DIR" checkout -q "$BRANCH" && git -C "$RUN_DIR" reset -q --hard "origin/$BRANCH" || {
  printf 'FAIL\tthe checkout could not be moved to origin/%s\n' "$BRANCH"; exit 1; }
now=$(git -C "$RUN_DIR" rev-parse --short HEAD | tr -d '[:space:]')

# 2. its dependency closure, because node-based tools (the calendar reader, the MCP faces) need it and a fresh
#    clone has none — measured 2026-11-02: calendar-watch died on `Cannot find package 'zod'`.
if [ -f "$RUN_DIR/package-lock.json" ] && [ ! -d "$RUN_DIR/node_modules/zod" ]; then
  printf 'deps\tinstalling the runtime dependency closure (npm ci --omit=dev)\n'
  ( cd "$RUN_DIR" && npm ci --omit=dev --no-audit --no-fund >/dev/null 2>&1 ) || {
    printf 'FAIL\tthe dependency closure did not install\trun it by hand: cd %s && npm ci --omit=dev\n' "$RUN_DIR"; exit 1; }
fi

# 3. restart, then prove each unit by its own state (a oneshot that exits 0 is `inactive/dead` and CORRECT)
systemctl --user daemon-reload
for u in $UNITS; do
  systemctl --user list-unit-files "$u.service" >/dev/null 2>&1 || continue
  systemctl --user restart "$u" >/dev/null 2>&1
done
sleep 6

fail=0
for u in $UNITS; do
  systemctl --user list-unit-files "$u.service" >/dev/null 2>&1 || continue
  state=$(systemctl --user show -p ActiveState -p SubState --value "$u" 2>/dev/null | paste -sd/ -)
  type=$(systemctl --user show -p Type --value "$u" 2>/dev/null)
  case "$type:$state" in
    oneshot:inactive/dead|oneshot:active/*|simple:active/running|notify:active/running|exec:active/running|forking:active/running) ok=1 ;;
    *) ok=0 ;;
  esac
  printf '%-20s %-10s %-20s %s\n' "$u" "${type:-simple}" "${state:-unknown}" "$([ "$ok" = 1 ] && echo ok || echo FAIL)"
  [ "$ok" = 1 ] || fail=1
done

if [ "$fail" -ne 0 ]; then
  printf 'FAIL\ta unit did not settle after the move\tcommit %s is in place; see: journalctl --user -u <unit> -n 40\n' "$now"
  exit 1
fi
printf 'deployed\t%s\t%s\tthe pinned runtime moved and every unit settled\n' "$now" "$RUN_DIR"
