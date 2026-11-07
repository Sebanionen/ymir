#!/usr/bin/env bash
# plan.sh — the plan ledger: create the NEXT numbered plan and its index row.
#
#   plan.sh new <slug> --title "<title>" [--realm R] [--project P]
#   plan.sh list                      # the ledger's rows (number · title · status)
#   plan.sh next                      # the number the next plan would take (read-only)
#
# THE LEDGER (the house law): svartalfaheim/<realm>/projects/<project>/plans/ in the HOME.
# Numbering is after the index's highest; a number is never reused. Extracted from the Pi
# extension so every harness reaches it (the extension header's own law: behaviour in bin/).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
hoard="$(bash "$ROOT/bin/vault/hodd.sh" path 2>/dev/null || true)"
[ -n "$hoard" ] || { printf 'plan: no home (bin/vault/hodd.sh path answered nothing)\n' >&2; exit 1; }
HOME_DIR="$(dirname "$hoard")"
REALM="${YMIR_REALM:-work}"; PROJECT="${YMIR_PROJECT:-ymir}"
LEDGER="$HOME_DIR/svartalfaheim/$REALM/projects/$PROJECT/plans"
[ -d "$LEDGER" ] || LEDGER="$HOME_DIR/svartalfaheim/$REALM/workspace/$PROJECT/plans"
# the ledger is found, never guessed: the project may live under any realm (work, a house realm)
[ -d "$LEDGER" ] || LEDGER="$(find "$HOME_DIR/svartalfaheim" -maxdepth 4 -type d -path "*/projects/$PROJECT/plans" 2>/dev/null | head -1)"
[ -d "$LEDGER" ] || LEDGER="$(find "$HOME_DIR/svartalfaheim" -maxdepth 4 -type d -path "*/workspace/$PROJECT/plans" 2>/dev/null | head -1)"
[ -d "$LEDGER" ] || { printf 'plan: no ledger for %s/%s (looked in projects/ and workspace/)\n' "$REALM" "$PROJECT" >&2; exit 1; }

# ── Rule 45 — a number is taken from the CURRENT ledger, never from a stale one ──
# WHY (2026-11-04): this seat sat seven commits behind origin, asked for the next
# number, and was told 182. The plan was written — but another machine had taken 182
# the same day, so two plans shared a number and one had to be renumbered. Numbering
# is a DISTRIBUTED allocation: the ledger is git, and an allocation without a fetch
# is a guess dressed as a fact.
ledger_state() {   # fresh | behind:<n> | unverified:<why>
  local repo br behind
  command -v git >/dev/null 2>&1 || { printf 'unverified:no git on PATH'; return 0; }
  repo="$(git -C "$LEDGER" rev-parse --show-toplevel 2>/dev/null)" || { printf 'unverified:the home is not a git repository'; return 0; }
  [ "${YMIR_OFFLINE:-0}" = "1" ] && { printf 'unverified:YMIR_OFFLINE=1'; return 0; }
  git -C "$repo" fetch --quiet --prune origin 2>/dev/null || { printf 'unverified:origin is unreachable'; return 0; }
  br="$(git -C "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
  br="${br:-main}"
  git -C "$repo" rev-parse --verify -q "origin/$br" >/dev/null 2>&1 || { printf 'unverified:origin/%s is missing' "$br"; return 0; }
  behind="$(git -C "$repo" rev-list --count "HEAD..origin/$br" 2>/dev/null || printf 0)"
  if [ "${behind:-0}" = "0" ]; then printf 'fresh'; else printf 'behind:%s' "$behind"; fi
}

# READING a number is harmless; TAKING one is not. Only `new` calls this.
refuse_stale_ledger() {
  local s repo; s="$(ledger_state)"
  case "$s" in
    fresh) : ;;
    behind:*)
      if [ "${YMIR_ALLOW_STALE_LEDGER:-0}" = "1" ]; then
        printf 'plan: WARNING — the ledger is %s commit(s) behind origin and a number was taken anyway (YMIR_ALLOW_STALE_LEDGER=1)\n' "${s#behind:}" >&2
      else
        repo="$(git -C "$LEDGER" rev-parse --show-toplevel 2>/dev/null)"
        printf 'plan: REFUSED — the ledger is %s commit(s) behind origin, so the next number is not this seat to take.\n' "${s#behind:}"
        printf 'plan: it may already belong to a plan written elsewhere (that is how 182 was written twice, 2026-11-04).\n'
        printf 'plan: run  git -C "%s" pull --ff-only  then ask again; the ledger is %s\n' "$repo" "$LEDGER"
        printf 'plan: loud override when you know better:  YMIR_ALLOW_STALE_LEDGER=1\n'
        return 1
      fi ;;
    unverified:*)
      printf 'plan: note — the ledger is UNVERIFIED against origin (%s): a number taken now may already be taken elsewhere.\n' "${s#unverified:}" >&2 ;;
  esac
  return 0
}

next_number() { ls "$LEDGER" 2>/dev/null | grep -oE '^[0-9]+' | sort -n | tail -1 | awk '{print ($1+1)}' ; }

case "${1:-}" in
  -h|--help|"") sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  next) n="$(next_number)"; printf '%s\n' "${n:-1}" ;;
  list) grep -hE '^\| [0-9]+ \|' "$LEDGER/README.md" 2>/dev/null | sed -E 's/^\| ([0-9]+) \| \[([^]]*)\].*/#\1 \2/' | tail -20 ;;
  new)
    slug="${2:-}"; shift 2 2>/dev/null || true
    title=""; while [ $# -gt 0 ]; do case "$1" in --title) title="$2"; shift 2 ;; --realm) REALM="$2"; shift 2 ;; --project) PROJECT="$2"; shift 2 ;; *) shift ;; esac; done
    [ -n "$slug" ] && [ -n "$title" ] || { printf 'plan: new needs <slug> and --title\n' >&2; exit 2; }
    refuse_stale_ledger || exit 1
    n="$(next_number)"; n="${n:-1}"; f="$LEDGER/${n}-${slug}.md"
    [ -e "$f" ] && { printf 'plan: %s exists\n' "$f" >&2; exit 1; }
    printf '# Plan %s - %s\n\n**Opened %s.**\n' "$n" "$title" "$(date +%F)" > "$f"
    printf '| %s | [%s](%s) | opened |\n' "$n" "$title" "$(basename "$f")" >> "$LEDGER/README.md"
    printf 'created %s\n' "$f" ;;
  *) printf 'error: unknown action %s\nhelp: plan.sh [new <slug> --title <t> | list | next]\n' "$1" >&2; exit 2 ;;
esac
