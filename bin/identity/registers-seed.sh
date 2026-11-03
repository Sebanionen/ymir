#!/usr/bin/env bash
# registers-seed.sh — give a home the identity registers it is missing, from ONE template each.
#
#   registers-seed.sh            # seed every absent register under hodd/identity/
#   registers-seed.sh --check    # say what a real run would seed; write nothing
#
# The registers are the houses the operator IS (`companies.yaml`), the companies a house SERVES
# (`clients.yaml`), the projects that belong to a house (`projects.yaml`) and the realms those
# projects may name (`workspaces.yaml`) — four facts, four files, and each arrives from
# `registry/<name>.yaml.example`
# in the code tree (plan 128). This is the ONE place that copies them: the installer calls it,
# and no script writes YAML inline any more — two sources of one truth drift by construction.
#
# An existing register is NEVER touched: what the operator wrote is his record, not a
# script's default.
#
# Exit: 0 ok (created or nothing to do), 1 a template is missing from the shelf.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Resolve the hoard (Rule 07)
if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  for _c in "$SCRIPT_DIR/../vault/hoard-lib.sh" \
             "$SCRIPT_DIR/../../vault/hoard-lib.sh" \
             "$SCRIPT_DIR/../../../vault/hoard-lib.sh"; do
    [ -r "$_c" ] && { . "$_c"; YMIR_HOARD_LIB_LOADED=1; break; }
  done
  unset _c
fi
if [ -z "${YMIR_HOME:-}" ] && command -v ymir_home_root >/dev/null 2>&1; then
  ymir_home_root YMIR_HOME
fi

die() { printf 'registers-seed: %s\n' "$*" >&2; exit 1; }

CHECK=0
case "${1-}" in
  -h|--help|help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") CHECK=0 ;;
  --check) CHECK=1 ;;
  *) die "unknown flag $1 — registers-seed.sh [--check]" ;;
esac

[ -n "${YMIR_HOME:-}" ] || die "the home is unresolved — set YMIR_HOME or record the choice at installation"
ID="$YMIR_HOME/hodd/identity"
REGISTERS="companies clients projects workspaces"
made=0 kept=0 missing=""

[ "$CHECK" = 0 ] && mkdir -p "$ID"
for r in $REGISTERS; do
  tpl="$ROOT/registry/$r.yaml.example"
  [ -f "$tpl" ] || { missing="$missing $r"; continue; }
  if [ -f "$ID/$r.yaml" ]; then
    kept=$((kept + 1))
    continue
  fi
  if [ "$CHECK" = 1 ]; then
    printf 'registers-seed: would seed %s from registry/%s.yaml.example\n' "$ID/$r.yaml" "$r"
    made=$((made + 1))
    continue
  fi
  cp "$tpl" "$ID/$r.yaml"
  printf 'registers-seed: seeded %s from registry/%s.yaml.example\n' "$ID/$r.yaml" "$r"
  made=$((made + 1))
done

[ -n "$missing" ] && die "no template for:$missing — the shelf $ROOT/registry/ is incomplete"
[ "$made" -eq 0 ] && printf 'registers-seed: %d register(s) already stand — nothing touched\n' "$kept"
exit 0
