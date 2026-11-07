#!/usr/bin/env bash
# weave-guard.sh — an index that does not name every file it indexes is refused.
#
# Plan 175 §3 gives the woven documents three layers with three different jobs, and none of them
# substitutes for another:
#
#   the merge driver  RESOLVES   a conflict on a woven file is answered by weaving (already seated)
#   the pre-commit hook CONVENIENCE  weaves the four woven files, names them, stages only them
#   THIS WARD         THE LAW     a stale index is refused, and the gap is named
#
# It asks one question of the dispatcher — `bin/records/weave.sh --check`: does every index still
# name every rule, every plan and every feature page? A row a hand edits and the rows the files own
# drift apart in exactly one way: silently.
#
# IT NEVER FIXES. `weave.sh --fix` appends the missing rows and the hook runs the weaver; a WARD
# that repaired the drift would hide the hand-edit that caused it, and a gate whose findings
# disappear by themselves has judged nothing.
#
#   weave-guard.sh              # check
#   weave-guard.sh check        # same
#   weave-guard.sh --all        # same
#   weave-guard.sh --version
#
# Exit: 0 every index agrees · 1 drift (named) · 2 usage.
set -u
VERSION="1.0.0"

_root() {
  local d; d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [ "$d" != "/" ]; do
    [ -d "$d/.pi" ] && [ -d "$d/RULES" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
}
ROOT="$(_root)"
WEAVE="$ROOT/bin/records/weave.sh"

case "${1-}" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  check|--all|"") ;;
  *) printf 'error: unknown action %s\nhelp: weave-guard.sh [check|--all]\n' "${1-}" >&2; exit 2 ;;
esac

if [ ! -r "$WEAVE" ]; then
  printf 'weave-guard[3]{finding,index,detail}:\n  "no weaver","","bin/records/weave.sh is missing — no index can be judged"\n'
  printf 'help: restore the dispatcher (plan 175); a ward without its dispatcher is a wish\n' >&2
  exit 1
fi

# The dispatcher's own word, carried up rather than paraphrased: it names the gap, and a gate that
# does not say why is an obstacle rather than a gate.
out="$(bash "$WEAVE" --check 2>&1)" && rc=0 || rc=$?

printf 'weave-guard[3]{finding,index,detail}:\n'
if [ "$rc" -eq 0 ]; then
  printf '  "none","rules · plans · features","every index names every file it indexes — %s"\n' \
    "$(printf '%s' "$out" | grep -E '^indexes: ' | tail -1)"
  exit 0
fi

# A finding line is `<index>: <detail>`; anything else (the dispatcher's own tally) is not a finding.
drift=0
while IFS= read -r ln; do
  case "$ln" in ''|'weave: '*) continue ;; esac
  case "$ln" in
    *': '*) idx="${ln%%:*}"; det="${ln#*: }" ;;
    *)       idx=""; det="$ln" ;;
  esac
  printf '  "an index has drifted","%s","%s"\n' "$idx" "$det"
  drift=$((drift + 1))
done <<EOF
$out
EOF

if [ "$drift" -eq 0 ]; then
  printf '  "the weaver itself failed","","bin/records/weave.sh answered %s with no named gap — run it by hand"\n' "$rc"
  printf 'weave-guard: the weaver failed without naming a gap (exit %s)\nhelp: run bin/records/weave.sh --check by hand; this ward only carries its word\n' "$rc" >&2
  exit 1
fi

printf 'weave-guard: %s index drift(s) — a rule, a plan or a feature page is not named by its index\nhelp: weave the index in the SAME change — bin/records/weave.sh --fix appends the missing rows, commit them; this ward never fixes, because a silent fix hides the hand-edit that caused the drift (plan 175 §3)\n' "$drift" >&2
exit 1
