#!/usr/bin/env bash
# portability-ratchet.sh — the GNU-only callers may go DOWN, never up.
#
# Rule: RULES/05 (2026-11-02 appended) — every new core script that touches a host facility goes through
# `bin/fleet/ymir-platform.sh`, never through a GNU tool name.
#
# WHY A RATCHET AND NOT A WALL. Measured 2026-11-02: `stat -c` in 43 files, `sha256sum` in 43, `flock` in 10,
# `mapfile` in 7, `setsid` in 6, `nproc` in 5, `sed -i` in 4, `md5sum` in 3 — 121 callers, and only 24 files
# sourcing the shim. Fixing all of them in one change is a rewrite with no test; forbidding new ones is one
# file of arithmetic and can start today. Each count is compared against a baseline recorded in the home
# (`hodd/data/portability-baseline.yaml`) and the ward fails when a count RISES.
#
#   bash bin/gates/checks/portability-ratchet.sh [check] [--write-baseline]
#
# Exit: 0 within baseline · 1 a count rose · 2 usage.
set -uo pipefail

_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(CDPATH='' cd "$_d" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)"
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
home=""; declare -f ymir_home_root >/dev/null 2>&1 && ymir_home_root home 2>/dev/null
[ -n "$home" ] || home="${YMIR_HOME:-}"
base="${home:+$home/hodd/data/portability-baseline.yaml}"

# The verbs the shim provides, and the GNU spelling each replaces.
verbs[0]="stat -c";  fn[0]="ymir_stat"
verbs[1]="sha256sum"; fn[1]="ymir_sha256"
verbs[2]="flock";     fn[2]="ymir_lock"
verbs[3]="mapfile";   fn[3]="ymir_read_lines"
verbs[4]="nproc";     fn[4]="ymir_nproc"
verbs[5]="sed -i ";   fn[5]="ymir_sed_i"

mode="${1:-check}"
case "$mode" in
  -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  check|"") ;;
  --write-baseline) ;;
  *) printf 'error: unknown action %s\nhelp: portability-ratchet.sh [check] [--write-baseline]\n' "$mode" >&2; exit 2 ;;
esac

count_for() {  # how many FILES call this GNU spelling, ignoring the shim itself and its comments
  grep -rl --include=*.sh --include=*.py -- "$1" "$ROOT/bin" "$ROOT/systems" "$ROOT/scripts" 2>/dev/null \
    | grep -v "bin/fleet/ymir-platform.sh" | wc -l | tr -d ' '
}

declare -A now
total=0
for i in "${!verbs[@]}"; do
  now[$i]=$(count_for "${verbs[$i]}")
  total=$((total + now[$i]))
done

if [ "$mode" = "--write-baseline" ]; then
  [ -n "$base" ] || { printf 'error: no hoard to write the baseline into (set YMIR_HOME)\n' >&2; exit 2; }
  mkdir -p "$(dirname "$base")"
  {
    printf '# portability-baseline.yaml — how many files still call a GNU-only tool (RULES/05, 2026-11-02)\n'
    printf '# Written by bin/gates/checks/portability-ratchet.sh --write-baseline. A count may fall, never rise.\n'
    printf 'as_of: "%s"\n' "$(date -u +%Y-%m-%d)"
    printf 'counts:\n'
    for i in "${!verbs[@]}"; do printf '  "%s": %s\n' "${verbs[$i]// /}" "${now[$i]}"; done
    printf '  "total": %s\n' "$total"
  } >"$base"
  printf 'portability-ratchet[1]{state}:\n  "baseline written","%s (total %s)"\n' "$base" "$total"
  exit 0
fi

if [ ! -r "$base" ]; then
  printf 'portability-ratchet[1]{finding,detail}:\n  "no baseline","%s is absent — run --write-baseline once on a clean tree"\n' "$base"
  exit 0
fi

fail=0
printf 'portability-ratchet[%s]{verb,now,baseline,verdict}:\n' "${#verbs[@]}"
for i in "${!verbs[@]}"; do
  key="${verbs[$i]// /}"
  was=$(sed -n "s/^  \"$key\": \([0-9]*\).*/\1/p" "$base" | head -1)
  [ -n "$was" ] || was="?"
  if [ "$was" = "?" ]; then v="no baseline row"
  elif [ "${now[$i]}" -gt "$was" ]; then v="ROSE"; fail=1
  elif [ "${now[$i]}" -lt "$was" ]; then v="fell — lower the baseline"
  else v="ok"; fi
  printf '  "%s","%s","%s","%s"\n' "${verbs[$i]}" "${now[$i]}" "$was" "$v"
done

[ "$fail" = 1 ] && {
  printf 'help: route the new caller through %s (bin/fleet/ymir-platform.sh) instead of the GNU tool\n' "${fn[0]}" >&2
  exit 1; }
printf 'help: a count that fell may be lowered: run --write-baseline and commit the home file\n' >&2
exit 0
