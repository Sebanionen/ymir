#!/usr/bin/env bash
# push.sh — commit and push NAMED paths in the home (never `git add -A`).
#
#   push.sh "<message>" <path> [path…]
#   push.sh --dry-run "<message>" <path> [path…]   # say what WOULD be staged; commit nothing
#
# Staging discipline (Rule 04): a scratch file written seconds earlier must never be
# swept in. Refuses to delete a tracked file (Rule 11 — retire by moving).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
hoard="$(bash "$ROOT/bin/vault/hodd.sh" path 2>/dev/null || true)"; [ -n "$hoard" ] || { echo "push: no home" >&2; exit 1; }
HOME_DIR="$(dirname "$hoard")"
dry=0; case "${1:-}" in --dry-run) dry=1; shift ;; esac
msg="${1:-}"; shift || true
[ -n "$msg" ] && [ $# -gt 0 ] || { printf 'usage: push.sh [--dry-run] "<message>" <path> [path…]\n' >&2; exit 2; }

# Rule 11: a retired document is MOVED, never deleted — and a deletion is visible in the
# worktree before anything is staged, so it is refused here rather than discovered later.
gone="$(git -C "$HOME_DIR" diff --name-only --diff-filter=D -- "$@" 2>/dev/null)"
[ -z "$gone" ] || { printf 'push: refused — a tracked file is deleted among the named paths:\n%s\nRule 11: retire it by MOVING it (hodd/reference/), never by deleting it.\n' "$gone" >&2; exit 1; }

if [ "$dry" = 1 ]; then
  printf 'dry run — nothing staged, nothing committed, nothing pushed.\n  home: %s\n  message: %s\n  paths:\n' "$HOME_DIR" "$msg"
  printf '    %s\n' "$@"
  printf '  what git would stage:\n'
  git -C "$HOME_DIR" status --porcelain -- "$@" 2>/dev/null | sed 's/^/    /' || true
  exit 0
fi

cd "$HOME_DIR" || { echo "push: no home at $HOME_DIR" >&2; exit 1; }
git add -- "$@" || { echo "push: staging failed (see git)" >&2; exit 1; }
if git diff --cached --quiet; then
  printf 'nothing to push: the named paths are unchanged\n'
  exit 0
fi
git commit -q -m "$msg" || { echo "push: commit failed (see git)" >&2; exit 1; }
git push -q origin main || { echo "push: committed, but the push failed (see git)" >&2; exit 1; }
printf 'pushed %s path(s): %s\n' "$#" "$*"
