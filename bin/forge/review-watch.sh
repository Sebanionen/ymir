#!/usr/bin/env bash
# review-watch.sh — the missing trigger: a PR that arrives is a question the owner is asked.
#
# WHY (plan 206 §10.2, the Allfather's question): *"why isn't the heart reviewing all prs that
# come in on the ymir repo and merging them."* The review SPINE already exists
# (`bin/agents/eindri-review-spawn.sh`) and the judge is real — but the spine's only trigger is
# an errand's own terminal `done`. **Nothing watched the repository**, so a PR opened by another
# hand, or by an agent that never called `acclaim`, was never seen. This is that watch.
#
# WHAT IT DOES, one pass:
#   1 · list the open PRs of the named repos (never guessed: --repo, else YMIR_REVIEW_REPOS,
#       else the one documented default);
#   2 · for each PR not already judged at THIS head, raise ONE ask through `bin/seat/lock-ask.sh`
#       — the owner's own queue — naming the PR, its head, its CI and its mergeability;
#   3 · mark the (PR, head) so a second pass in the same minute raises nothing (the flood brake);
#   4 · `--judge <n>` seats the judge for that PR through the spine, which is the owner's answer.
#
# WHAT IT NEVER DOES: merge, push, comment on GitHub, or decide. A watch that decided would be a
# gate with no judge in it.
#
# Usage:
#   review-watch.sh [--repo owner/repo ...] [--dry-run] [--json] [--all]
#   review-watch.sh --judge <n> [--repo owner/repo]      # the owner's answer: seat the judge
#   review-watch.sh --status                             # what the watch sees, and what it raised
#   review-watch.sh --install-timer [--interval 10min]    # the clock: a user timer, every 10 minutes
#   review-watch.sh --timer-status | --uninstall-timer
#
# Exit: 0 judged · 1 a fault (named) · 2 usage · 3 refused (no identity / no owner).
set -u
VERSION="1.0.0"
SELF="$(basename "$0")"

case "${1-}" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
[ -n "$STATE" ] || { printf 'review-watch: the state dir is unresolved\n' >&2; exit 1; }

LOCK_ASK="$ROOT/bin/seat/lock-ask.sh"
SPINE="$ROOT/bin/agents/eindri-review-spawn.sh"
# Rule 07: the repos are configuration with ONE documented default.
DEFAULT_REPOS="${YMIR_REVIEW_REPOS:-zerwiz/ymir}"

die()    { printf 'review-watch: %s\n' "$*" >&2; exit 1; }
usage()  { printf 'review-watch: %s\n' "$*" >&2; exit 2; }
refuse() { printf 'review-watch: REFUSED — %s\n' "$*" >&2; exit 3; }

REPOS=(); DRY=0 JSON=0 ALL=0 JUDGE=""; STATUS_ONLY=0
TIMER_ACTION=""; TIMER_INTERVAL="10min"
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPOS+=("${2:-}"); shift 2 ;;
    --repo=*) REPOS+=("${1#--repo=}"); shift ;;
    --judge) JUDGE="${2:-}"; shift 2 ;;
    --judge=*) JUDGE="${1#--judge=}"; shift ;;
    --dry-run) DRY=1; shift ;;
    --json) JSON=1; shift ;;
    --all) ALL=1; shift ;;
    --status) STATUS_ONLY=1; shift ;;
    --install-timer) TIMER_ACTION=install; shift ;;
    --uninstall-timer) TIMER_ACTION=uninstall; shift ;;
    --timer-status) TIMER_ACTION=status; shift ;;
    --interval) TIMER_INTERVAL="${2:-10min}"; shift 2 ;;
    --interval=*) TIMER_INTERVAL="${1#--interval=}"; shift ;;
    -*) usage "unknown flag $1" ;;
    *) usage "unexpected argument $1" ;;
  esac
done
if [ "${#REPOS[@]}" -eq 0 ]; then
  # shellcheck disable=SC2206
  IFS=', ' read -r -a REPOS <<<"$DEFAULT_REPOS"
fi

