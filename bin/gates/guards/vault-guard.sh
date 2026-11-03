#!/usr/bin/env bash
# vault-guard.sh — nothing may copy content OUT of the vault (Rule 15).
#
# Hnitbjörg may hold work under NDA. While it is OPEN this ward hashes every file
# inside the mount and refuses to commit any file — in this tree or the home —
# whose content matches a vault file verbatim. Installed as a pre-commit hook in
# both trees, so git runs it on every commit, including the hasty ones.
#
# The honest limit (Rule 15): a machine can catch a file copied out whole; it cannot
# catch a screenshot, a paraphrase, or a paste into a remote model. Those are the
# operator's and the agent's discipline; this raises the floor.
#
#   vault-guard.sh            # scan the staged change (pre-commit)
#   vault-guard.sh --all      # scan every tracked file
#
# Exit: 0 clean, or the vault is sealed (nothing to leak)
#       1 a file copies the vault verbatim
#       2 usage
set -u
VERSION="1.0.0"

_root() {
  local d; d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [ "$d" != "/" ]; do
    [ -d "$d/.pi" ] && [ -d "$d/RULES" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
}
ROOT="$(_root)"

case "${1-}" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  check|--all|"") ;;
  *) printf 'error: unknown action %s\nhelp: vault-guard.sh [check|--all]\n' "${1-}" >&2; exit 2 ;;
esac

# The vault (Rule 07: env → hoard-lib → the one documented default).
_home=""
[ -r "$ROOT/bin/vault/hoard-lib.sh" ] && . "$ROOT/bin/vault/hoard-lib.sh"
# The platform shim: `sha256sum` is GNU-only, `shasum -a 256` is BSD (RULES/05, 2026-11-02).
[ -r "$ROOT/bin/fleet/ymir-platform.sh" ] || { printf 'vault-guard: the platform shim is missing — %s\n' "$ROOT/bin/fleet/ymir-platform.sh" >&2; exit 2; }
. "$ROOT/bin/fleet/ymir-platform.sh"
command -v ymir_home_root >/dev/null 2>&1 && ymir_home_root _home
[ -n "$_home" ] || _home="${YMIR_HOME:-}"
VAULT_MNT="${YMIR_VAULT_MNT:-$HOME/Vault}"
MAPPER="hnitbjorg"

printf 'vault-guard[3]{finding,file,why}:\n'

# A sealed vault cannot be read by this process, so nothing can have been copied
# out by hash — the ward is clean, and it says so loudly rather than silently.
# Test seam: `YMIR_VAULT_GUARD_SRC=<dir>` stands in for an open vault mount.
SRC="${YMIR_VAULT_GUARD_SRC:-}"
if [ -z "$SRC" ]; then
  if ! cryptsetup status "$MAPPER" >/dev/null 2>&1 || ! mountpoint -q "$VAULT_MNT"; then
    printf '  "none","","the vault is sealed — nothing to copy out"\n'
    exit 0
  fi
  SRC="$VAULT_MNT"
fi
[ -d "$SRC" ] || { printf '  "none","","the vault is sealed — nothing to copy out"\n'; exit 0; }

tmp="$(mktemp)"; trap 'rm -f "${tmp:-}"' EXIT
# Hashes of every vault file (paths are never recorded — only what was hashed).
find "$SRC" -type f -print0 2>/dev/null | while IFS= read -r -d '' f; do
  ymir_sha256 "$f"
done | sort -u > "$tmp"
vault_count="$(wc -l < "$tmp" | tr -d ' ')"
[ "$vault_count" -gt 0 ] || { printf '  "none","","the vault holds no files yet"\n'; exit 0; }

# Candidate files: the staged change (pre-commit) or every tracked file (--all).
git_dir="$(git rev-parse --git-dir 2>/dev/null || true)"
if [ "${1-}" = "--all" ]; then
  files="$(git ls-files 2>/dev/null)"
else
  files="$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null)"
  [ -n "$files" ] || files="$(git ls-files 2>/dev/null)"
fi

found=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || continue
  case "$f" in */Vault/*|*/vault/*.img) continue ;; esac
  h="$(ymir_sha256 "$f" 2>/dev/null)"
  [ -n "$h" ] || continue
  if grep -q "^$h\$" "$tmp"; then
    printf '  "a file copies the vault verbatim","%s","its content is byte-identical to a file inside the vault — Rule 15 forbids it leaving"\n' "$f"
    found=$((found + 1))
  fi
done <<< "$files"

if [ "$found" -eq 0 ]; then
  printf '  "none","","no committed file matches the %s vault file(s)"\n' "$vault_count"
  exit 0
fi
printf 'vault-guard: %s file(s) copy the vault verbatim\nhelp: keep vault content inside the vault — do not commit it, anywhere (Rule 15)\n' "$found" >&2
exit 1
