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
#   bin/records/developers.sh whoami                     # whose ACCOUNT this machine commits as
#   DEVELOPERS_CLONES="owner/repo:/path,owner/repo:/path" bin/records/developers.sh owner/repo
#
# A PERSON IS A GITHUB ACCOUNT, NOT A MAILBOX. Measured 2026-11-03: the public history carried the
# operator's personal address in 1,236 commits, because git records whatever `user.email` says and
# nothing in the house watched it. So an author is shown as their LOGIN, derived from the account's
# noreply address (`<id>+<login>@users.noreply.github.com`), and an address is printed ONLY when
# asked for with --emails — a register that lists mailboxes on request is not a register that
# publishes them.
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

[ "$#" -gt 0 ] || { printf 'usage: developers.sh <owner/repo> … | whoami\n' >&2; exit 2; }

# ── whoami: the ACCOUNT this machine commits as, and whether the two agree ───
if [ "${1-}" = "whoami" ]; then
  if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
    printf 'whoami[1]{account,state}:\n  "github","no authenticated account (gh auth login)"\n'
    exit 1
  fi
  account="$(gh api user --jq '.login' 2>/dev/null)"
  uid="$(gh api user --jq '.id' 2>/dev/null)"
  name="$(gh api user --jq '.name // ""' 2>/dev/null)"
  noreply="${uid}+${account}@users.noreply.github.com"
  configured="$(git -C "$ROOT" config --get user.email 2>/dev/null || true)"
  verdict="agrees"
  case "$configured" in
    "$noreply"|*@users.noreply.github.com) : ;;
    "") verdict="unset — commits would use the machine default" ;;
    *) verdict="DIFFERS — a commit here would publish a personal address; set: git config --global user.email $noreply" ;;
  esac
  printf 'whoami[5]{key,value}:\n'
  printf '  "account","%s"\n' "$account"
  printf '  "name","%s"\n' "$name"
  printf '  "commits_as","%s"\n' "$noreply"
  printf '  "this_checkout","%s"\n' "${configured:-unset}"
  printf '  "verdict","%s"\n' "$verdict"
  exit 0
fi

EMAILS=0
for a in "$@"; do case "$a" in --emails) EMAILS=1 ;; esac; done

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
    printf '  authors (by commit count):\n'
    # A LOGIN, from the noreply form GitHub mints for every account. An author whose address is a
    # personal mailbox is shown MASKED — the row exists to identify a person, not to republish the
    # address they happen to commit with.
    git -C "$clone" log --format='%ae' 2>/dev/null | sort | uniq -c | sort -rn | head -5 |
    while read -r n addr; do
      [ -n "$addr" ] || continue
      case "$addr" in
        *+*@users.noreply.github.com) who="${addr%%@*}"; who="${who#*+}" ;;
        *@users.noreply.github.com)   who="(noreply, unnamed login)" ;;
        # The HOUSE's own addresses are not personal data: they are agent identities, and the
        # register exists to show them. Everything else is somebody's mailbox and is masked.
        *@ymir|*@ymir.local|*@zerwiz.org) who="$addr (house identity)" ;;
        *) if [ "${EMAILS:-0}" = 1 ]; then who="$addr"
           else who="$(printf '%s' "$addr" | sed -E 's/^(.).*@/\1***@/') (a personal address — pass --emails to see it)" ; fi ;;
      esac
      printf '    %5s  %s\n' "$n" "$who"
    done
  else
    printf '  authors: no local clone given — set DEVELOPERS_CLONES="%s:/path"\n' "$repo"
  fi
done

if [ -r "$people" ]; then
  printf '\nrecorded people (collaborators.yaml) — the answer to "who is supposed to be here"\n'
  awk '/^- id:/ {id=$3} /github:/ {gsub(/["'\'']/,"",$2); printf "  %-22s %s\n", id, $2}' "$people" | head -20
fi
