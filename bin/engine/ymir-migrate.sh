#!/usr/bin/env bash
# ymir-migrate.sh — versioned STRUCTURE migrations for existing Ymir homes.
#
#   bin/engine/ymir-migrate.sh status           # which migrations exist / are applied
#   bin/engine/ymir-migrate.sh apply            # apply everything pending, in order
#   bin/engine/ymir-migrate.sh apply --dry-run  # show what would run, touch nothing
#   bin/engine/ymir-migrate.sh --version
#
# Each migration is `.agents/migrations/<NNNN>-<name>.sh`, MUST be idempotent,
# and runs with `bash`. Applied ids are recorded in `state/migrations` (private).
# `bin/engine/ymir-install.sh` and `bin/agents/brokk-update.sh` call `apply` after an update.
#
# A migration may answer with a THIRD outcome, exit 3 = DEFERRED: it is a real
# migration that this machine cannot run yet (a destination nobody has named, a
# service that must be stopped first). It is reported, never recorded as applied —
# recording it would silence it forever — and never treated as a failure.
set -u
# The ONE resolver (Rule 07): env -> the recorded choice -> the one default.
if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  for _yc in "${ROOT:-}/bin/vault/hoard-lib.sh" \
             "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/bin/vault/hoard-lib.sh" \
             "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/bin/vault/hoard-lib.sh" \
             "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/hoard-lib.sh"; do
    [ -n "$_yc" ] && [ -r "$_yc" ] && { . "$_yc"; YMIR_HOARD_LIB_LOADED=1; break; }
  done
  unset _yc
fi
if [ -z "${YMIR_HOME:-}" ] && command -v ymir_home_root >/dev/null 2>&1; then
  ymir_home_root YMIR_HOME
fi

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"
YMIR_HOME="${YMIR_HOME}"
MIG_DIR="$ROOT/.agents/migrations"
STATE_DIR="${YMIR_STATE_DIR:-$YMIR_HOME/state}"
APPLIED="$STATE_DIR/migrations"

case "${1-}" in -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help|"") sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac

ACTION="${1:-status}"; shift || true
DRY=0
for a in "$@"; do case "$a" in --dry-run|-n) DRY=1 ;; esac; done

[ -d "$MIG_DIR" ] || { printf 'ymir-migrate[1]{state}:\n  "none","no migrations directory"\n'; exit 0; }
mkdir -p "$STATE_DIR"; [ -f "$APPLIED" ] || : >"$APPLIED"

is_applied() { grep -qxF "$1" "$APPLIED" 2>/dev/null; }
desc_of() { sed -n 's/^# *[0-9]\{4\}-[a-z0-9-]* *—* *//p' "$1" | head -1; }

mapfile -t MIGS < <(ls "$MIG_DIR"/[0-9][0-9][0-9][0-9]-*.sh 2>/dev/null | sort)

if [ "$ACTION" = status ]; then
  printf 'ymir-migrate[%d]{migration,state,description}:\n' "${#MIGS[@]}"
  for m in "${MIGS[@]}"; do
    id="$(basename "$m" .sh)"
    if is_applied "$id"; then st=applied; else st=pending; fi
    printf '  "%s","%s","%s"\n' "$id" "$st" "$(desc_of "$m")"
  done
  exit 0
fi

[ "$ACTION" = apply ] || { printf 'error: unknown action %s\nhelp: bin/engine/ymir-migrate.sh [status|apply [--dry-run]]\n' "$ACTION" >&2; exit 2; }

ran=0; skipped=0; deferred=0
for m in "${MIGS[@]}"; do
  id="$(basename "$m" .sh)"
  if is_applied "$id"; then skipped=$((skipped+1)); continue; fi
  printf 'ymir-migrate[1]{apply,migration}:\n  "%s","%s"\n' "$([ "$DRY" = 1 ] && echo dry-run || echo run)" "$id"
  if [ "$DRY" = 1 ]; then
    # A dry run must be able to NAME what it would touch, so the migration sees the
    # flag. A migration that ignores it and writes anyway is a bug, not a dry run.
    bash "$m" --dry-run || true
    continue
  fi
  bash "$m"; rc=$?
  case "$rc" in
    0) printf '%s\n' "$id" >>"$APPLIED"; ran=$((ran+1)) ;;
    # 3 = DEFERRED: the migration is legitimate but this machine cannot run it yet
    # (a destination nobody has named, a service that must be stopped first). It is
    # NOT applied — recording it would silence it forever — and it is NOT a failure,
    # because nothing is broken. It says why, and the next apply asks again.
    3) deferred=$((deferred+1)) ;;
    *) printf 'error: migration %s failed — stopping; fix and re-run\n' "$id" >&2; exit 1 ;;
  esac
done
printf 'ymir-migrate[1]{action,applied,pending}:\n  "%s",%s,%s\n' "$([ "$DRY" = 1 ] && echo dry-run || echo apply)" "$ran" "$skipped"
[ "$deferred" -eq 0 ] || printf 'ymir-migrate[1]{deferred,note}:\n  %s,"not applied and not failed — the reason is printed above"\n' "$deferred"