command -v gh >/dev/null 2>&1 || refuse "gh is not on PATH here — a watch with no GitHub door sees nothing, and must not say 'nothing to do'"
if ! gh auth status >/dev/null 2>&1; then
  refuse "this seat has NO working GitHub identity (gh auth status failed) — the watch cannot read a PR, so it refuses rather than reporting an empty repository"
fi


# ── the clock (plan 206 §6 M4) ───────────────────────────────────────────────────────────────
# A watch nobody runs is a watch that does not exist. The unit is a USER timer: no listener, no
# root, and it runs the same command a human runs — so a quiet hour is a quiet hour and not a
# stopped loop.
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SERVICE="review-watch.service"; TIMER="review-watch.timer"
if [ -n "$TIMER_ACTION" ]; then
  case "$TIMER_ACTION" in
    install)
      mkdir -p "$UNIT_DIR" || die "cannot create $UNIT_DIR"
      cat >"$UNIT_DIR/$SERVICE" <<UNIT
[Unit]
Description=review-watch — ask the lock owner about every unjudged open PR (plan 206)

[Service]
Type=oneshot
WorkingDirectory=$ROOT
ExecStart=/usr/bin/env bash $ROOT/bin/forge/review-watch.sh
UNIT
      cat >"$UNIT_DIR/$TIMER" <<UNIT
[Unit]
Description=review-watch — the review loop's clock (every $TIMER_INTERVAL)

[Timer]
OnBootSec=3min
OnUnitActiveSec=$TIMER_INTERVAL
AccuracySec=30s
Unit=$SERVICE

[Install]
WantedBy=timers.target
UNIT
      systemctl --user daemon-reload 2>/dev/null || true
      systemctl --user enable --now "$TIMER" 2>&1 | tail -2 || die "the timer could not be enabled — the unit is written at $UNIT_DIR/$TIMER"
      printf 'timer[3]{unit,interval,state}:\n  "%s","%s","%s"\n' "$UNIT_DIR/$TIMER" "$TIMER_INTERVAL" \
        "$(systemctl --user is-active "$TIMER" 2>/dev/null | head -1 || true)"
      exit 0 ;;
    uninstall)
      systemctl --user disable --now "$TIMER" >/dev/null 2>&1 || true
      rm -f "$UNIT_DIR/$SERVICE" "$UNIT_DIR/$TIMER"
      systemctl --user daemon-reload 2>/dev/null || true
      printf 'timer[2]{unit,state}:\n  "%s","removed"\n' "$UNIT_DIR/$TIMER"
      exit 0 ;;
    status)
      printf 'timer[3]{unit,active,next}:\n  "%s","%s","%s"\n' "$UNIT_DIR/$TIMER" \
        "$(systemctl --user is-active "$TIMER" 2>/dev/null | head -1 || true)" \
        "$(systemctl --user list-timers "$TIMER" --no-pager 2>/dev/null | sed -n '2p' | awk '{print $1, $2, $3}')"
      exit 0 ;;
  esac
fi

# ── the owner's answer: seat the judge ────────────────────────────────────────────────────────
if [ -n "$JUDGE" ]; then
  [ -x "$SPINE" ] || die "the review spine is missing at $SPINE"
  # The repo of the PR is resolved from the one repo that answers for it.
  url=""
  for r in "${REPOS[@]}"; do
    [ -n "$r" ] || continue
    if gh pr view "$JUDGE" -R "$r" --json number >/dev/null 2>&1; then
      url="https://github.com/$r/pull/$JUDGE"; break
    fi
  done
  [ -n "$url" ] || refuse "PR #$JUDGE is not readable in ${REPOS[*]} — nothing is seated for a PR that cannot be read"
  [ "$DRY" = 1 ] && { printf 'review-watch[2]{judge,would_seat}:\n  "%s","%s --pr %s"\n' "$JUDGE" "$SPINE" "$url"; exit 0; }
  exec "$SPINE" --pr "$url"
fi

