#!/usr/bin/env bash
# plan.sh — the plan ledger: create the NEXT numbered plan and its index row.
#
#   plan.sh new <slug> --title "<title>" [--realm R] [--project P]
#   plan.sh list                      # the ledger's rows (number · title · status)
#   plan.sh next                      # the number the next plan will take
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

next_number() { ls "$LEDGER" 2>/dev/null | grep -oE '^[0-9]+' | sort -n | tail -1 | awk '{print ($1+1)}' ; }

case "${1:-}" in
  -h|--help|"") sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  next) n="$(next_number)"; printf '%s\n' "${n:-1}" ;;
  list) grep -hE '^\| [0-9]+ \|' "$LEDGER/README.md" 2>/dev/null | sed -E 's/^\| ([0-9]+) \| \[([^]]*)\].*/#\1 \2/' | tail -20 ;;
  new)
    slug="${2:-}"; shift 2 2>/dev/null || true
    title=""; while [ $# -gt 0 ]; do case "$1" in --title) title="$2"; shift 2 ;; --realm) REALM="$2"; shift 2 ;; --project) PROJECT="$2"; shift 2 ;; *) shift ;; esac; done
    [ -n "$slug" ] && [ -n "$title" ] || { printf 'plan: new needs <slug> and --title\n' >&2; exit 2; }
    n="$(next_number)"; n="${n:-1}"; f="$LEDGER/${n}-${slug}.md"
    [ -e "$f" ] && { printf 'plan: %s exists\n' "$f" >&2; exit 1; }
    printf '# Plan %s - %s\n\n**Opened %s.**\n' "$n" "$title" "$(date +%F)" > "$f"
    printf '| %s | [%s](%s) | opened |\n' "$n" "$title" "$(basename "$f")" >> "$LEDGER/README.md"
    printf 'created %s\n' "$f" ;;
  *) printf 'error: unknown action %s\nhelp: plan.sh [new <slug> --title <t> | list | next]\n' "$1" >&2; exit 2 ;;
esac
