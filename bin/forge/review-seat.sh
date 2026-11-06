#!/usr/bin/env bash
# review-seat.sh — the reviewer's SEAT: pi in a herdr pane, on the heart, on a loop.
#
# WHY (the Allfather, 2026-11-06): *"make so were using the pi harness in herdr for this work."*
# Plan 203 §12 asked for a reviewer that lives on the heart, in a herdr pane, running pi, so it
# reviews while the fleet sleeps. The doors were built; the SEAT was not. This is the seat:
#
#   one workspace named `review`, one pi agent in it, its cwd a CLONE (never a worktree of a
#   smith's), its charter the judge's role file plus the law it judges by, and its model resolved
#   for THAT seat (bin/model/agent-model.sh — never a model id in this file).
#
# THE SEAT LAWS IT KEEPS (herdr-panes skill, 2026-09-23):
#   · a seat loads its own figure — `--append-system-prompt <role file>`, or pi believes it is Brokk;
#   · a seat never takes the helm — a private BROKK_MACHINE_STATE_DIR on the workspace, set at
#     CREATE time because `herdr agent start` has no --env.
#
# Usage:
#   review-seat.sh status                       # is the seat there, and what is it doing
#   review-seat.sh ensure [--clone <path>]      # raise it (idempotent); prints pane + agent
#   review-seat.sh ask <pr> [--wait]            # put one PR in front of the seated judge
#   review-seat.sh charter                      # print the charter it would load
#   review-seat.sh close                        # lower the seat's workspace
#
# Exit: 0 ok · 1 a fault (named) · 2 usage · 3 refused (not inside herdr / no clone).
set -u
VERSION="1.0.0"

case "${1-}" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help|"") sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
[ -n "$STATE" ] || { printf 'review-seat: the state dir is unresolved\n' >&2; exit 1; }

WORKSPACE_LABEL="review"
ROLE_FILE="$ROOT/.agents/agents/forseti-reviewer.md"
CHARTER="$STATE/review/charter.md"
DEFAULT_CLONE="${YMIR_REVIEW_CLONE:-$HOME/review/ymir}"

die()    { printf 'review-seat: %s\n' "$*" >&2; exit 1; }
usage()  { printf 'review-seat: %s\n' "$*" >&2; exit 2; }
refuse() { printf 'review-seat: REFUSED — %s\n' "$*" >&3; exit 3; }

herdr_ok() { [ "${HERDR_ENV:-}" = 1 ] && command -v herdr >/dev/null 2>&1; }
need_herdr() {
  herdr_ok || refuse "this is not a herdr pane (HERDR_ENV=${HERDR_ENV:-unset}) — the seat lives in herdr; run this from a pane on the machine that will review"
}

# The agent rows this seat would raise: the pane's cwd is the review clone, so a worktree of a
# smith's is never the judge's ground.
seat_pane() {  # -> pane id whose cwd is the review clone (or empty)
  local clone=$1
  herdr agent list 2>/dev/null | python3 -c '
import json, sys
clone = sys.argv[1]
try: d = json.load(sys.stdin)
except Exception: raise SystemExit
for a in d.get("result", {}).get("agents", []):
    if a.get("cwd") == clone:
        print(a.get("pane_id") or "")
        break
' "$clone" 2>/dev/null || true
}

