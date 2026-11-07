#!/usr/bin/env bash
# review-verdict.sh — the judge's ONE act of writing: its verdict, and nothing else.
#
# WHY: the judge is `edit: deny, write: deny` by charter, and that must stay — a reviewer that can
# edit the work it judges is not a reviewer. But a verdict has to be written somewhere, and a
# verdict spoken into a chat is not a record. So the judge writes through this door: one file, one
# shape, the sha it judged, and the ruleset it judged against.
#
# The verdict is what `bin/forge/ship.sh` reads. A verdict whose first line is REFUSE (or
# NEEDS-REWORK) is a refusal with no override; a verdict naming a sha the PR has left is stale and
# the merge door refuses it.
#
# Usage:
#   review-verdict.sh write <pr> --head <sha> --verdict PASS|REFUSE|NEEDS-REWORK \
#       [--repo owner/repo] [--ruleset <id>] --reason "<one line>" [--finding <text> …] [--json]
#   review-verdict.sh show <pr> [--json]
#   review-verdict.sh list
#
# Exit: 0 written · 1 a fault · 2 usage · 3 refused.
set -u
VERSION="1.0.0"

case "${1-}" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help|"") sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"
if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  for _c in "$ROOT/bin/vault/hoard-lib.sh" "$SCRIPT_DIR/../vault/hoard-lib.sh"; do
    [ -r "$_c" ] && { . "$_c"; YMIR_HOARD_LIB_LOADED=1; break; }
  done
  unset _c
fi
STATE=""; hoard_state_dir STATE 2>/dev/null || true
[ -n "$STATE" ] || { printf 'review-verdict: the state dir is unresolved\n' >&2; exit 1; }
REPORTS="$STATE/eindri-reports"

die()    { printf 'review-verdict: %s\n' "$*" >&2; exit 1; }
usage()  { printf 'review-verdict: %s\n' "$*" >&2; exit 2; }
refuse() { printf 'review-verdict: REFUSED — %s\n' "$*" >&2; exit 3; }

ACTION="${1:-}"; shift || true
case "$ACTION" in write|show|list) ;; *) usage "action required: write | show | list" ;; esac

if [ "$ACTION" = "list" ]; then
  mkdir -p "$REPORTS"
  n=0
  printf 'verdicts[3]{pr,head,verdict}:\n'
  for f in "$REPORTS"/pr-*-review.md; do
    [ -r "$f" ] || continue
    pr="$(basename "$f" | sed -n 's/^pr-\([0-9]*\)-review\.md$/\1/p')"
    [ -n "$pr" ] || continue
    head="$(grep -oE '\b[0-9a-f]{40}\b' "$f" | head -1)"
    v="$(head -1 "$f")"
    printf '  "%s","%s","%s"\n' "$pr" "${head:0:12}" "$(printf '%s' "$v" | cut -c1-60)"
    n=$((n + 1))
  done
  [ "$n" -gt 0 ] || printf '  "none","","no verdict has been written"\n'
  exit 0
fi

PR="${1:-}"; shift || true
[ -n "$PR" ] || usage "a PR number is required"
case "$PR" in ''|*[!0-9]*) usage "the PR must be a number" ;; esac
FILE="$REPORTS/pr-$PR-review.md"

if [ "$ACTION" = "show" ]; then
  [ -r "$FILE" ] || refuse "no verdict for PR #$PR at $FILE"
  cat "$FILE"; exit 0
fi

HEAD=""; VERDICT=""; REASON=""; REPO="${YMIR_SHIP_REPO:-zerwiz/ymir}"; RULESET=""; JSON=0
FINDINGS=()
while [ $# -gt 0 ]; do case "$1" in
  --head) HEAD="${2:-}"; shift 2 ;;
  --head=*) HEAD="${1#--head=}"; shift ;;
  --verdict) VERDICT="${2:-}"; shift 2 ;;
  --verdict=*) VERDICT="${1#--verdict=}"; shift ;;
  --reason) REASON="${2:-}"; shift 2 ;;
  --reason=*) REASON="${1#--reason=}"; shift ;;
  --repo) REPO="${2:-}"; shift 2 ;;
  --ruleset) RULESET="${2:-}"; shift 2 ;;
  --finding) FINDINGS+=("${2:-}"); shift 2 ;;
  --json) JSON=1; shift ;;
  *) usage "unknown argument $1" ;;
esac; done

case "$VERDICT" in
  PASS|REFUSE|NEEDS-REWORK) ;;
  "") usage "--verdict is required: PASS | REFUSE | NEEDS-REWORK" ;;
  *) usage "unknown verdict '$VERDICT' — PASS | REFUSE | NEEDS-REWORK" ;;
esac
case "$HEAD" in
  ""|*[!0-9a-f]*) usage "--head must be the full 40-character head sha the verdict judged" ;;
esac
[ "${#HEAD}" = 40 ] || usage "--head must be the FULL sha (40 hex), not an abbreviation — a verdict that cannot name the sha cannot be checked"
[ -n "$REASON" ] || usage "--reason is required: one line, and a refusal names the rule it applies"

# The head must still be the PR's head, or the verdict judges code nobody will merge.
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  now="$(gh pr view "$PR" -R "$REPO" --json headRefOid --jq '.headRefOid' 2>/dev/null || true)"
  if [ -n "$now" ] && [ "$now" != "$HEAD" ]; then
    refuse "PR #$PR is at ${now:0:12} but the verdict names ${HEAD:0:12} — judge the head that will be merged"
  fi
fi

mkdir -p "$REPORTS" || die "cannot create $REPORTS"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
[ -n "$RULESET" ] || RULESET="$(bash "$ROOT/bin/forge/review-rules.sh" "$ROOT" 2>/dev/null | sed -n 's/.*ruleset[^0-9a-f]*\([0-9a-f]\{8,\}\).*/\1/p' | head -1)"

{
  printf '%s — PR #%s\n\n' "$VERDICT" "$PR"
  printf 'pr: %s\nrepo: %s\nhead: %s\nruleset: %s\njudged_by: %s\njudged_at: %s\n\n' \
    "$PR" "$REPO" "$HEAD" "${RULESET:-unrecorded}" "$(hostname -s 2>/dev/null || echo seat)" "$TS"
  printf '## The verdict\n\n%s\n\n' "$REASON"
  if [ "${#FINDINGS[@]}" -gt 0 ]; then
    printf '## Findings\n\n'
    for f in "${FINDINGS[@]}"; do printf -- '- %s\n' "$f"; done
    printf '\n'
  fi
  printf '## CHANGE LOG\n\n- **%s** — written by review-verdict.sh (plan 206); this file is append-only by\n  correction, never by rewrite.\n' "$TS"
} >"$FILE.tmp" && mv "$FILE.tmp" "$FILE" || die "the verdict could not be written at $FILE"

if [ "$JSON" = 1 ]; then
  printf '{"pr":%s,"head":"%s","verdict":"%s","file":"%s"}\n' "$PR" "$HEAD" "$VERDICT" "$FILE"
else
  printf 'verdict[4]{pr,head,verdict,file}:\n  "%s","%s","%s","%s"\n' "$PR" "${HEAD:0:12}" "$VERDICT" "$FILE"
fi
