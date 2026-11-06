#!/usr/bin/env bash
# pr-ship-guard.sh — Rule 08, the ship door: the BRANCH is a smith's to push; the PR is not.
#
# WHY (plan 203 §14, 2026-11-06, at the Allfather's question): *"It needs to push the branch,
# otherwise how will the heart be able to get the code and make PR and merge?"* He found a hole
# in §6. A smith that may not push cannot hand anything over at all — so the gate was never
# "pushing", it was "shipping". A smith pushes `eins/<id>` (the transport) and this ward closes
# the door that actually ships: a pull request whose AUTHOR is a smith's identity.
#
# WHAT IT JUDGES: every OPEN pull request in this repository, by author login, against the smith
# registry. A PR authored by a registry identity is a smith that shipped. The branch is fine; the
# PR is not: it is named, and the remedy is the reviewer's door.
#
# WHAT IT DOES NOT JUDGE: the branch, the push, the commit, or the packet's contents. Those have
# their own doors (branch-guard for `main`; the reviewer's sha check for the packet).
#
# IDENTITIES (the first that exists wins):
#   $YMIR_SMITH_IDENTITIES                comma- or space-separated logins
#   $YMIR_HOME/hodd/identity/smiths.txt   one login per line, `#` comments
# No registry, no judgement — it says so out loud (RULES/25: a clean skip names its reason).
#
# Usage:
#   pr-ship-guard.sh check              # judge every open PR (the default)
#   pr-ship-guard.sh --author <login>   # judge one login, no network (tests, hooks)
#   pr-ship-guard.sh --pr <number>      # judge one open PR
#
# Exit: 0 clear (or a clean skip with its reason) · 1 a smith opened a PR · 2 usage.
set -u
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
cd "$ROOT" 2>/dev/null || { printf 'pr-ship-guard: cannot enter %s\n' "$ROOT" >&2; exit 2; }

# The home is RESOLVED, never guessed (defaults-guard): bin/vault/hoard-lib.sh owns
# where it lives, so this ward asks the one resolver instead of restating a path.
if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  for _c in "$ROOT/bin/vault/hoard-lib.sh" "$ROOT/../vault/hoard-lib.sh"; do
    [ -r "$_c" ] && { . "$_c"; YMIR_HOARD_LIB_LOADED=1; break; }
  done
  unset _c
fi
HOME_DIR=""
ymir_home_root HOME_DIR 2>/dev/null || true
[ -n "$HOME_DIR" ] || HOME_DIR="${YMIR_HOME:-}"
REGISTRY="$HOME_DIR/hodd/identity/smiths.txt"
FETCH_TIMEOUT="${YMIR_PR_SHIP_TIMEOUT:-10}"

