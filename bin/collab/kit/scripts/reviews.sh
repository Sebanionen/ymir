#!/usr/bin/env bash
# reviews.sh — a review is a file in the repository, so the next hand gets it without asking anyone.
#
#   bash scripts/reviews.sh new --pr=19 --title="the guided journey"   # a review note to fill in
#   bash scripts/reviews.sh list                                       # every review, newest first
#   bash scripts/reviews.sh newest                                     # the one the baton must point at
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT/docs/audit"
usage() { sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; }
slugify() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed 's/--*/-/g; s/^-//; s/-$//' | cut -c1-50; }

action="${1:-}"; shift || true
case "$action" in
  -h|--help|"") usage; exit 0 ;;
  new)
    pr=""; title=""
    for a in "$@"; do case "$a" in --pr=*) pr="${a#*=}" ;; --title=*) title="${a#*=}" ;; esac; done
    [ -n "$pr" ] && [ -n "$title" ] || { echo "new needs --pr=<number> and --title=\"…\"" >&2; exit 2; }
    path="$DIR/$(date +%Y-%m-%d)-review-of-pr$pr.md"
    [ -e "$path" ] && { echo "a review of #$pr already exists: $path" >&2; exit 1; }
    mkdir -p "$DIR"
    cat > "$path" <<TEMPLATE
# Review — PR #$pr, $title

**Reviewer:** (name) · **Date:** $(date +%Y-%m-%d) · **Branch:** (head → base)

## What the evidence says

Run it before writing a judgement. Record the command and what it printed.

\`\`\`
verified[4]{check,result,note}:
  "typecheck","",""
  "npm run check","",""
  "npm test","",""
  "the page","",""
\`\`\`

## What is good

Say it plainly, and why it is good — a review that only lists faults teaches nothing.

## What must change before it merges

\`\`\`
fixes[3]{issue,why,what_to_do}:
  "","",""
\`\`\`

## The next tasks, smallest first

\`\`\`
next[4]{task,why_this_order,size}:
  "1","",""
  "2","",""
  "3","",""
  "4","",""
\`\`\`
TEMPLATE
    echo "created $path";;
  list)
    ls -1 "$DIR"/*.md 2>/dev/null | sort -r | while IFS= read -r f; do
      printf '  "%s","%s"\n' "$(basename "$f")" "$(sed -n '1s/^# Review — //p' "$f" | cut -c1-70)"
    done;;
  newest)
    ls -1 "$DIR"/*.md 2>/dev/null | sort -r | head -1;;
  *) usage; exit 2;;
esac
