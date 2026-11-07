#!/usr/bin/env bash
# eindri-review-spawn.sh — the review spine. FORSETI the Judge is sent after
# every ship: a worker's terminal `done` opens a dedicated review errand that
# audits the PR it opened, before the Allfather's seal.
#
# The delivery-gate law makes a PR the only way work leaves (the guards, the fix
# notes, the no-merge rule). This is the other half of that law: a PR is not
# "done" when it is pushed, it is done when it has been AUDITED. The spine sends
# the judge, once per task, and never again.
#
#   bin/agents/eindri-review-spawn.sh <task-id> [--pr-url <url>] [--branch <b>]
#                              [--dry-run] [--force]
#   bin/agents/eindri-review-spawn.sh --pr <pr-url> [--project <path>] [--dry-run] [--force]
#        the PR-ONLY mode (plan 206 §10.3a): judge a pull request this seat did not
#        author and has no errand record for. The marker is per HEAD, so a moved
#        head earns a fresh judgement and a second run in the same minute does not.
#
# It is called by the terminal act's done path (bin/agents/eindri-acclaim.sh) and can be
# run by hand. It reads the PR from the task's own record (state/<id>.status
# carries `done: opened PR <url>`), fills the fierce review brief for THIS task,
# and spawns a scout-kind `<id>-review` errand through the einherjar road:
#
#   bin/agents/einherjar-spawn.sh <id>-review <project> --scout --backend herdr
#       --harness pi --model <resolved by bin/model/agent-model.sh> --effort high
#
# The judge is read-only by charter (Forseti's card keeps edit:deny/write:deny),
# and the verdict lands on the wake road at state/eindri-reports/<id>-review.md.
#
# One per task. A `.reviewed` marker (state/.reviewed/<id>) is written only after
# the review is SEATED; a re-done never re-reviews, and a failed spawn leaves no
# marker so a retry can still seat the judge. YMIR_AUTO_REVIEW=off is the loud
# override (it prints why and exits 0); a failed spawn is never silent.
#
# Config (Rule 07 — env with one documented default):
#   YMIR_AUTO_REVIEW    on|off              default on
#   YMIR_REVIEW_HARNESS pi|...              default from the roster (Forseti), else pi
#   YMIR_REVIEW_MODEL   provider/model      default: resolved by bin/model/agent-model.sh forseti
#   YMIR_REVIEW_EFFORT  low..max            default high
#   YMIR_REVIEW_BACKEND tmux|herdr          default herdr
#   YMIR_REVIEW_DRY     0|1                 default 0; 1 = print the spawn line, seat nothing
#
# Output: Galdr TOON.
set -u

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${BROKK_ROOT_OVERRIDE:-$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)}"

# The roots that live OUTSIDE the code tree resolve through the one door
# (Rule 04): the operator's home, not a path baked into the tree.
if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  for _yc in "$SCRIPT_DIR/../vault/hoard-lib.sh" "$SCRIPT_DIR/../vault/hoard-lib.sh" "$SCRIPT_DIR/../../vault/hoard-lib.sh"; do
    [ -r "$_yc" ] && { . "$_yc"; YMIR_HOARD_LIB_LOADED=1; break; }
  done
  unset _yc
fi
hoard_state_dir YMIR_STATE_DIR

TEMPLATE="$ROOT/.agents/assets/templates/review-brief.template.md"

usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
}

case "${1:-}" in
  -h|--help|"") usage; exit 0 ;;
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
esac