write_charter() {
  local clone=$1
  mkdir -p "$STATE/review" || die "cannot create $STATE/review"
  {
    printf '# The reviewer charter — Forseti the Judge\n\n'
    printf 'You are the reviewer for %s. You judge; you do not author.\n\n' "$clone"
    printf '## The law you load, in this order\n\n'
    printf '1. %s/AGENTS.md — the repository contract\n' "$clone"
    printf '2. %s/RULES/ — the house law (04 · 06 · 07 · 08 · 25 · 43 · 44)\n' "$clone"
    printf '3. %s/.review-rules.yaml — this project'"'"'s own declarations (a missing one is a REFUSAL)\n' "$clone"
    printf '4. plan 203 §12 (the reviewer on the heart) and plan 206 (the loop, the mouth, the switch)\n'
    printf '   in %s\n\n' "${YMIR_HOME:-$HOME/Documents/ymirhome}/svartalfaheim/whynotproductions/projects/ymir/plans"
    printf '## What you may do\n\n'
    printf -- '- read everything; run the gates and the tests YOURSELF on the fetched head\n'
    printf -- '- mark every claim in a packet verified or unverified\n'
    printf -- '- write ONE verdict to %s/eindri-reports/pr-<n>-review.md, first line PASS or REFUSE\n' "$STATE"
    printf -- '- ask the lock owner anything you may not do: bash bin/seat/lock-ask.sh ask "<question>"\n\n'
    printf '## What you may never do\n\n'
    printf -- '- merge, push, force-push, delete a branch, or edit the work you judge\n'
    printf -- '- review your own authored work; review a head that moved after the packet\n'
    printf -- '- pass a change on a red gate, an unverified claim, or a missing rules floor\n'
  } >"$CHARTER" || die "cannot write the charter at $CHARTER"
  printf '%s' "$CHARTER"
}

cmd_charter() {
  local clone=${1:-$DEFAULT_CLONE}
  local f; f="$(write_charter "$clone")"
  cat "$f"
}

cmd_status() {
  local clone=${1:-$DEFAULT_CLONE}
  need_herdr
  local pane; pane="$(seat_pane "$clone")"
  if [ -z "$pane" ]; then
    printf 'seat[3]{clone,pane,state}:\n  "%s","none","not seated — review-seat.sh ensure"\n' "$clone"
    return 0
  fi
  herdr agent get "$pane" 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin).get("result", {}).get("agent", {})
print(f"seat[3]{{clone,pane,state}}:\n  \"%s\",\"%s\",\"%s\"" % (sys.argv[1], d.get("pane_id"), d.get("agent_status")))
' "$clone"
}

cmd_ensure() {
  local clone=$DEFAULT_CLONE
  while [ $# -gt 0 ]; do case "$1" in --clone) clone="${2:-}"; shift 2 ;; --clone=*) clone="${1#--clone=}"; shift ;; *) shift ;; esac; done
  need_herdr
  [ -d "$clone" ] || refuse "no review clone at $clone — a judge reviews a CLONE of the delivered commit, never a smith's worktree (git clone <remote> $clone)"
  local pane; pane="$(seat_pane "$clone")"
  if [ -n "$pane" ]; then
    cmd_status "$clone"; return 0
  fi
  # The model is resolved for THIS seat, and named only if the catalogue lists it.
  local model; model="$(bash "$ROOT/bin/model/agent-model.sh" forseti --plain 2>/dev/null || true)"
  [ -n "$model" ] || die "no model resolved for the judge on this seat — bin/model/agent-model.sh forseti --explain"
  local charter; charter="$(write_charter "$clone")"
  local seat_state="${YMIR_REVIEW_SEAT_STATE:-$STATE/review/seat}"
  mkdir -p "$seat_state" || die "cannot create the seat's private state at $seat_state"

  local ws_out ws
  ws_out="$(herdr workspace create --cwd "$clone" --label "$WORKSPACE_LABEL" --no-focus \
              --env "BROKK_MACHINE_STATE_DIR=$seat_state" \
              --env "BROKK_STATE_OVERRIDE=$seat_state" 2>/dev/null)" \
    || die "herdr workspace create failed — is a herdr server running here?"
  ws="$(printf '%s' "$ws_out" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("result",{}).get("workspace",{}).get("workspace_id",""))' 2>/dev/null || true)"
  [ -n "$ws" ] || die "herdr created no workspace (its answer: $(printf '%s' "$ws_out" | head -c 200))"

  local pane_out
  pane_out="$(herdr pane list 2>/dev/null | python3 -c '
import json, sys
ws = sys.argv[1]
d = json.load(sys.stdin)
for p in d.get("result", {}).get("panes", []):
    if p.get("workspace_id") == ws:
        print(p.get("pane_id")); break
' "$ws" 2>/dev/null || true)"
  [ -n "$pane_out" ] || die "the new workspace has no pane — nothing to seat pi in"

  herdr agent start pi --kind pi --pane "$pane_out" -- --model "$model" \
    --append-system-prompt "$ROLE_FILE" --append-system-prompt "$charter" >/dev/null 2>&1 \
    || die "herdr agent start failed for pane $pane_out (model $model)"
  # Seating without verifying leaves an idle agent — the hard contract of the herdr skill.
  local tries=0 st=""
  while [ "$tries" -lt 20 ]; do
    st="$(herdr agent get "$pane_out" 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin).get("result",{}).get("agent",{}).get("agent_status",""))' 2>/dev/null || true)"
    case "$st" in working|idle|done|blocked) break ;; esac
    tries=$((tries + 1)); sleep 0.5
  done
  printf 'seat[5]{clone,pane,workspace,model,state}:\n  "%s","%s","%s","%s","%s"\n' \
    "$clone" "$pane_out" "$ws" "$model" "${st:-unknown}"
}

