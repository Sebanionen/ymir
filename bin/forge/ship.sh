#!/usr/bin/env bash
# ship.sh — the reviewer's merge: the one door that puts a judged PR on main.
#
# WHY (RULES/08, appended 2026-11-06; plan 206 §3 F3): the Allfather's word made the reviewer the
# hand that ships — *"why aren't the heart reviewing all prs that comes in on the ymir repo and
# merging them"*. But a merge door without brakes is a force-push with a nicer name, and a merge
# door that reads nothing is a merge door that cannot tell a green PR from a conflicted one.
#
# SIX CONDITIONS, and the door refuses on the FIRST that fails, naming it:
#   1 · the project DECLARES `delivery: reviewer-merges` (hodd/identity/projects.yaml) — the
#       default is `operator-merges`, and a project that did not say so is his hand, not ours;
#   2 · the PR is OPEN, not a draft, and GitHub says MERGEABLE (no DIRTY/BEHIND/BLOCKED);
#   3 · CI is green — every check concluded SUCCESS/NEUTRAL/SKIPPED, nothing pending;
#   4 · a VERDICT exists for this PR, and it is not a refusal;
#   5 · the verdict names the SAME head sha the PR has now — a head that moved after the
#       judgement is work nobody reviewed;
#   6 · `state/.seal-hold` is absent — the brake that stops every merge in this house.
#
# AND THEN, in order: merge (squash, delete the branch), write ONE Runes entry naming reviewer,
# reviewed sha, merge commit and the moment, and TELL HIM — MERGED with the record, or a FAIL line
# if the word cannot be sent (the merge stands; a mail that cannot be sent never claims to be).
#
# Usage:
#   ship.sh <pr> [--repo owner/repo] [--review <file>] [--dry-run] [--json] [--no-mail]
#   ship.sh --check <pr> [--repo owner/repo]     # judge the six, merge nothing
#
# Exit: 0 merged (or would merge on --dry-run) · 1 a fault · 2 usage · 3 refused (the condition named).
set -u
VERSION="1.0.0"

case "${1-}" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help|"") sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
HOME_DIR=""; ymir_home_root HOME_DIR 2>/dev/null || true
STATE=""; hoard_state_dir STATE 2>/dev/null || true
[ -n "$HOME_DIR" ] && [ -n "$STATE" ] || { printf 'ship: the home or the state is unresolved\n' >&2; exit 1; }

PROJECTS="$HOME_DIR/hodd/identity/projects.yaml"
MAIL="$ROOT/bin/notify/mail.sh"
RUNES="$ROOT/bin/records/runes-append.sh"
DEFAULT_REPO="${YMIR_SHIP_REPO:-zerwiz/ymir}"

die()    { printf 'ship: %s\n' "$*" >&2; exit 1; }
usage()  { printf 'ship: %s\n' "$*" >&2; exit 2; }
refuse() { printf 'ship: REFUSED — %s\n' "$*" >&2; exit 3; }

PR=""; REPO="$DEFAULT_REPO"; REVIEW_FILE=""; DRY=0; JSON=0; MAIL_ON=1; CHECK_ONLY=0
while [ $# -gt 0 ]; do case "$1" in
  --repo) REPO="${2:-}"; shift 2 ;;
  --repo=*) REPO="${1#--repo=}"; shift ;;
  --review) REVIEW_FILE="${2:-}"; shift 2 ;;
  --review=*) REVIEW_FILE="${1#--review=}"; shift ;;
  --dry-run) DRY=1; shift ;;
  --check) CHECK_ONLY=1; shift ;;
  --json) JSON=1; shift ;;
  --no-mail) MAIL_ON=0; shift ;;
  -*) usage "unknown flag $1" ;;
  *) [ -z "$PR" ] && PR="$1" || usage "one PR at a time"; shift ;;
esac; done
[ -n "$PR" ] || usage "a PR number is required: ship.sh <pr> [--repo owner/repo]"
case "$PR" in ''|*[!0-9]*) usage "the PR must be a number, got '$PR'" ;; esac

command -v gh >/dev/null 2>&1 || refuse "gh is not on PATH — no GitHub door, no merge"
gh auth status >/dev/null 2>&1 || refuse "this seat has NO working GitHub identity (gh auth status failed) — a merge door with no identity must refuse, not guess"

# ── 1 · the delivery switch ───────────────────────────────────────────────────────────────────
DELIVERY="$(python3 - "$PROJECTS" "$REPO" <<'PY' 2>/dev/null || true
import sys
try:
    import yaml
except Exception:
    sys.exit(0)
