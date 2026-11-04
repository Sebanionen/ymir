#!/usr/bin/env bash
# weave.sh — the dispatcher for every WOVEN document and every INDEX (Þættir, plan 174/175).
#
#   weave.sh                # weave what can be woven, then check every index
#   weave.sh --check        # exit 1 on any drift (a woven file stale, an entry missing from its index)
#   weave.sh --fix-count    # the rules index count only
#   weave.sh --fix          # append the rows a plan or a rule is missing (never a rewrite)
#
# A woven file is generated (FEATURES.md · the registers) and answered by the merge driver.
# An INDEX is hand-kept prose whose rows collide; this door cannot rewrite prose safely, so it
# CHECKS completeness — every rule, plan and feature page must have a row — and names the gap.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
hoard="$(bash "$ROOT/bin/vault/hodd.sh" path 2>/dev/null || true)"; HOME_DIR="$(dirname "${hoard:-/}")"
LEDGER="$(find "$HOME_DIR/svartalfaheim" -maxdepth 4 -type d -path '*/projects/ymir/plans' 2>/dev/null | head -1)"
bad=0
# A ROW IS NOT A MENTION IN A COMMENT. `grep -qF` alone counted a row that had been commented out
# (`#  "01-domains.md"`) as present — proved while wiring weave-guard on 2026-11-04, and that is
# exactly the hand-edit the ward exists to refuse. Comment lines are dropped before the presence
# test, and the verdict is a case match rather than `grep -q` in a pipeline: under `pipefail` the
# reader's early exit (SIGPIPE) reads as a failure, which made every large index look unindexed.
has_row() {
  local text; text="$(grep -vE '^[[:space:]]*#' "$1" 2>/dev/null)" || true
  case "$text" in *"$2"*) return 0 ;; esac
  return 1
}
check_rules() {
  local n; n=$(ls "$ROOT"/RULES/*.md 2>/dev/null | grep -vc 'README.md')
  local idx; idx=$(sed -n 's/^rules_index\[\([0-9]*\)\].*/\1/p' "$ROOT/RULES/README.md" | head -1)
  if [ "${idx:-0}" != "$n" ]; then printf 'rules: index says %s, disk holds %s\n' "${idx:-?}" "$n"; bad=$((bad+1)); fi
  for f in "$ROOT"/RULES/[0-9]*.md; do
    b="$(basename "$f")"
    has_row "$ROOT/RULES/README.md" "$b" || { printf 'rules: %s has no README row\n' "$b"; bad=$((bad+1)); }
  done
}
check_plans() {
  [ -d "${LEDGER:-}" ] || return 0
  for f in "$LEDGER"/[0-9]*.md; do
    b="$(basename "$f")"
    has_row "$LEDGER/README.md" "$b" || { printf 'plans: %s has no README row\n' "$b"; bad=$((bad+1)); }
  done
}
check_features() {
  local cat="$ROOT/docs/features/_catalogue" rows
  [ -d "$cat/entries" ] || return 0
  rows="$(cat "$cat"/entries/*.md 2>/dev/null | grep -vE '^[[:space:]]*#')" || true
  for f in "$ROOT"/docs/features/*.md; do
    b="$(basename "$f")"; [ "$b" = README.md ] && continue
    case "$rows" in
      *"docs/features/$b"*) ;;
      *) printf 'features: %s is not catalogued\n' "$b"; bad=$((bad+1)) ;;
    esac
  done
}
case "${1:-}" in
  -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --fix-count)
    n=$(ls "$ROOT"/RULES/*.md 2>/dev/null | grep -vc 'README.md')
    sed -i "s/^rules_index\[[0-9]*\]/rules_index[$n]/" "$ROOT/RULES/README.md" && printf 'rules index: %s\n' "$n" ;;
  --check) check_rules; check_plans; check_features; [ "$bad" -eq 0 ] && printf 'indexes: agree\n' || { printf 'weave: %s drift(s)\n' "$bad" >&2; exit 1; } ;;
  --fix)
    # append the missing rows — a row is ADDED, never a rewrite (Rule 06)
    added=0
    if [ -n "${LEDGER:-}" ] && [ -f "$LEDGER/README.md" ]; then
      for f in "$LEDGER"/[0-9]*.md; do
        b="$(basename "$f")"; grep -qF "$b" "$LEDGER/README.md" && continue
        n="$(printf '%s' "$b" | grep -oE '^[0-9]+')"
        t="$(sed -n '1s/^# *//p' "$f" | sed 's/^Plan [0-9]* *[-—:]* *//')"
        printf '| %s | [%s](%s) | opened |\n' "$n" "$t" "$b" >> "$LEDGER/README.md"; added=$((added+1))
      done
    fi
    for f in "$ROOT"/RULES/[0-9]*.md; do
      b="$(basename "$f")"; grep -qF "$b" "$ROOT/RULES/README.md" && continue
      n="$(printf '%s' "$b" | grep -oE '^[0-9]+')"
      t="$(sed -n '1s/^# *//p' "$f" | sed 's/^Rule [0-9]* *[-—:]* *//')"
      printf '| %s | `%s` | %s |\n' "$n" "$b" "$t" >> "$ROOT/RULES/README.md"; added=$((added+1))
    done
    printf 'weave: %s row(s) appended\n' "$added" ;;
  "")
    # WEAVE-WHAT-CAN-BE-WOVEN. This arm was unreachable until 2026-11-04: the help arm also
    # matched the empty argument, so `weave.sh` printed its usage and wove nothing — the mode the
    # pre-commit hook calls first (plan 175 §3) answered with a manual page. Found while wiring
    # the hook; a dispatcher whose default does nothing silently is a door that opens onto a wall.
    bash "$ROOT/bin/records/weave-features.sh" >/dev/null 2>&1 || true
    bash "$ROOT/bin/gates/inventory.sh" >/dev/null 2>&1 || true
    bash "$ROOT/bin/gates/capabilities.sh" >/dev/null 2>&1 || true
    check_rules; check_plans; check_features
    [ "$bad" -eq 0 ] && printf 'woven and checked: no drift\n' || printf 'woven; %s index drift(s) remain (see above)\n' "$bad" ;;
  *) printf 'error: unknown action %s\nhelp: weave.sh [--check|--fix-count]\n' "$1" >&2; exit 2 ;;
esac