cmd_ask() {
  local pr="${1:-}"; shift || true
  local clone=$DEFAULT_CLONE WAIT=0
  while [ $# -gt 0 ]; do case "$1" in --clone) clone="${2:-}"; shift 2 ;; --wait) WAIT=1; shift ;; *) shift ;; esac; done
  [ -n "$pr" ] || usage "ask needs a PR number"
  need_herdr
  local pane; pane="$(seat_pane "$clone")"
  [ -n "$pane" ] || refuse "the judge is not seated in $clone — review-seat.sh ensure first"
  local line="Review PR #$pr. Fetch its head, run the rules floor and the gates YOURSELF here, then write ONE verdict to $STATE/eindri-reports/pr-$pr-review.md whose first line is PASS or REFUSE. Merge nothing; if you need a hand, ask the lock owner with bin/seat/lock-ask.sh."
  if [ "$WAIT" = 1 ]; then
    herdr agent prompt "$pane" "$line" --wait --until working >/dev/null 2>&1 \
      || die "the judge did not take the prompt (pane $pane)"
  else
    herdr agent prompt "$pane" "$line" >/dev/null 2>&1 || die "the judge did not take the prompt (pane $pane)"
  fi
  printf 'asked[3]{pane,pr,state}:\n  "%s","%s","prompted"\n' "$pane" "$pr"
}

cmd_close() {
  need_herdr
  local ws
  ws="$(herdr workspace list 2>/dev/null | python3 -c '
import json, sys
label = sys.argv[1]
d = json.load(sys.stdin)
for w in d.get("result", {}).get("workspaces", []):
    if (w.get("label") or "") == label:
        print(w.get("workspace_id")); break
' "$WORKSPACE_LABEL" 2>/dev/null || true)"
  [ -n "$ws" ] || { printf 'seat[2]{workspace,state}:\n  "%s","absent"\n' "$WORKSPACE_LABEL"; return 0; }
  herdr workspace close "$ws" >/dev/null 2>&1 || die "herdr refused to close $ws"
  printf 'seat[2]{workspace,state}:\n  "%s","closed"\n' "$WORKSPACE_LABEL"
}

ACTION="${1:-status}"; shift || true
case "$ACTION" in
  status)  cmd_status "$@" ;;
  ensure)  cmd_ensure "$@" ;;
  ask)     cmd_ask "$@" ;;
  charter) cmd_charter "$@" ;;
  close)   cmd_close "$@" ;;
  *) usage "unknown action '$ACTION' — status | ensure | ask | charter | close" ;;
esac
