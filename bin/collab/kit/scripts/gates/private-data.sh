#!/usr/bin/env bash
# private-data — the repository is public; the operator's machine is not.
#
# Blocks the shapes that leak a house rather than a secret: absolute paths into somebody's home, the private vault's
# directory, and real email addresses outside the fixtures and the documentation examples.
#
#   bash scripts/gates/private-data.sh          # staged changes
#   bash scripts/gates/private-data.sh --all    # every tracked file
set -uo pipefail

files="$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null)"
[ "${1:-}" = "--all" ] && files="$(git ls-files)"
[ -n "$files" ] || exit 0

# paths that belong to one machine; emails that belong to real people
path_pattern='/home/[a-z]+/|/Users/[A-Za-z]+/|Documents/ymirhome'   # allow-home-default: the pattern NAMES a home path in order to refuse one; it never resolves one
mail_pattern='[A-Za-z0-9._%+-]+@(gmail|hotmail|live|outlook|yahoo|icloud)\.[a-z]{2,}'

found=0
while IFS= read -r file; do
  [ -f "$file" ] || continue
  case "$file" in
    # documentation may describe an example; the fixtures and the tests are where fake addresses live by design
    docs/*|*.md|*test*|*fixture*|package-lock.json) continue ;;
    scripts/gates/*) continue ;;
  esac
  # `%h/Documents/ymirhome` and `$HOME/Documents/ymirhome` are home-relative, which the rule allows; only a
  # literal machine path is a leak. Appended 2026-11-06: the gate cried wolf on a systemd unit that used `%h`.
  hits="$(grep -nEI "$path_pattern|$mail_pattern" "$file" 2>/dev/null | grep -vE '(%h|\$\{?HOME\}?)/Documents/ymirhome' | cut -c1-120)"   # allow-home-default: the pattern NAMES the home in order to allow its relative form and refuse the machine one; it never resolves a path
  if [ -n "$hits" ]; then
    printf 'private-data: %s\n%s\n\n' "$file" "$hits" >&2
    found=1
  fi
done <<< "$files"

if [ "$found" = 1 ]; then
  printf 'private-data refused: a machine path or a real address is in the change.\n  Private data lives in the private home of this house; this repository is public.\n' >&2
  exit 1
fi
printf 'private-data: clean\n'
