#!/usr/bin/env bash
# secret-scan — a credential must never enter this repository, and a hook is cheaper than a history rewrite.
#
# Scans the staged diff (or the whole tree with --all) for the shapes a secret takes: a private key, a bearer token, an
# API key assignment with a real-looking value, a refresh token, and a database URL whose password is LITERAL —
# `postgres://user:${VAR}@host` is a reference, not a secret, and flagging it teaches people to ignore the gate.
#
#   bash scripts/gates/secret-scan.sh            # staged changes, for pre-commit
#   bash scripts/gates/secret-scan.sh --all      # every tracked file
set -uo pipefail

files="$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null)"
[ "${1:-}" = "--all" ] && files="$(git ls-files)"

[ -n "$files" ] || exit 0

pattern='(BEGIN (RSA|OPENSSH|EC|PGP) PRIVATE KEY|GOCSPX-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{30,}|xoxb-[A-Za-z0-9-]{20,}|AIza[A-Za-z0-9_-]{30,}|postgres(ql)?://[^:@/ ]+:[^$@/ ][^@/ ]*@|"?(api[_-]?key|secret|token|password|refresh_token)"?\s*[:=]\s*"[A-Za-z0-9_./+-]{24,}")'

found=0
while IFS= read -r file; do
  [ -f "$file" ] || continue
  case "$file" in
    *.png|*.jpg|*.jpeg|*.webp|*.gif|*.pdf|*.ico|*.woff|*.woff2|package-lock.json|pnpm-lock.yaml) continue ;;
  esac
  hits="$(grep -nEI "$pattern" "$file" 2>/dev/null | cut -c1-120)"
  if [ -n "$hits" ]; then
    printf 'secret-scan: %s\n%s\n\n' "$file" "$hits" >&2
    found=1
  fi
done <<< "$files"

if [ "$found" = 1 ]; then
  printf 'secret-scan refused: a credential is in the change.\n  A secret is referenced by path, never stored — see RULES/08.\n  If this is a test fixture, make it obviously fake (example.invalid, sk-test-0000).\n' >&2
  exit 1
fi
printf 'secret-scan: clean (%s file(s))\n' "$(printf '%s\n' "$files" | grep -c . || true)"
