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
#   review-seat.sh ensure [--clone <path>] [--primary]
#                                               # raise it (idempotent); --primary takes the helm
#                                               # when no live primary holds the lock
#   review-seat.sh ask <pr> [--wait]            # put one PR in front of the seated judge
#   review-seat.sh charter                      # print the charter it would load
#   review-seat.sh close                        # lower the seat's workspace
#   review-seat.sh --install-unit               # DURABLE + VISIBLE: a herdr server unit, and a
#                                               # keeper timer that re-raises the seat if it dies
#   review-seat.sh --unit-status | --uninstall-unit
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
HOME_DIR=""; ymir_home_root HOME_DIR 2>/dev/null || true
[ -n "$STATE" ] || { printf 'review-seat: the state dir is unresolved\n' >&2; exit 1; }
[ -n "$HOME_DIR" ] || { printf 'review-seat: the home is unresolved (bin/vault/hoard-lib.sh)\n' >&2; exit 1; }

WORKSPACE_LABEL="review"
ROLE_FILE="$ROOT/.agents/agents/forseti-reviewer.md"
CHARTER="$STATE/review/charter.md"
DEFAULT_CLONE="${YMIR_REVIEW_CLONE:-$HOME/review/ymir}"

die()    { printf 'review-seat: %s\n' "$*" >&2; exit 1; }
usage()  { printf 'review-seat: %s\n' "$*" >&2; exit 2; }
refuse() { printf 'review-seat: REFUSED — %s\n' "$*" >&3; exit 3; }

# The honest probe is the SERVER answering, not a variable: a herdr CLI reaches its server from
# a pane, from a timer and over ssh, and refusing on HERDR_ENV alone would refuse every one of
# those while the server stands (RULES/25 — probe, never assume).
need_herdr() {
  command -v herdr >/dev/null 2>&1 \
    || refuse "herdr is not installed on this seat — the reviewer's seat lives in herdr"
  herdr agent list >/dev/null 2>&1 \
    || refuse "the herdr server does not answer here — start it (herdr) or run this on the machine that will review"
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
    printf '   in %s\n\n' "$HOME_DIR/svartalfaheim/whynotproductions/projects/ymir/plans"
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
  local clone=$DEFAULT_CLONE PRIMARY=0
  while [ $# -gt 0 ]; do case "$1" in
    --clone) clone="${2:-}"; shift 2 ;;
    --clone=*) clone="${1#--clone=}"; shift ;;
    --primary) PRIMARY=1; shift ;;
    *) shift ;;
  esac; done
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
  # THE SEAT LAW: a seat gets its own machine state, so it never contends for the primary's helm.
  # `--primary` is the deliberate exception — a machine with NO live primary (measured: the heart's
  # lock named a dead pid on 2026-11-06) has nobody to drain the arm, so the review seat takes the
  # helm and says so. It refuses when a live primary already holds it.
  local seat_state="${YMIR_REVIEW_SEAT_STATE:-$STATE/review/seat}"
  local -a ENV_ARGS=()
  if [ "$PRIMARY" = 1 ]; then
    local lk owner
    lk="$(bash "$ROOT/bin/records/ymir-state.sh" lock lock-path 2>/dev/null || true)"
    owner="$(bash "$ROOT/bin/records/ymir-state.sh" lock owner 2>/dev/null || true)"
    if [ -n "$lk" ] && [ -n "$owner" ] && [ -r "/proc/$owner/stat" ]; then
      refuse "a live primary already holds the lock (pid $owner) — the review seat stays a seat; do not give it the helm"
    fi
    printf 'seat[1]{helm}:
  "primary — no live lock owner on this machine, so the review seat drains the arm itself"\n'
  else
    mkdir -p "$seat_state" || die "cannot create the seat's private state at $seat_state"
    ENV_ARGS=(--env "BROKK_MACHINE_STATE_DIR=$seat_state" --env "BROKK_STATE_OVERRIDE=$seat_state")
  fi

  local ws_out ws
  ws_out="$(herdr workspace create --cwd "$clone" --label "$WORKSPACE_LABEL" --no-focus \
              "${ENV_ARGS[@]}" 2>/dev/null)" \
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

