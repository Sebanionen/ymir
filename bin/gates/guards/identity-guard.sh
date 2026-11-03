#!/usr/bin/env bash
# identity-guard.sh — a commit that leaves by push must not publish a private mailbox.
#
# WHY (2026-11-03, at the Allfather's word and in his own repository): git records whatever
# `user.email` says, in every commit, forever. Measured on `zerwiz/ymir` — a PUBLIC repository —
# the operator's personal address was the author of **1,236 commits**, and any `git log`, any
# GitHub page, any fork and any script could read it. Nothing in the house watched the ONE place
# every agent writes: the author identity of the commit it makes.
#
# The law it enforces: RULES/04 (no private data in this repository — and an author line IS data
# in the repository) and RULES/39 (never give out the address). A mailbox is not an identifier;
# the identity a commit carries is the account's noreply address, `<id>+<login>@users.noreply.github.com`.
#
# WHAT IT JUDGES: the author and committer addresses of the commits a push ADDS (base..HEAD).
# History is not judged — the commits already published cannot be unmade by a ward, and a gate
# that fails on all existing history is a gate that is switched off.
#
#   identity-guard.sh --staged            # the commit about to be made (author + committer)
#   identity-guard.sh --base origin/main  # the commits a push adds
#   identity-guard.sh --check             # the current branch against its merge base
#
# ALLOWED ADDRESSES (a commit's own identity, never a person's mailbox):
#   *+<login>@users.noreply.github.com     the account's own noreply form (the house default)
#   *@users.noreply.github.com             the older noreply form
#   *@ymir  *@ymir.local  *@zerwiz.org     the house's agent identities (brokk@…, an Eindri's seat)
# Anything else is refused, on purpose and by name.
#
# A refusal can be spoken aloud (`allow-personal-email:` in the commit message, or
# YMIR_ALLOW_PERSONAL_EMAIL="why"), because a genuine exception must be a decision, not a silence.
set -uo pipefail

VERSION="1.0.0"
_root() {
  local d; d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [ "$d" != "/" ]; do
    [ -d "$d/.pi" ] && [ -d "$d/RULES" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
}
ROOT="${YMIR_GUARD_ROOT:-$(_root)}"
cd "$ROOT" 2>/dev/null || { printf 'identity-guard: cannot enter %s\n' "$ROOT" >&2; exit 2; }

mode="--check"; base=""
while [ $# -gt 0 ]; do
  case "$1" in
    -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --staged) mode="--staged"; shift ;;
    --check)  mode="--check"; shift ;;
    --base)   base="${2-}"; mode="--base"; shift 2 || shift ;;
    *) printf 'error: unknown flag %s\nhelp: identity-guard.sh [--staged|--base <ref>|--check]\n' "$1" >&2; exit 2 ;;
  esac
done

allowed() {  # <address> — may this address leave by push?
  case "$1" in
    *@users.noreply.github.com) return 0 ;;
    *@ymir|*@ymir.local|*@zerwiz.org) return 0 ;;
  esac
  return 1
}

case "$mode" in
  --staged)
    addrs="$(git config --get user.email 2>/dev/null || true)
