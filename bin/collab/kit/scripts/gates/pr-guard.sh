#!/usr/bin/env bash
# pr-guard — a branch that exists on the remote must have a pull request.
#
# Called from pre-push with the refs git is about to send. The first push of a branch is allowed (that is how a
# pull request gets something to point at); every push after it must be covered by an open pull request, or the
# work is invisible to review and the rule "all code comes as a PR" is a wish.
#
#   bash scripts/gates/pr-guard.sh <remote> <local-ref> <local-sha> <remote-ref> <remote-sha>
set -uo pipefail
remote="${1:-origin}"; local_ref="${2:-}"; remote_ref="${3:-}"; remote_sha="${4:-}"
[ -n "$remote_ref" ] || exit 0
branch="${remote_ref#refs/heads/}"
[ "$branch" = "$remote_ref" ] && exit 0        # not a branch

# a brand-new branch has nothing to review yet: allow it, and say what to do next
if [ -z "$remote_sha" ] || [ "$remote_sha" = "0000000000000000000000000000000000000000" ]; then
  printf 'pr-guard: new branch %s — after the push, open the pull request:\n  gh pr create --base <main> --head %s\n' "$branch" "$branch" >&2
  exit 0
fi

command -v gh >/dev/null 2>&1 || { printf 'pr-guard: gh is not installed — cannot check for a pull request; allowing\n' >&2; exit 0; }
if ! gh auth status >/dev/null 2>&1; then printf 'pr-guard: gh is not authenticated — allowing\n' >&2; exit 0; fi

existing="$(gh pr list --head "$branch" --state all --json number,state --jq '.[0].state // ""' 2>/dev/null)"
case "$existing" in
  OPEN)   printf 'pr-guard: %s has an open pull request\n' "$branch" >&2; exit 0 ;;
  MERGED|CLOSED)
    printf 'pr-guard: %s has a %s pull request — a new branch needs its own PR\n' "$branch" "$existing" >&2 ;;
  *)
    printf 'pr-guard refused: %s exists on %s and has no pull request.\n' "$branch" "$remote" >&2
    printf '  open one first:  gh pr create --base <main> --head %s\n' "$branch" >&2
    printf '  (a branch that only exists to be pushed is a branch nobody reviews — RULES/15)\n' >&2
    exit 1 ;;
esac