ID=""
PR_URL_ARG=""
BRANCH_ARG=""
PR_ONLY=0
PROJECT_ARG=""
DRY=0
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --pr) PR_ONLY=1; PR_URL_ARG="${2-}"; shift 2 ;;
    --pr=*) PR_ONLY=1; PR_URL_ARG=${1#--pr=}; shift ;;
    --project) PROJECT_ARG="${2-}"; shift 2 ;;
    --project=*) PROJECT_ARG=${1#--project=}; shift ;;
    --pr-url) PR_URL_ARG="${2-}"; shift 2 ;;
    --pr-url=*) PR_URL_ARG=${1#--pr-url=}; shift ;;
    --branch) BRANCH_ARG="${2-}"; shift 2 ;;
    --branch=*) BRANCH_ARG=${1#--branch=}; shift ;;
    --dry-run) DRY=1; shift ;;
    --force) FORCE=1; shift ;;
    -*) printf 'error: unknown flag %s\nhelp: bin/agents/eindri-review-spawn.sh <task-id> [--pr-url <url>] [--branch <b>] [--dry-run] [--force] | --pr <url>\n' "$1" >&2; exit 2 ;;
    *)
      if [ -z "$ID" ]; then ID=$1
      else printf 'error: too many positional arguments\nhelp: one task-id\n' >&2; exit 2
      fi
      shift ;;
  esac