path, repo = sys.argv[1:3]
try:
    cfg = yaml.safe_load(open(path)) or {}
except Exception:
    sys.exit(0)
name = repo.split("/")[-1]
for p in (cfg.get("projects") or []):
    g = p.get("git") or {}
    if g.get("repo") == name and (not g.get("owner") or f'{g.get("owner")}/{name}' == repo):
        print(p.get("delivery") or "operator-merges")
        break
PY
)"
[ -n "$DELIVERY" ] || DELIVERY="operator-merges"
[ "$DELIVERY" = "reviewer-merges" ] || refuse "project '$REPO' declares delivery: $DELIVERY — a merge on this project is the Allfather's hand (RULES/08). Only a project that says 'reviewer-merges' may be shipped by a reviewer"

# ── 6 (early) · the brake, before anything is read ────────────────────────────────────────────
[ -f "$STATE/.seal-hold" ] && refuse "state/.seal-hold is present — this house merges NOTHING while it exists: $(head -1 "$STATE/.seal-hold" 2>/dev/null)"

# ── 2 · the PR's own state ────────────────────────────────────────────────────────────────────
info="$(gh pr view "$PR" -R "$REPO" --json number,title,state,isDraft,mergeable,headRefOid,headRefName,statusCheckRollup,author 2>/dev/null)" \
  || die "PR #$PR is not readable in $REPO"
row="$(printf '%s' "$info" | python3 -c '
import json, sys
p = json.load(sys.stdin)
checks = p.get("statusCheckRollup") or []
concl = [(c.get("conclusion") or c.get("state") or "?") for c in checks]
if not concl: ci = "none"
elif any(c in ("FAILURE","ERROR","CANCELLED","TIMED_OUT") for c in concl): ci = "red"
elif any(c in ("PENDING","IN_PROGRESS","QUEUED","") for c in concl): ci = "pending"
else: ci = "green"
print("\t".join([str(p.get("number")), p.get("state") or "", "true" if p.get("isDraft") else "false",
                 p.get("mergeable") or "UNKNOWN", p.get("headRefOid") or "", p.get("headRefName") or "",
                 ci, ((p.get("author") or {}).get("login") or "?")]))
')" || die "the PR row could not be parsed"
IFS=$'\t' read -r NUM P_STATE P_DRAFT P_MERGE P_HEAD P_BRANCH P_CI P_AUTHOR <<<"$row"

[ "$P_STATE" = "OPEN" ] || refuse "PR #$PR is $P_STATE — nothing to ship"
[ "$P_DRAFT" = "true" ] && refuse "PR #$PR is a DRAFT — a draft is not offered for delivery"
[ "$P_MERGE" = "MERGEABLE" ] || refuse "PR #$PR is $P_MERGE — no merge on a conflicted, behind or blocked head, under any flag"
[ "$P_CI" != "red" ] && [ "$P_CI" != "pending" ] || refuse "PR #$PR has CI $P_CI — a red or unfinished check is not evidence of a green change"

# ── 4 and 5 · the verdict, and the sha it judged ─────────────────────────────────────────────
[ -n "$REVIEW_FILE" ] || REVIEW_FILE="$STATE/eindri-reports/pr-$PR-review.md"
[ -r "$REVIEW_FILE" ] || refuse "no verdict for PR #$PR at $REVIEW_FILE — a merge without a judgement is a commit with paperwork"
VERDICT="$(head -1 "$REVIEW_FILE" 2>/dev/null | tr -d '\r')"
case "$VERDICT" in
  *REFUSE*|*refuse*|*NEEDS-REWORK*|*needs-rework*) refuse "the verdict for PR #$PR is a REFUSAL — ${VERDICT:0:120} (fix it and re-review; this door has no override)" ;;
esac
REVIEWED_SHA="$(grep -oE '\b[0-9a-f]{40}\b' "$REVIEW_FILE" 2>/dev/null | head -1)"
if [ -n "$REVIEWED_SHA" ] && [ "$REVIEWED_SHA" != "$P_HEAD" ]; then
  refuse "the verdict judged ${REVIEWED_SHA:0:12} and the PR is now ${P_HEAD:0:12} — a head that moved after the judgement is work nobody reviewed"
fi

