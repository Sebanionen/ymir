#!/usr/bin/env bash
# worktree.sh — one agent, one worktree. Two hands never edit the same tree.
#
# The house runs Yggdrasil worktrees (`bin/forge/yggdrasil.sh` in the platform): every task gets its own
# `.yggdrasil/<id>/` checkout so parallel agents cannot collide on a file, a build or a lock. This is the same
# discipline for this repository, using git's own mechanism and nothing else.
#
#   bash scripts/worktree.sh new <agent-id> [base]   # create .yggdrasil/<id> on branch <prefix>/<id>
#   bash scripts/worktree.sh list                    # what exists, and which branch each is on
#   bash scripts/worktree.sh done <agent-id>         # remove it once its pull request is merged
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${WT_PREFIX:-agent}"
WT=".yggdrasil"

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; }
cmd="${1:-}"; shift || true

case "$cmd" in
  new)
    id="${1:-}"; base="${2:-}"
    [ -n "$id" ] || { echo "new needs an agent id" >&2; exit 2; }
    case "$id" in *[!A-Za-z0-9._-]*) echo "unsafe id: $id" >&2; exit 2 ;; esac
    [ -z "$base" ] && base="$(git -C "$ROOT" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
    [ -n "$base" ] || base="$(git -C "$ROOT" branch --show-current)"
    path="$ROOT/$WT/$id"
    [ -e "$path" ] && { echo "already exists: $path" >&2; exit 1; }
    mkdir -p "$ROOT/$WT"
    git -C "$ROOT" worktree add -b "$PREFIX/$id" "$path" "${base:-master}" >/dev/null || { echo "worktree add failed (base ${base})" >&2; exit 1; }
    # the same two exclusions the house uses: a worktree does not need a second copy of dependencies or a build
    if [ -d "$ROOT/node_modules" ] && [ ! -e "$path/node_modules" ]; then ln -s "$ROOT/node_modules" "$path/node_modules"; fi
    [ -d "$ROOT/backend/node_modules" ] && [ ! -e "$path/backend/node_modules" ] && ln -s "$ROOT/backend/node_modules" "$path/backend/node_modules"
    printf 'worktree\t%s\t%s\n' "$PREFIX/$id" "$path"
    printf 'next: cd %s && npm run check\n' "$path" ;;
  list)
    git -C "$ROOT" worktree list | sed 's/^/  /' ;;
  done)
    id="${1:-}"; [ -n "$id" ] || { echo "done needs an agent id" >&2; exit 2; }
    git -C "$ROOT" worktree remove --force "$ROOT/$WT/$id" 2>/dev/null || true
    git -C "$ROOT" branch -D "$PREFIX/$id" 2>/dev/null || true
    printf 'removed\t%s\n' "$WT/$id" ;;
  -h|--help|"") usage ;;
  *) usage; exit 2 ;;
esac