done
[ -n "$ID" ] || [ "$PR_ONLY" = 1 ] || { printf 'error: task-id is required\nhelp: bin/agents/eindri-review-spawn.sh <task-id> | --pr <url>\n' >&2; exit 2; }
if [ -n "$ID" ]; then
  case "$ID" in
    */*|.*|*' '*) printf 'error: invalid task-id %s\n' "$ID" >&2; exit 2 ;;
  esac
fi

REVIEW_ID="${ID:+$ID-review}"
AUTO="${YMIR_AUTO_REVIEW:-on}"
HARNESS="${YMIR_REVIEW_HARNESS:-}"
# The judge's model is RESOLVED for THIS seat (plan 206 §11, the Allfather: "all users and
# computers have different models and capabilities"). The code names no model id: the fleet
# declares its choice in the private home, the seat's own catalogue says whether it can serve
# it, and a seat that cannot says so instead of quietly borrowing a neighbour's promise.
MODEL="${YMIR_REVIEW_MODEL:-$(bash "$ROOT/bin/model/agent-model.sh" forseti --plain 2>/dev/null || true)}"
[ -n "$MODEL" ] || { printf 'error: no model resolved for the judge on this seat\nhelp: bin/model/agent-model.sh forseti --explain (a model this seat cannot serve is a refusal, not a fallback)\n' >&2; exit 1; }
EFFORT="${YMIR_REVIEW_EFFORT:-high}"
BACKEND="${YMIR_REVIEW_BACKEND:-herdr}"
# YMIR_REVIEW_DRY=1 behaves exactly as --dry-run: resolve and print the spawn
# line without seating the judge. It lets the whole spine be proved (the acclaim
# hook included) on a fixture, with no live seat.
[ "${YMIR_REVIEW_DRY:-0}" = 1 ] && DRY=1

skip() {  # <why>
  printf 'review-spawn[1]{task,review,state,why}:\n  "%s","%s","skipped","%s"\n' "$ID" "$REVIEW_ID" "$1"
  exit 0
}

# ── the guards: off, a review of a review, an already-reviewed task ──────────
[ "$AUTO" = off ] && skip "YMIR_AUTO_REVIEW=off (the loud override)"
case "$ID" in
  *-review) skip "the id is already a review — a scout opens no PR" ;;
esac

# Find the task record. A well-formed spawn writes it in the machine state, but
# a per-seat BROKK_STATE_OVERRIDE can move it, so both are consulted.
meta_value() {  # <file> <key>
  grep "^$2=" "$1" 2>/dev/null | tail -1 | cut -d= -f2- || true
}
TASK_STATE=""
TASK_META=""
for _cand in "${BROKK_STATE_OVERRIDE:-}" "$YMIR_STATE_DIR" "${BROKK_HOME:-$ROOT}/state" "$ROOT/state"; do
  [ -n "$_cand" ] || continue
  if [ -f "$_cand/$ID.meta" ]; then TASK_STATE="$_cand"; TASK_META="$_cand/$ID.meta"; break; fi
done
unset _cand
NO_TASK=0
if [ -z "$TASK_META" ]; then
  if [ "$PR_ONLY" = 1 ]; then
    NO_TASK=1
  else
    skip "no task record at <state>/$ID.meta — nothing to review"
  fi
fi
TASK_KIND="$(meta_value "$TASK_META" kind)"; TASK_KIND=${TASK_KIND:-ship}
[ "$NO_TASK" = 0 ] && [ "$TASK_KIND" = scout ] && skip "kind=scout — a scout opens no PR"
PROJECT="$(meta_value "$TASK_META" project)"
[ -n "$PROJECT" ] || PROJECT="${BROKK_ROOT_OVERRIDE:-$ROOT}"
WORKTREE="$(meta_value "$TASK_META" worktree)"

# The shared state the spine writes and Brokk reads: the RESOLVED task root
# (the hoard, symlinked beside the code), never an inference from the existence
# of $PROJECT/state — that inference seated a SECOND judge under an override
# (Forseti's verdict on #235, reproduced live). The resolved root wins; the
# project's state dir is only a fallback when no task state resolved at all.
SHARED_ROOT="$PROJECT"
[ -n "$TASK_STATE" ] && SHARED_STATE="$TASK_STATE" || SHARED_STATE="$SHARED_ROOT/state"
SHARED_DATA="$SHARED_ROOT/data"

# ── the PR: from the flag, else the task's own terminal status line ──────────
PR_URL="$PR_URL_ARG"
if [ -z "$PR_URL" ]; then
  # The done line may sit in the task's own record state or the caller's seat
  # state (a per-seat BROKK_STATE_OVERRIDE); the spine reads wherever it landed.
  for _sf in "${BROKK_STATE_OVERRIDE:-}/$ID.status" "$TASK_STATE/$ID.status" "$SHARED_STATE/$ID.status"; do
    [ -n "$_sf" ] || continue
    [ -f "$_sf" ] || continue
    _url=$(grep -oE 'https://github\.com/[^[:space:]]+/pull/[0-9]+' "$_sf" 2>/dev/null | tail -1 || true)
    if [ -n "$_url" ]; then PR_URL="$_url"; break; fi
  done
  unset _sf _url
fi
[ -n "$PR_URL" ] || { release_claim; skip "no PR in state/$ID.status (a local-only tip never reviews)"; }
PR_NUMBER="$(printf '%s' "$PR_URL" | grep -oE '/pull/[0-9]+' | grep -oE '[0-9]+' | tail -1 || true)"
[ -n "$PR_NUMBER" ] || PR_NUMBER="?"

# ── PR-ONLY mode: the PR is the record, and its HEAD is the marker (plan 206 §10.3a) ──
HEAD_SHA=""
if [ "$PR_ONLY" = 1 ]; then
  command -v gh >/dev/null 2>&1 || {
    printf 'error: gh is required to judge a PR by url, and it is not on PATH here\nhelp: a judge with no GitHub door cannot read the head it must review\n' >&2
    exit 1
  }
  SLUG="$(printf '%s' "$PR_URL" | sed -nE 's#^https://github\.com/([^/]+/[^/]+)/pull/([0-9]+).*#\1#p')"
  [ -n "$SLUG" ] || { printf 'error: cannot read owner/repo from the PR url %s\n' "$PR_URL" >&2; exit 1; }
  _pr_json="$(gh pr view "$PR_NUMBER" -R "$SLUG" --json headRefOid,headRefName,mergeable 2>/dev/null || true)"
  HEAD_SHA="$(printf '%s' "$_pr_json" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("headRefOid",""))' 2>/dev/null || true)"
  [ -n "$HEAD_SHA" ] || {
    printf 'error: could not read PR #%s from %s — no head sha, so no marker and no honest judgement\nhelp: check the GitHub identity on this seat (gh auth status)\n' "$PR_NUMBER" "$SLUG" >&2
    exit 1
  }
  if [ -z "$BRANCH_ARG" ]; then
    BRANCH_ARG="$(printf '%s' "$_pr_json" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("headRefName",""))' 2>/dev/null || true)"
  fi
  unset _pr_json
  if [ "$NO_TASK" = 1 ]; then
    ID="pr-$PR_NUMBER"
    REVIEW_ID="$ID-review"
    PROJECT="${PROJECT_ARG:-$ROOT}"
    SHARED_ROOT="$PROJECT"
    SHARED_STATE="$YMIR_STATE_DIR"
    SHARED_DATA="${BROKK_DATA_OVERRIDE:-$PROJECT/data}"
    TASK_BRIEF=""
    TASK_STATUS=""
  fi
fi

# ── the branch: the flag, else the task worktree's own branch ────────────────
BRANCH="$BRANCH_ARG"
if [ -z "$BRANCH" ] && [ -n "$WORKTREE" ] && [ -d "$WORKTREE" ]; then
  _b=$(git -C "$WORKTREE" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  case "$_b" in HEAD|"") ;; *) BRANCH="$_b" ;; esac
  unset _b
fi
[ -n "$BRANCH" ] || BRANCH="eindri/$ID"

# ── the anti-double marker ───────────────────────────────────────────────────
REVIEWED_DIR="$SHARED_STATE/.reviewed"
if [ "$NO_TASK" = 1 ]; then
  # Plan 206 §10.3 — a PR is judged once per HEAD. A moved head is new work and earns a
  # fresh judgement; the same head twice in a minute earns nothing (the flood brake).
  MARKER="$REVIEWED_DIR/pr-$PR_NUMBER.${HEAD_SHA:-unknown}"
  REVIEW_SPAWNED="$MARKER.spawning"
else
  MARKER="$REVIEWED_DIR/$ID"
  REVIEW_SPAWNED="$REVIEWED_DIR/$ID.spawning"
fi
if [ -f "$MARKER" ] && [ "$FORCE" -ne 1 ]; then
  skip "already reviewed ($MARKER exists) — a re-done never re-reviews"
fi
if [ -f "$MARKER" ] && [ "$FORCE" -eq 1 ]; then
  printf 'review-spawn: --force overrides the anti-double marker (%s) — a deliberate re-review\n' "$MARKER"
fi
# Claim the task atomically so two racing dones cannot seat two judges. A stale
# claim (older than 30 min: a spawn that died badly) is reclaimed.
if [ -d "$REVIEW_SPAWNED" ]; then
  _age=$(( $(date +%s) - $(stat -c %Y "$REVIEW_SPAWNED" 2>/dev/null || echo 0) ))
  if [ "$_age" -lt 1800 ]; then
    skip "a review spawn is already in flight for this task"
  fi
  rm -rf "$REVIEW_SPAWNED" 2>/dev/null || true
fi
mkdir -p "$REVIEWED_DIR" 2>/dev/null || true
if [ "$DRY" -eq 0 ] && ! mkdir "$REVIEW_SPAWNED" 2>/dev/null; then
  skip "a review spawn is already in flight for this task"
fi
release_claim() { [ "$DRY" -eq 0 ] && rmdir "$REVIEW_SPAWNED" 2>/dev/null || true; }


# ── the judge's seat: the roster resolves the figure's harness ───────────────
if [ -z "$HARNESS" ] && [ -x "$SCRIPT_DIR/../fleet/agents-config.sh" ]; then
  HARNESS="$("$SCRIPT_DIR/../fleet/agents-config.sh" get forseti harness 2>/dev/null | head -n1 || true)"
fi
HARNESS="${HARNESS:-pi}"

# ── fill the fierce brief for THIS task ──────────────────────────────────────
BRIEF="$SHARED_DATA/$REVIEW_ID/brief.md"
REPORT_PATH="$SHARED_STATE/eindri-reports/$REVIEW_ID.md"
STATUS_PATH="$SHARED_STATE/$REVIEW_ID.status"
INBOX_DIR="$SHARED_STATE/$REVIEW_ID.inbox"
WAKE_QUEUE="$SHARED_STATE/.wake-queue"
TASK_BRIEF="$SHARED_DATA/$ID/brief.md"
TASK_STATUS="$SHARED_STATE/$ID.status"

if [ ! -r "$TEMPLATE" ]; then
  release_claim
  printf 'error: review brief template not found at %s\nhelp: it lives in the tree at .agents/assets/templates/review-brief.template.md\n' "$TEMPLATE" >&2
  exit 1
fi
brief=$(cat "$TEMPLATE")
brief=${brief//'{{TASK_ID}}'/$ID}
brief=${brief//'{{REVIEW_ID}}'/$REVIEW_ID}
brief=${brief//'{{PR_URL}}'/$PR_URL}
brief=${brief//'{{PR_NUMBER}}'/$PR_NUMBER}
brief=${brief//'{{BRANCH}}'/$BRANCH}
brief=${brief//'{{PROJECT}}'/$PROJECT}
brief=${brief//'{{STATE_DIR}}'/$SHARED_STATE}
brief=${brief//'{{DATA_DIR}}'/$SHARED_DATA}
brief=${brief//'{{REPORT_PATH}}'/$REPORT_PATH}
brief=${brief//'{{STATUS_PATH}}'/$STATUS_PATH}
brief=${brief//'{{INBOX_DIR}}'/$INBOX_DIR}
brief=${brief//'{{WAKE_QUEUE}}'/$WAKE_QUEUE}
brief=${brief//'{{TASK_BRIEF}}'/$TASK_BRIEF}
brief=${brief//'{{TASK_STATUS}}'/$TASK_STATUS}
mkdir -p "$SHARED_DATA/$REVIEW_ID" || true
printf '%s\n' "$brief" >"$BRIEF" || {
  release_claim
  printf 'error: could not write the review brief at %s\n' "$BRIEF" >&2
  exit 1
}

# ── the spawn line (printed whole on --dry-run) ──────────────────────────────
spawn=( "$SCRIPT_DIR/einherjar-spawn.sh" "$REVIEW_ID" "$PROJECT" --scout
        --backend "$BACKEND" --harness "$HARNESS" --model "$MODEL" --effort "$EFFORT" )
spawn_line="$SCRIPT_DIR/einherjar-spawn.sh $REVIEW_ID $(printf '%q' "$PROJECT") --scout --backend $BACKEND --harness $HARNESS --model $MODEL --effort $EFFORT"

if [ "$DRY" -eq 1 ]; then
  release_claim
  printf 'review-spawn[1]{task,review,pr,branch,head,marker,brief,report,spawn}:\n'
  printf '  "%s","%s","%s","%s","%s","%s","%s","%s","%s"\n' \
    "$ID" "$REVIEW_ID" "$PR_URL" "$BRANCH" "${HEAD_SHA:-none}" "$MARKER" "$BRIEF" "$REPORT_PATH" "$spawn_line"
  exit 0
fi

# ── seat the judge through the einherjar road ────────────────────────────────
# The review's records belong to the SHARED state, never the caller's seat: the
# spawn is a Brokk-level act, and its meta/status must be read by supervision.
if env -u BROKK_STATE_OVERRIDE -u BROKK_DATA_OVERRIDE \
       BROKK_HOME="$SHARED_ROOT" BROKK_STATE_OVERRIDE="$SHARED_STATE" BROKK_DATA_OVERRIDE="$SHARED_DATA" \
       "${spawn[@]}"; then
  {
    printf 'review=%s\n' "$REVIEW_ID"
    printf 'pr=%s\n' "$PR_URL"
    printf 'branch=%s\n' "$BRANCH"
    printf 'report=%s\n' "$REPORT_PATH"
    printf 'at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >"$MARKER" 2>/dev/null || true
  release_claim
  printf 'review-spawn[1]{task,review,pr,branch,brief,report,state}:\n'
  printf '  "%s","%s","%s","%s","%s","%s","seated"\n' \
    "$ID" "$REVIEW_ID" "$PR_URL" "$BRANCH" "$BRIEF" "$REPORT_PATH"
else
  _rc=$?
  release_claim
  printf 'error: the review spawn failed (exit %s) for %s — NO judge is seated; retry with bin/agents/eindri-review-spawn.sh %s --force\n' \
    "$_rc" "$ID" "$ID" >&2
  exit 1
fi