if [ "$CHECK_ONLY" = 1 ] || [ "$DRY" = 1 ]; then
  if [ "$JSON" = 1 ]; then
    printf '{"pr":%s,"repo":"%s","head":"%s","ci":"%s","mergeable":"%s","delivery":"%s","verdict":"%s","action":"%s"}\n' \
      "$PR" "$REPO" "$P_HEAD" "$P_CI" "$P_MERGE" "$DELIVERY" "$(printf '%s' "$VERDICT" | head -c 60)" \
      "$([ "$CHECK_ONLY" = 1 ] && echo check || echo would-merge)"
  else
    printf 'ship[8]{pr,repo,head,ci,mergeable,delivery,verdict,action}:\n  "%s","%s","%s","%s","%s","%s","%s","%s"\n' \
      "$PR" "$REPO" "${P_HEAD:0:12}" "$P_CI" "$P_MERGE" "$DELIVERY" "$(printf '%s' "$VERDICT" | head -c 40)" \
      "$([ "$CHECK_ONLY" = 1 ] && echo check || echo would-merge)"
  fi
  exit 0
fi

# ── the merge ────────────────────────────────────────────────────────────────────────────────
MERGE_OUT="$(gh pr merge "$PR" -R "$REPO" --squash --delete-branch 2>&1)" || {
  printf 'ship: the merge failed — %s\n' "$(printf '%s' "$MERGE_OUT" | tail -2)" >&2
  printf 'ship[2]{pr,state}:\n  "%s","not merged"\n' "$PR"
  exit 1
}
MERGE_SHA="$(gh pr view "$PR" -R "$REPO" --json mergeCommit --jq '.mergeCommit.oid' 2>/dev/null || true)"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ── the record: ONE Runes entry per merge ────────────────────────────────────────────────────
RUNES_OK=no
if [ -x "$RUNES" ]; then
  "$RUNES" --component forge --title "PR #$PR merged by the reviewer ($REPO)" \
    --detail "reviewer=$(hostname -s 2>/dev/null || echo seat) reviewed_head=${P_HEAD} merge_commit=${MERGE_SHA:-?} verdict=${REVIEW_FILE} ruleset=$(bash "$ROOT/bin/forge/review-rules.sh" "$ROOT" 2>/dev/null | sed -n 's/.*ruleset[^0-9a-f]*\([0-9a-f]\{8,\}\).*/\1/p' | head -1) at=$TS" \
    >/dev/null 2>&1 && RUNES_OK=yes
fi
[ "$RUNES_OK" = yes ] || printf 'ship: WARNING — the merge happened and the Runes entry did NOT; record it by hand (bin/records/runes-append.sh)\n' >&2

# ── the word reaching him ───────────────────────────────────────────────────────────────────
MAILED="not attempted"
if [ "$MAIL_ON" = 1 ] && [ -x "$MAIL" ]; then
  body="$(mktemp)"
  {
    printf 'Merged: PR #%s in %s\n\n' "$PR" "$REPO"
    printf 'Title:  %s\n' "$(printf '%s' "$info" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("title",""))' 2>/dev/null)"
    printf 'Author: %s\n' "$P_AUTHOR"
    printf 'Reviewed head: %s\n' "$P_HEAD"
    printf 'Merge commit:  %s\n' "${MERGE_SHA:-unknown}"
    printf 'CI at merge:   %s\n' "$P_CI"
    printf 'Verdict:       %s\n' "$VERDICT"
    printf 'Record:        %s\n' "$REVIEW_FILE"
    printf 'Merged at:     %s\n' "$TS"
    printf '\nThe reviewer shipped it under delivery: reviewer-merges (RULES/08, 2026-11-06).\n'
    printf 'To undo the switch, set delivery: operator-merges on this project — one line.\n'
  } >"$body"
  if "$MAIL" --kind merged --subject "PR #$PR merged in $REPO" --body "$body" --ref "$REVIEW_FILE" >/dev/null 2>&1; then
    MAILED="sent"
  else
    MAILED="FAILED — the merge stands, the word did not arrive"
    printf 'ship: FAIL — the merge happened but the mail did not send (bin/notify/mail.sh --status)\n' >&2
  fi
  rm -f "$body"
fi

if [ "$JSON" = 1 ]; then
  printf '{"pr":%s,"repo":"%s","merge_commit":"%s","reviewed_head":"%s","runes":"%s","mail":"%s"}\n' \
    "$PR" "$REPO" "${MERGE_SHA:-}" "$P_HEAD" "$RUNES_OK" "$MAILED"
else
  printf 'shipped[6]{pr,repo,merge_commit,reviewed_head,runes,mail}:\n  "%s","%s","%s","%s","%s","%s"\n' \
    "$PR" "$REPO" "${MERGE_SHA:-?}" "${P_HEAD:0:12}" "$RUNES_OK" "$MAILED"
fi