$(git config --get committer.email 2>/dev/null || true)"
    scope="the commit about to be made"
    ;;
  --base)
    [ -n "$base" ] || { printf 'error: --base needs a ref\n' >&2; exit 2; }
    addrs="$(git log --format='%ae%n%ce' "$base"..HEAD 2>/dev/null)"
    scope="the commits this push adds ($base..HEAD)"
    ;;
  *)
    # ON A PULL REQUEST, CHECKOUT IS THE SYNTHETIC MERGE COMMIT, and GitHub authors it with the
    # account that opened the PR — a mailbox that is not in the PR's own commits at all. Judging
    # HEAD would fail every PR for a commit nobody wrote. So judge the PR's OWN side of the merge:
    # `origin/main..HEAD^2` when HEAD is a merge whose first parent is the base.
    # NO MERGE-BASE, NO FETCH: GitHub's merge commit has the base as its FIRST parent and the PR's
    # head as its SECOND, so `HEAD^1..HEAD^2` is exactly the commits the contributor wrote. That
    # works on a shallow checkout, needs no fetched base branch, and cannot accidentally include a
    # commit from the base — which is the whole fault this replaced (the base's own commits carry
    # the mailbox this ward exists to refuse, so including one refused every PR, forever).
    if [ "$(git rev-list --parents -n1 HEAD | awk '{print NF-1}')" -ge 2 ] \
       && git rev-parse -q --verify HEAD^2 >/dev/null 2>&1; then
      addrs="$(git log --format='%ae%n%ce' HEAD^1..HEAD^2 2>/dev/null)"
      scope="this pull request's own commits (HEAD^1..HEAD^2, $(git rev-list --count HEAD^1..HEAD^2 2>/dev/null) commit(s))"
      bad="$(printf '%s\n' "$addrs" | grep -v '^$' | sort -u | while IFS= read -r a; do allowed "$a" || printf '%s\n' "$a"; done)"
      if [ -z "$bad" ]; then
        printf 'identity_guard[1]{scope,verdict}:\n  "%s","PASS — every address is a noreply account or a house identity"\n' "$scope"
        exit 0
      fi
      printf 'identity_guard[2]{scope,refused}:\n  "%s","a private mailbox would enter the public history"\n' "$scope"
      printf '%s\n' "$bad" | sed -E 's/^(.).*@/\1***@/' | sed 's/^/  - (masked) /' >&2
      exit 1
    fi
    b="$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main 2>/dev/null || true)"
    tip="HEAD"
    [ -n "$b" ] || { printf 'identity_guard[1]{state,reason}:\n  "SKIP","no merge base to judge"\n'; exit 0; }
    addrs="$(git log --format='%ae%n%ce' "$b".."$tip" 2>/dev/null)"
    scope="this branch's commits ($(printf '%s' "$b" | cut -c1-8)..$tip)"
    ;;
esac

bad="$(printf '%s\n' "$addrs" | grep -v '^$' | sort -u | while IFS= read -r a; do allowed "$a" || printf '%s\n' "$a"; done)"

if [ -z "$bad" ]; then
  printf 'identity_guard[1]{scope,verdict}:\n  "%s","PASS — every address is a noreply account or a house identity"\n' "$scope"
  exit 0
fi

reason="${YMIR_ALLOW_PERSONAL_EMAIL:-}"
if [ -n "$reason" ]; then
  printf 'identity_guard[2]{scope,verdict}:\n  "%s","ALLOWED — on purpose"\n  "reason","%s"\n' "$scope" "$reason"
  exit 0
fi

printf 'identity_guard[2]{scope,refused}:\n'
printf '  "%s","a private mailbox would enter the public history"\n' "$scope"
printf '%s\n' "$bad" | sed -E 's/^(.).*@/\1***@/' | sed 's/^/  - (masked) /' >&2
cat >&2 <<'MSG'

  A commit's author line is DATA IN THE REPOSITORY, and this repository is public
  (RULES/04, RULES/39). A private mailbox in the author of a commit is published in every
  `git log`, every GitHub page, every fork and every CI log — forever.

  Commit as the ACCOUNT, not a mailbox (the address GitHub mints for you):

      git config --global user.name  "<your login>"
      git config --global user.email "$(gh api user --jq '"\(.id)+\(.login)@users.noreply.github.com"')"

  Then amend the commit you are about to make, so it carries the account:

      git commit --amend --reset-author --no-edit

  A genuine exception is spoken aloud, never silent:

      YMIR_ALLOW_PERSONAL_EMAIL="why, in one line" git push …

  And for an address already published in history: nothing here can unmake it. That is a
  history rewrite and the operator's decision (plan 171).
MSG
exit 1