# ── one pass ──────────────────────────────────────────────────────────────────────────────────
RAISED=0; SEEN=0; SKIPPED=0
rows=()
for repo in "${REPOS[@]}"; do
  [ -n "$repo" ] || continue
  prs="$(gh pr list -R "$repo" --state open --limit 100 \
          --json number,title,headRefOid,mergeable,isDraft,statusCheckRollup,author 2>/dev/null)" \
    || die "gh pr list failed for $repo — no PR list, no watch (a refusal, not an empty repo)"
  [ -n "$prs" ] || prs="[]"
  while IFS=$'\t' read -r num title head mergeable draft ci author; do
    [ -n "$num" ] || continue
    SEEN=$((SEEN + 1))
    marker="$STATE/.reviewed/raised-pr-$num.$head"
    if [ -f "$marker" ]; then SKIPPED=$((SKIPPED + 1)); continue; fi
    if [ "$draft" = "true" ]; then
      SKIPPED=$((SKIPPED + 1))
      rows+=("$(printf 'pr[6]{repo,n,head,state,why,raised}:\n  "%s","%s","%s","%s","%s","%s"' \
        "$repo" "$num" "${head:0:12}" "$mergeable" "draft — a draft is not offered for review" "no")")
      continue
    fi
    question="PR #$num ($repo) is open at head ${head:0:12}: mergeable=$mergeable ci=$ci. May I judge it — run the rules floor and the gates here, and give a verdict?"
    if [ "$DRY" = 1 ]; then
      rows+=("$(printf 'pr[6]{repo,n,head,state,why,raised}:\n  "%s","%s","%s","%s","%s","%s"' \
        "$repo" "$num" "${head:0:12}" "$mergeable" "would ask the lock owner" "dry-run")")
      continue
    fi
    if [ -x "$LOCK_ASK" ] && out="$("$LOCK_ASK" ask "$question" --task "pr-$num.$head" --as review-watch 2>&1)"; then
      mkdir -p "$STATE/.reviewed" 2>/dev/null || true
      printf '%s\n' "$out" >"$marker" 2>/dev/null || true
      RAISED=$((RAISED + 1))
      rows+=("$(printf 'pr[6]{repo,n,head,state,why,raised}:\n  "%s","%s","%s","%s","%s","%s"' \
        "$repo" "$num" "${head:0:12}" "$mergeable" "asked the lock owner" "yes")")
    else
      # A watch that cannot speak is a fault, said out loud — never a quiet pass.
      printf 'review-watch: the ask for %s #%s was REFUSED: %s\n' "$repo" "$num" "$(printf '%s' "${out:-no output}" | tail -1)" >&2
      rows+=("$(printf 'pr[6]{repo,n,head,state,why,raised}:\n  "%s","%s","%s","%s","%s","%s"' \
        "$repo" "$num" "${head:0:12}" "$mergeable" "the ask was refused" "no")")
    fi
  done < <(printf '%s' "$prs" | python3 -c '
import json, sys
try: prs = json.load(sys.stdin)
except Exception: prs = []
for p in prs:
    checks = p.get("statusCheckRollup") or []
    concl = [c.get("conclusion") or c.get("state") or "?" for c in checks]
    if not concl: ci = "none"
    elif any(c in ("FAILURE", "ERROR", "CANCELLED", "TIMED_OUT") for c in concl): ci = "red"
    elif any(c in ("PENDING", "IN_PROGRESS", "QUEUED", "") for c in concl): ci = "pending"
    else: ci = "green"
    author = (p.get("author") or {}).get("login") or "?"
    print("\t".join([str(p.get("number")), (p.get("title") or "")[:80].replace("\t", " "),
                     p.get("headRefOid") or "", p.get("mergeable") or "UNKNOWN",
                     "true" if p.get("isDraft") else "false", ci, author]))
')
done

if [ "$JSON" = 1 ]; then
  python3 - "$RAISED" "$SEEN" "$SKIPPED" <<'PY'
import json, sys
print(json.dumps({"raised": int(sys.argv[1]), "seen": int(sys.argv[2]), "skipped": int(sys.argv[3])}))
PY
else
  printf 'review-watch[4]{repos,seen,raised,skipped}:\n  "%s","%s","%s","%s"\n' \
    "${REPOS[*]}" "$SEEN" "$RAISED" "$SKIPPED"
  for r in "${rows[@]}"; do printf '%s\n' "$r"; done
fi
[ "$RAISED" -gt 0 ] || [ "$ALL" = 1 ] || true
exit 0
