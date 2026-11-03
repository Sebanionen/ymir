#!/usr/bin/env bash
# developers.sh — who can write to a repository, and who actually has.
#
# Three questions that disagree, and the disagreement is the information:
#   · a COLLABORATOR may push (GitHub decides)
#   · an AUTHOR has committed (git history decides)
#   · a recorded PERSON is someone the house has decided about (collaborators.yaml decides)
# A name in only one of the three is the case worth looking at.
#
#   bin/records/developers.sh <owner/repo> [<owner/repo> …]
#   DEVELOPERS_CLONES="owner/repo:/path,owner/repo:/path" bin/records/developers.sh owner/repo
#
# Read-only: it asks GitHub, git and the home, and writes nothing.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
home=""; declare -f ymir_home_root >/dev/null 2>&1 && ymir_home_root home 2>/dev/null
home="${home:-${YMIR_HOME:-}}"
people="$home/hodd/identity/collaborators.yaml"

clone_for() {  # <owner/repo> — from DEVELOPERS_CLONES="a/b:/path,c/d:/path"
  local want="$1" pair
  IFS=',' read -r -a pairs <<< "${DEVELOPERS_CLONES:-}"
  for pair in "${pairs[@]}"; do
    [ "${pair%%:*}" = "$want" ] && { printf '%s' "${pair#*:}"; return 0; }
  done
}

[ "$#" -gt 0 ] || { printf 'usage: developers.sh <owner/repo> …\n' >&2; exit 2; }

for repo in "$@"; do
  printf '\n[%s]\n' "$repo"
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    writers="$(gh api "repos/$repo/collaborators" --jq '[.[].login] | join(", ")' 2>/dev/null)"
    pending="$(gh api "repos/$repo/invitations" --jq '[.[] | "\(.invitee.login) (\(.permissions), pending)"] | join(", ")' 2>/dev/null)"
    printf '  writers: %s\n' "${writers:-none readable (or not a repository you own)}"
    printf '  invited: %s\n' "${pending:-none}"
  else
    printf '  writers: gh unavailable or not authenticated — cannot ask GitHub\n'
  fi

  clone="$(clone_for "$repo")"
  if [ -n "${clone:-}" ] && [ -d "$clone" ]; then
    printf '  authors:\n'
    git -C "$clone" log --format='%an <%ae>' 2>/dev/null | sort | uniq -c | sort -rn | head -5 | sed 's/^/    /'
  else
    printf '  authors: no local clone given — set DEVELOPERS_CLONES="%s:/path"\n' "$repo"
  fi
done

if [ -r "$people" ]; then
  printf '\nrecorded people (collaborators.yaml) — the answer to "who is supposed to be here"\n'
  awk '/^- id:/ {id=$3} /github:/ {gsub(/["'\'']/,"",$2); printf "  %-22s %s\n", id, $2}' "$people" | head -20
fi