# ── durable and visible (the Allfather, 2026-11-06: "it should run in herdr so i can see it") ──
# A pane created by an ssh command dies with the session, and a headless agent is invisible. So the
# shape is two USER units: the herdr SERVER as a service (the panes outlive every client), and a
# keeper timer that re-raises the seat when it is gone. Nothing here takes the helm by itself —
# `ensure --primary` decides that, and refuses when a live primary holds the lock.
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
install_units() {
  local clone=$1 primary=$2
  mkdir -p "$UNIT_DIR" || die "cannot create $UNIT_DIR"
  cat >"$UNIT_DIR/herdr-server.service" <<UNIT
[Unit]
Description=herdr server — the panes outlive every client (the review seat lives in one)

[Service]
Type=simple
# A server already running is not a fault: the guard sleeps instead of starting a second one.
ExecStart=/bin/bash -lc 'herdr status server >/dev/null 2>&1 && exec sleep infinity || exec herdr server'
Restart=on-failure
RestartSec=15

[Install]
WantedBy=default.target
UNIT
  cat >"$UNIT_DIR/review-seat.service" <<UNIT
[Unit]
Description=review-seat keeper — ensure the reviewer's herdr seat exists (idempotent)

[Service]
Type=oneshot
WorkingDirectory=$clone
ExecStart=/usr/bin/env bash $ROOT/bin/forge/review-seat.sh ensure --clone $clone${primary:+ --primary}
UNIT
  cat >"$UNIT_DIR/review-seat.timer" <<UNIT
[Unit]
Description=review-seat keeper — every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
AccuracySec=20s
Unit=review-seat.service

[Install]
WantedBy=timers.target
UNIT
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable --now herdr-server.service >/dev/null 2>&1 || printf 'review-seat: WARNING — herdr-server.service did not start (a server may already be running; the guard sleeps in that case)\n' >&2
  systemctl --user enable --now review-seat.timer >/dev/null 2>&1 || die "the keeper timer could not be enabled ($UNIT_DIR/review-seat.timer)"
  printf 'units[4]{herdr_server,keeper_timer,clone,helm}:\n  "%s","%s","%s","%s"\n' \
    "$(systemctl --user is-active herdr-server.service 2>/dev/null | head -1)" \
    "$(systemctl --user is-active review-seat.timer 2>/dev/null | head -1)" \
    "$clone" "$([ -n "$primary" ] && echo primary || echo seat)"
}
unit_status() {
  printf 'units[3]{herdr_server,keeper_timer,next}:\n  "%s","%s","%s"\n' \
    "$(systemctl --user is-active herdr-server.service 2>/dev/null | head -1)" \
    "$(systemctl --user is-active review-seat.timer 2>/dev/null | head -1)" \
    "$(systemctl --user list-timers review-seat.timer --no-pager 2>/dev/null | sed -n '2p' | awk '{print $1, $2, $3}')"
}
uninstall_units() {
  systemctl --user disable --now review-seat.timer >/dev/null 2>&1 || true
  rm -f "$UNIT_DIR/review-seat.service" "$UNIT_DIR/review-seat.timer"
  systemctl --user daemon-reload 2>/dev/null || true
  printf 'units[2]{keeper_timer,state}:\n  "%s","removed (herdr-server.service left in place)"\n' "$UNIT_DIR/review-seat.timer"
}

case "${1-}" in
  --install-unit) shift || true; PRIMARY_ARG=""
                  while [ $# -gt 0 ]; do case "$1" in --primary) PRIMARY_ARG=1; shift ;; --clone) CLONE_ARG="${2:-}"; shift 2 ;; *) shift ;; esac; done
                  install_units "${CLONE_ARG:-$DEFAULT_CLONE}" "$PRIMARY_ARG"; exit 0 ;;
  --unit-status)  unit_status; exit 0 ;;
  --uninstall-unit) uninstall_units; exit 0 ;;
esac

ACTION="${1:-status}"; shift || true
case "$ACTION" in
  status)  cmd_status "$@" ;;
  ensure)  cmd_ensure "$@" ;;
  ask)     cmd_ask "$@" ;;
  charter) cmd_charter "$@" ;;
  close)   cmd_close "$@" ;;
  *) usage "unknown action '$ACTION' — status | ensure | ask | charter | close" ;;
esac
