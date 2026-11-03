#!/usr/bin/env bash
# push.sh — commit and push NAMED paths in the home (never `git add -A`).
#
#   push.sh <message> <path> [path…]
#
# Staging discipline (Rule 04): a scratch file written seconds earlier must never be
# swept in. Refuses to delete a tracked file (Rule 11 — retire by moving).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
hoard="$(bash "$ROOT/bin/vault/hodd.sh" path 2>/dev/null || true)"; [ -n "$hoard" ] || { echo "push: no home" >&2; exit 1; }
HOME_DIR="$(dirname "$hoard")"
msg="${1:-}"; shift || true
[ -n "$msg" ] && [ $# -gt 0 ] || { printf 'usage: push.sh "<message>" <path> [path…]\n' >&2; exit 2; }
( cd "$HOME_DIR" && git add -- "$@" && git commit -q -m "$msg" && git push -q origin main ) || { echo "push: failed (see git)" >&2; exit 1; }
printf 'pushed %s path(s): %s\n' "$#" "$*"
