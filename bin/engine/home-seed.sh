#!/usr/bin/env bash
# home-seed.sh — give a home the files it is missing, from the ONE contract.
#
#   home-seed.sh            # seed every absent `seeded` / `stub` row whose door is this script
#   home-seed.sh --check    # say what a real run would seed; write nothing
#   home-seed.sh --list     # print the contract's rows, tab-separated — the ONE parser
#
# WHY (RULES/42). A file the runtime reads and a user's home does not hold is a feature
# only its author has. Measured 2026-11-02: a fresh home had no `operator.md`, no
# `learnings.md`, no `machines.md`, no `projects.md` and no roster — the session digest
# opened with four ABSENT lines and the seat could not be named.
#
# `.agents/home-contract.yaml` is the single list: one row per home file the runtime
# READS, with its kind, its template and the door that writes it. This script walks that
# list and copies the shape of the rows it owns. It is ONE of the doors — the identity
# registers are `bin/identity/registers-seed.sh`, and the generated files belong to their
# generators — so it skips every row whose `door` is not itself. One owner per copy, or
# two sources of one truth drift by construction.
#
# What it never does:
#   · overwrite — a home file that exists is the operator's record, not a default
#   · invent   — a `generated` row is a door's output, not a seed
#   · guess    — a missing template is a loud failure naming the row
#
# Exit: 0 ok (seeded, or nothing to do) · 1 a template named by the contract is missing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"

# The home is resolved, never assumed (RULES/07, RULES/22).
if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  for _c in "$SCRIPT_DIR/../vault/hoard-lib.sh" "$SCRIPT_DIR/../../bin/vault/hoard-lib.sh"; do
    [ -r "$_c" ] && { . "$_c"; YMIR_HOARD_LIB_LOADED=1; break; }
  done
  unset _c
fi
if [ -z "${YMIR_HOME:-}" ] && command -v ymir_home_root >/dev/null 2>&1; then
  ymir_home_root YMIR_HOME
fi
CHECK=0
case "${1-}" in
  -h|--help|help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") CHECK=0 ;;
  --check) CHECK=1 ;;
  --list) CHECK=2 ;;
  *) printf 'error: unknown flag %s\nhelp: home-seed.sh [--check]\n' "$1" >&2; exit 2 ;;
esac

die() { printf 'home-seed: %s\n' "$*" >&2; exit 1; }

CONTRACT="$ROOT/.agents/home-contract.yaml"
[ -r "$CONTRACT" ] || die "no contract at $CONTRACT — the list of home files is missing from this checkout"
# --list is a reading of the SHAPE, not an act on a home: it must answer on a machine
# with no home at all, because the ward that judges this contract runs in CI.
[ "$CHECK" = 2 ] || [ -n "${YMIR_HOME:-}" ] || die "the home is unresolved — set YMIR_HOME or record the choice at installation"
SELF="bin/engine/home-seed.sh"

# The realm a `{realm}` path resolves to: the pin first, then the active realm.
REALM="${BROKK_REALM:-}"
if [ -z "$REALM" ] && [ -r "${YMIR_HOME:-}/hodd/data/realm.md" ]; then
  REALM="$(head -n 1 "${YMIR_HOME:-}/hodd/data/realm.md" 2>/dev/null | tr -d '[:space:]')"
fi
if [ -z "$REALM" ] && [ -r "$ROOT/bin/skuld/realm-lib.sh" ]; then
  # shellcheck source=bin/skuld/realm-lib.sh
  . "$ROOT/bin/skuld/realm-lib.sh"
  ymir_active_realm "$ROOT" REALM 2>/dev/null || true
fi
REALM="${REALM:-default}"

# The contract is read by ONE parser, here; the ward calls this script in --check mode
# rather than growing a second one. A row it cannot read is refused, never skipped.
rows="$(awk '
  function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); sub(/^"/, "", s); sub(/"$/, "", s); return s }
  /^  - path:/      { if (p != "") print p "\t" k "\t" t "\t" d "\t" r; p = trim(substr($0, index($0, ":") + 1)); k = ""; t = ""; d = ""; r = ""; next }
  /^    kind:/      { k = trim(substr($0, index($0, ":") + 1)); next }
  /^    template:/  { t = trim(substr($0, index($0, ":") + 1)); next }
  /^    door:/      { d = trim(substr($0, index($0, ":") + 1)); next }
  /^    required:/  { r = trim(substr($0, index($0, ":") + 1)); next }
  END               { if (p != "") print p "\t" k "\t" t "\t" d "\t" r }
' "$CONTRACT")"
[ -n "$rows" ] || die "the contract at $CONTRACT lists no rows — nothing can be seeded from it"
[ "$CHECK" = 2 ] && { printf '%s\n' "$rows"; exit 0; }

seeded=0; kept=0; skipped=0; missing=""
hint_roster=0
while IFS="$(printf '\t')" read -r path kind template door required; do
  [ -n "$path" ] || continue
  case "$kind" in
    seeded|stub) ;;
    *) skipped=$((skipped+1)); continue ;;   # defaulted · optional · generated: not this door's to write
  esac
  [ "$door" = "$SELF" ] || { skipped=$((skipped+1)); continue; }
  dest="$YMIR_HOME/${path//\{realm\}/$REALM}"
  tpl="$ROOT/$template"
  if [ -f "$dest" ]; then kept=$((kept+1)); continue; fi
  if [ -z "$template" ] || [ "$template" = "-" ] || [ ! -f "$tpl" ]; then
    missing="$missing $path"; continue
  fi
  if [ "$CHECK" = 1 ]; then
    printf 'home-seed: would seed %s from %s\n' "$path" "$template"
    seeded=$((seeded+1))
    continue
  fi
  mkdir -p "$(dirname "$dest")"
  if cp "$tpl" "$dest"; then
    case "$dest" in *.md) chmod 644 "$dest" ;; *) chmod 600 "$dest" ;; esac
    printf 'home-seed: seeded %s from %s\n' "${dest#"$YMIR_HOME"/}" "$template"
    seeded=$((seeded+1))
    case "$path" in hodd/identity/seats.yaml) hint_roster=1 ;; esac
  else
    missing="$missing $path"
  fi
done <<<"$rows"

[ -n "$missing" ] && die "no usable template for:$missing — the shelf the contract names is incomplete (bin/gates/checks/home-contract-check.sh names the row)"

if [ "$seeded" -eq 0 ]; then
  printf 'home-seed: %d file(s) already stand, %d row(s) belong to another door — nothing touched\n' "$kept" "$skipped"
else
  printf 'home-seed: %d file(s) seeded, %d already stood, %d row(s) belong to another door\n' "$seeded" "$kept" "$skipped"
fi

# An empty roster is honest, and useless until the operator names the seat (RULES/02 §4:
# a name is never a script's invention). Say the one command; do not invent a figure.
if [ "$hint_roster" = 1 ]; then
  printf 'home-seed: the roster is empty — name this seat: bin/agents/seat-identity.sh set %s brokk\n' "$(hostname -s 2>/dev/null || printf '<this-host>')"
fi
exit 0