usage() { sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

skip() {  # <reason>
  printf 'pr-ship-guard[1]{gate,result,note}:\n  "ship door","SKIP","%s"\n' "$1"
  exit 0
}

block() {  # <login> <where>
  cat >&2 <<EOF
⛔ Rule 08 · plan 203 §14: $2 was opened by '$1', a smith's identity.
   a smith pushes a branch and writes a packet; the reviewer ships.
   The branch is fine. The PR is not — close it and let the reviewer open its own,
   from a head sha that matches the packet (a sha that moved is a refusal, §14.1).
   See plan 203 §14.1 and RULES/08-delivery-gate.md
EOF
  printf 'error: pr-ship-guard blocked %s by a smith identity "%s"\n' "$2" "$1" >&2
  printf 'help: the reviewer opens the PR; a smith only pushes its branch\n' >&2
  exit 1
}

# --- the registry -------------------------------------------------------------
# One login per line, blanks and `#` comments ignored. Whitespace inside a line is
# treated as a separator too, so a hand-written "a b" is not a mystery.
identities() {
  if [ -n "${YMIR_SMITH_IDENTITIES:-}" ]; then
    printf '%s\n' ${YMIR_SMITH_IDENTITIES//,/ }
    return 0
  fi
  [ -r "$REGISTRY" ] || return 0
  sed 's/#.*//' "$REGISTRY" | tr -s ' \t' '\n' | sed '/^$/d'
}

is_smith() {  # <login>
  local want="$1" id
  [ -n "$want" ] || return 1
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    [ "$id" = "$want" ] && return 0
  done <<EOF
$(identities)
EOF
  return 1
}

# --- one login, no network -----------------------------------------------------
judge_author() {  # <login>
  local login="$1"
  if [ -z "$(identities)" ]; then
    skip "no smith registry — neither \$YMIR_SMITH_IDENTITIES nor $REGISTRY; nothing to judge"
  fi
  is_smith "$login" && block "$login" "a pull request"
  printf 'pr-ship-guard[1]{gate,result}:\n  "ship door","ok"\n  "author","%s"\n' "$login"
  exit 0
}

# --- open PRs, over the network -----------------------------------------------
judge_prs() {  # [number]
  local one="${1-}" json
  command -v gh >/dev/null 2>&1 || skip "gh is not installed — no PR list to judge (CI keeps the last word)"
  [ -n "$(identities)" ] || skip "no smith registry — neither \$YMIR_SMITH_IDENTITIES nor $REGISTRY; nothing to judge"

  local repo
  repo="$(timeout "$FETCH_TIMEOUT" gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" \
    || skip "gh could not resolve this repository (offline, or no auth) — not judging blind"

  if [ -n "$one" ]; then
    json="$(timeout "$FETCH_TIMEOUT" gh pr view "$one" --json number,author,headRefName,url 2>/dev/null)" \
      || skip "PR #$one could not be read — not judging blind"
    json="[$json]"
  else
    json="$(timeout "$FETCH_TIMEOUT" gh pr list --state open --limit 100 \
              --json number,author,headRefName,url 2>/dev/null)" \
      || skip "gh pr list failed (offline, or no auth) — not judging blind"
  fi

  printf '%s' "$json" | python3 -c '
import json, sys
try:
    prs = json.load(sys.stdin)
except Exception:
    sys.exit(3)
for p in prs:
    print(p.get("number"), (p.get("author") or {}).get("login", ""), (p.get("headRefName") or ""), (p.get("url") or ""))
' > /tmp/.pr-ship-guard.$$ || { rm -f /tmp/.pr-ship-guard.$$; skip "the PR list from gh was not readable JSON — not judging blind"; }

  local n=0 faults=0 login num head url
  while read -r num login head url; do
    [ -n "${num:-}" ] || continue
    n=$((n + 1))
    if is_smith "$login"; then
      faults=$((faults + 1))
      printf 'pr-ship-guard[1]{pr,author,head,url,finding}:\n' >&2
      printf '  "#%s","%s","%s","%s","a smith opened a PR — the reviewer ships"\n' "$num" "$login" "$head" "$url" >&2
    fi
  done < /tmp/.pr-ship-guard.$$
  rm -f /tmp/.pr-ship-guard.$$

  if [ "$faults" -gt 0 ]; then
    cat >&2 <<EOF
⛔ Rule 08 · plan 203 §14: $faults pull request(s) in $repo carry a smith's identity.
   a smith pushes a branch and writes a packet; the reviewer ships.
   Close each one and let the reviewer open its own from the pushed branch.
   See plan 203 §14.1 and RULES/08-delivery-gate.md
EOF
    exit 1
  fi

  printf 'pr-ship-guard[1]{gate,result,open_prs,repo}:\n  "ship door","ok","%s","%s"\n' "$n" "$repo"
  exit 0
}

case "${1:-check}" in
  -h|--help) usage ;;
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  check) judge_prs ;;
  --author) [ -n "${2:-}" ] || usage; judge_author "$2" ;;
  --pr) [ -n "${2:-}" ] || usage; judge_prs "$2" ;;
  *) usage ;;
esac
