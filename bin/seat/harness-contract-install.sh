#!/usr/bin/env bash
# harness-contract-install.sh — every harness reads ONE contract, and an update keeps it true.
#
#   bin/seat/harness-contract-install.sh            install (idempotent): link each harness's global
#                                                   instruction file to the seat's one contract
#   bin/seat/harness-contract-install.sh --check    report per harness: linked · stale copy · absent
#
# WHY. Measured 2026-11-02: OpenCode's global `AGENTS.md` was a COPY of the machine contract from
# 2026-10-02 — three weeks stale — while Claude and Codex pointed at the seat's one file and Pi had no
# global contract at all (`~/.pi/agent/extensions/` held two marker files and nothing else). An install or
# an update that does not refresh the contract leaves a user's agent obeying last month's law.
#
# The rule (RULES/13, 2026-11-02; RULES/25, third section): the instruction file each tool actually reads is
# written into the USER'S OWN home on install AND re-verified on update.
set -uo pipefail

ROOT="$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
home=""; declare -f ymir_home_root >/dev/null 2>&1 && ymir_home_root home 2>/dev/null
[ -n "$home" ] || home="${YMIR_HOME:-}"

CANON="${YMIR_CONTRACT:-$HOME/.agents/AGENTS.md}"     # the seat's one machine contract
[ -r "$CANON" ] || { printf 'SKIP\tno contract to install\tthere is no %s on this seat\n' "$CANON"; exit 0; }

# The file each harness actually reads, in ITS own global location (measured, not guessed).
targets=(
  "$HOME/.pi/agent/AGENTS.md"
  "$HOME/.config/opencode/AGENTS.md"
  "$HOME/.claude/CLAUDE.md"
  "$HOME/.codex/AGENTS.md"
)

action="${1:-install}"
case "$action" in
  --check|check) mode=check ;;
  ""|install|--install) mode=install ;;
  -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) printf 'error: unknown action %s\nhelp: harness-contract-install.sh [--check]\n' "$action" >&2; exit 2 ;;
esac

fail=0
printf 'contract[%s]{harness,state,detail}:\n' "${#targets[@]}"
for t in "${targets[@]}"; do
  label=$(printf '%s' "$t" | sed "s#$HOME/##")
  dir=$(dirname "$t"); [ -d "$dir" ] || { printf '  "%s","absent","the harness is not installed here"\n' "$label"; continue; }
  if [ -L "$t" ]; then
    now=$(readlink -f "$t" 2>/dev/null)
    if [ "$now" = "$(readlink -f "$CANON")" ]; then
      printf '  "%s","linked","%s"\n' "$label" "$CANON"
      continue
    fi
    printf '  "%s","wrong link","→ %s (not the seat contract)"\n' "$label" "${now:-broken}"
    [ "$mode" = install ] && ln -sfn "$CANON" "$t" && printf '  "%s","relinked","%s"\n' "$label" "$CANON"
    continue
  fi
  if [ -f "$t" ]; then
    if cmp -s "$t" "$CANON"; then
      printf '  "%s","identical copy","same bytes; linking it makes the next update reach it"\n' "$label"
      [ "$mode" = install ] && { cp -p "$t" "$t.bak-$(date -u +%Y%m%d-%H%M%S)"; ln -sfn "$CANON" "$t"; }
      continue
    fi
    printf '  "%s","STALE COPY","a real file that differs from the contract"\n' "$label"
    fail=1
    if [ "$mode" = install ]; then
      cp -p "$t" "$t.bak-$(date -u +%Y%m%d-%H%M%S)"
      ln -sfn "$CANON" "$t"
      printf '  "%s","linked","kept the old copy beside it as .bak-<stamp>"\n' "$label"
      fail=0
    fi
    continue
  fi
  [ "$mode" = install ] && ln -sfn "$CANON" "$t" && printf '  "%s","linked","%s"\n' "$label" "$CANON"
done

if [ "$mode" = check ] && [ "$fail" = 1 ]; then
  printf 'help: bin/seat/harness-contract-install.sh (links each harness to %s, keeping the old file as .bak)\n' "$CANON" >&2
  exit 1
fi
[ "$mode" = check ] && printf 'contract[1]{state}:\n  "current","every installed harness reads the seat contract"\n'
exit 0
