#!/usr/bin/env bash
# pr-check — is every commit that exists proposed for review?
#
#   bash scripts/pr-check.sh            # commits ahead of the base branch, and whether an open PR covers them
#   bash scripts/pr-check.sh --quiet    # exit code only (1 = something is unproposed)
#
# A git hook can stop a push; only this can tell you that a branch is sitting ahead of main with no pull request, which is
# the fault that let this product run unreviewed code for two days (RULES/15).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
base="${PR_BASE:-$(git -C "$ROOT" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')}"
base="${base:-main}"
quiet=0; [ "${1:-}" = "--quiet" ] && quiet=1

ahead="$(git -C "$ROOT" log --oneline "origin/$base..HEAD" 2>/dev/null | wc -l | tr -d ' ')"
branch="$(git -C "$ROOT" branch --show-current)"
pr="$(gh pr list --head "$branch" --state open --json number --jq '.[0].number // ""' 2>/dev/null || true)"

[ "$quiet" = 1 ] || printf 'pr-check[1]{branch,ahead_of_%s,open_pr}:\n  "%s","%s","%s"\n' "$base" "$branch" "$ahead" "${pr:-none}"

if [ "${ahead:-0}" -gt 0 ] && [ -z "${pr:-}" ]; then
  [ "$quiet" = 1 ] || printf '\n  %s commit(s) on %s are not proposed for review.\n  open a pull request:  gh pr create --base %s --head %s\n' "$ahead" "$branch" "$base" "$branch" >&2
  exit 1
fi
[ "$quiet" = 1 ] || printf '  PASS — every commit ahead of %s is covered by a pull request\n' "$base"
