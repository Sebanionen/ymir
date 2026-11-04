#!/usr/bin/env bash
# fresh-base-check.sh — does this work start on the LATEST codebase? (Rule 45)
#
# WHY (2026-11-04): a seat sat seven commits behind origin, asked the plan ledger for
# the next number, and was handed one that another machine had already taken the same
# day. Two plans shared number 182 and the second had to be renumbered. The ledger now
# refuses to allocate from a stale home (bin/records/plan.sh). This is the same
# question asked of ANY tree: is the base the work will start from the current one?
#
# It FETCHES (that is the point — a remote ref nobody fetched is a memory), compares,
# and names how far behind. It never rebases, never merges, never pulls: starting work
# is the caller's act, so the repair stays visible.
#
#   fresh-base-check.sh                    # report the current tree
#   fresh-base-check.sh --strict           # exit 1 when behind (the errand door)
#   fresh-base-check.sh --repo DIR          # judge another tree
#   fresh-base-check.sh --quiet             # exit code only
#
# Exit: 0 fresh, or a CLEAN SKIP with the reason (not a git tree, no remote, offline)
#       1 behind, in --strict only
#       2 usage
#
# A clean skip is a pass (Rule 25): an honest seat offline is not a fault, but it is
# never silent — the reason is printed.
set -uo pipefail

ROOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
REPO="${YMIR_FRESH_REPO:-$ROOT_ROOT}"
STRICT=0; QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --strict) STRICT=1; shift ;;
    --quiet|-q) QUIET=1; shift ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'error: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
done

say() { [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }
skip() { say "fresh-base: SKIP — $*"; exit 0; }

command -v git >/dev/null 2>&1 || skip "no git on PATH"
git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || skip "$REPO is not a git working tree"

REMOTE="${YMIR_GIT_REMOTE:-origin}"
BRANCH="$(git -C "$REPO" symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null | sed "s#^$REMOTE/##")"
[ -n "$BRANCH" ] || BRANCH="${YMIR_GIT_BRANCH:-main}"

git -C "$REPO" remote get-url "$REMOTE" >/dev/null 2>&1 || skip "no '$REMOTE' remote — the base is UNVERIFIED, not stale"

[ "${YMIR_OFFLINE:-0}" = "1" ] && skip "YMIR_OFFLINE=1 — the base is UNVERIFIED against $REMOTE"
git -C "$REPO" fetch --quiet --prune "$REMOTE" 2>/dev/null || skip "$REMOTE is unreachable — the base is UNVERIFIED, not stale"

git -C "$REPO" rev-parse --verify -q "refs/remotes/$REMOTE/$BRANCH" >/dev/null 2>&1 \
  || skip "$REMOTE/$BRANCH does not exist — nothing to compare against"

HEAD_SHA="$(git -C "$REPO" rev-parse HEAD)"
BASE_SHA="$(git -C "$REPO" rev-parse "refs/remotes/$REMOTE/$BRANCH")"
BEHIND="$(git -C "$REPO" rev-list --count "HEAD..refs/remotes/$REMOTE/$BRANCH" 2>/dev/null || printf 0)"
BRANCH_NOW="$(git -C "$REPO" branch --show-current 2>/dev/null || printf 'detached')"

if [ "${BEHIND:-0}" = "0" ]; then
  say "fresh-base: FRESH — $BRANCH_NOW is on $REMOTE/$BRANCH (${HEAD_SHA:0:8})"
  exit 0
fi

say "fresh-base: BEHIND — $BRANCH_NOW is $BEHIND commit(s) behind $REMOTE/$BRANCH (${BASE_SHA:0:8})"
say "fresh-base: a change made from this base lands on code that already moved."
say "fresh-base: repair (never forced):  git -C \"$REPO\" rebase $REMOTE/$BRANCH   # own branch only"
say "fresh-base: or start again:        git -C \"$REPO\" checkout -B <branch> $REMOTE/$BRANCH"
[ "$STRICT" = 1 ] && exit 1
exit 0
