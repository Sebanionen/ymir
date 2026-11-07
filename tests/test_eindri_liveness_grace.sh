#!/usr/bin/env bash
# test_eindri_liveness_grace.sh — a quiet pane is not evidence of death.
#
# The defect this pins (2026-11-06): an errand launched at 23:10:11Z was judged
# dead at 23:14:10Z — 3m59s later — because herdr reported its agent `done`, and
# `done` means *idle between turns*, not *finished*. The sweep then spent its
# once-only delivery mark on the wrong verdict, so the worker's own terminal word
# could neither heal the report shelf nor raise a wake.
#
# So the rule is now: inside the settling grace a quiet seat reads SETTLING, and
# SETTLING corrects nothing. Past the grace it still reads DEAD — the door must
# keep working, or the fix trades a false alarm for a blind eye.
#
# Usage: bash tests/test_eindri_liveness_grace.sh
# Exit: 0 pass · 1 fail · 0 with `skip` when herdr is absent (a clean skip is a pass)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
LIVE="$ROOT/bin/agents/eindri-liveness.sh"
[ -x "$LIVE" ] || { printf 'fail: %s is not executable\n' "$LIVE"; exit 1; }

if ! command -v herdr >/dev/null 2>&1; then
  printf 'skip: herdr is not installed on this seat — the pane cannot be read\n'
  exit 0
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
now="$(date +%s)"

seat() {  # <id> <launched-epoch> — a meta + a non-terminal claim, no pane behind it
  cat >"$TMP/$1.meta" <<EOF
id=$1
engine=ymir_runtime/phase1
harness=pi
backend=herdr
window=@no-such-pane
worktree=$TMP/no-such-worktree
launched=$2
EOF
  printf 'working: launched %s (test fixture)\n' "$2" >"$TMP/$1.status"
}

seat young $((now - 60))     # 60s old — inside the 10 min grace
seat old   $((now - 7200))   # two hours old — past it

run() {
  YMIR_STATE_DIR="$TMP" YMIR_LIVENESS_GRACE_MIN="${1:-10}" \
    bash "$LIVE" check young old 2>&1
}

out="$(run 10)"
fail=0

case "$out" in
  *'"young","SETTLING"'*) printf 'pass: a 60s-old quiet seat reads SETTLING\n' ;;
  *'"young","DEAD"'*)     printf 'fail: a 60s-old quiet seat was judged DEAD (the 2026-11-06 defect)\n'; fail=1 ;;
  *) printf 'fail: no verdict for "young" in %.200s\n' "$out"; fail=1 ;;
esac

case "$out" in
  *'"old","DEAD"'*)    printf 'pass: a two-hour-old quiet seat still reads DEAD\n' ;;
  *'"old","SETTLING"'*) printf 'fail: the grace swallowed a genuinely dead seat\n'; fail=1 ;;
  *) printf 'fail: no verdict for "old" in %.200s\n' "$out"; fail=1 ;;
esac

# The grace must be the lever, not a constant: at 0 minutes the young seat dies too.
out0="$(run 0)"
case "$out0" in
  *'"young","DEAD"'*) printf 'pass: YMIR_LIVENESS_GRACE_MIN=0 makes the young seat DEAD\n' ;;
  *) printf 'fail: the grace is not configurable (grace 0 still read SETTLING)\n'; fail=1 ;;
esac

# `check` must never write: the record is corrected by `sweep` alone.
if [ "$(cat "$TMP/young.status")" = "working: launched $((now - 60)) (test fixture)" ]; then
  printf 'pass: check corrected nothing\n'
else
  printf 'fail: check mutated the status record\n'; fail=1
fi

exit "$fail"
