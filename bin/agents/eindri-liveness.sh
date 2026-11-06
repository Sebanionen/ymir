#!/usr/bin/env bash
# eindri-liveness.sh — the sweep's second question: is the pane still a worker?
#
# `state/<id>.status` is a CLAIM. The pane is the EVIDENCE (plan 189 §18, plan 190
# §4.2). On 2026-11-05 three errands read `working` for most of a day while their
# panes held a shell or a crash: weaver-hook-and-ci at 26 h, telegram-fleet-shape
# and catalogue-the-doors-review with an empty prompt. Nothing compared the claim
# to the pane, so the fleet looked busy and was not.
#
# This door asks the question for every seat this machine launched:
#
#   a pane whose AGENT IS GONE, has EXITED with no terminal line, or CRASHED is DEAD
#
# and, at `sweep`, it CORRECTS the record — appending `failed: … pane <id> …` with
# the evidence — and hands the word to **Gná**, whose arm carries it to the seat
# (the one delivery ledger in bin/agents/eindri-wake-lib.sh, exactly once per seat).
# It is the ear Gná was missing: her first job is not to carry words but to notice
# that there are none.
#
# Usage:
#   eindri-liveness.sh check [<id> …]   judge only — prints rows, changes nothing
#   eindri-liveness.sh sweep [<id> …]   judge AND correct a DEAD seat's record
#   eindri-liveness.sh list             the seats this machine launched
#
# Exit: 0 every judged seat is alive · 3 a DEAD seat was found · 1 error · 2 usage.
#
# What it will NOT do:
#   · judge a seat whose status is already terminal (done/failed/needs-decision)
#     — a closed claim is not a claim of life;
#   · call a seat DEAD on a machine where the pane cannot be read at all
#     (no herdr, no tmux): that is UNKNOWN, printed with its reason, never a
#     false green and never a false alarm (RULES/25).
set -u
VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  for _c in "$SCRIPT_DIR/../vault/hoard-lib.sh" "$SCRIPT_DIR/hoard-lib.sh" "$SCRIPT_DIR/../../bin/vault/hoard-lib.sh"; do
    [ -r "$_c" ] && { . "$_c"; YMIR_HOARD_LIB_LOADED=1; break; }
  done
  unset _c
fi
hoard_state_dir YMIR_STATE_DIR
# The seat RECORDS are the HOUSE's, so they resolve from the hoard and never from
# the harness's own machine-state: a worker inherits BROKK_STATE_OVERRIDE pointing
# at ${XDG_STATE_HOME:-~/.local/state}/ymir/seats/<id>, which is pi's continuity
# dir — it holds no meta and no status, and honouring it here would make every
# sweep a silent no-op inside exactly the session that runs it.
STATE="$YMIR_STATE_DIR"
AGENTS_READER="$SCRIPT_DIR/../seat/herdr-agents.py"

. "$SCRIPT_DIR/eindri-wake-lib.sh"
EINDRI_STATE="$STATE"

case "${1-}" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help|"") sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
ACTION="${1:-check}"; shift || true

meta_field() {  # <file> <key> — one `key=value` line from a meta record
  sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1
}

last_status() {  # <id> — the seat's last claim, verbatim
  tail -n1 "$STATE/$1.status" 2>/dev/null || true
}

seats() {  # every id with a meta record, or the ones the caller named
  local f
  if [ $# -gt 0 ]; then printf '%s\n' "$@"; return 0; fi
  for f in "$STATE"/*.meta; do
    [ -f "$f" ] || continue
    basename "$f" .meta
  done
}

# --- the pane, read through the ONE door ------------------------------------
# herdr: bin/seat/herdr-agents.py (agents, not panes — a pane is not an agent);
# tmux: the pane's own foreground command.
herdr_agent() {  # <pane> <worktree> -> "pane\tstate\tcwd" when an agent stands there
  [ -r "$AGENTS_READER" ] || return 1
  command -v herdr >/dev/null 2>&1 || return 1
  python3 "$AGENTS_READER" --find --pane "$1" 2>/dev/null && return 0
  if [ -n "$2" ]; then python3 "$AGENTS_READER" --find --cwd "$2" 2>/dev/null && return 0; fi
  return 1
}

herdr_pane_exists() {  # <pane> — 0 when herdr still lists the pane at all
  command -v herdr >/dev/null 2>&1 || return 1
  herdr pane list 2>/dev/null | grep -q "\"pane_id\"[[:space:]]*:[[:space:]]*\"$1\""
}

tmux_window() {  # <window-id> -> the pane foreground commands in that window
  command -v tmux >/dev/null 2>&1 || return 1
  tmux list-panes -a -F '#{window_id} #{pane_current_command}' 2>/dev/null \
    | awk -v w="$1" '$1==w {print $2}'
}

# The verdict for one seat: ALIVE · DEAD · UNKNOWN · SKIP, with its evidence.
judge() {  # <id> -> "verdict\tevidence"
  local id=$1 claim backend pane wt hit state cmd
  claim="$(last_status "$id")"
  case "$claim" in
    '') printf 'SKIP\tno status line — nothing claims life\n'; return 0 ;;
    done:*|failed:*|needs-decision:*|paused:*)
        printf 'SKIP\tstatus is already terminal: %.60s\n' "$claim"; return 0 ;;
  esac
  backend="$(meta_field "$STATE/$id.meta" backend)"
  pane="$(meta_field "$STATE/$id.meta" window)"
  wt="$(meta_field "$STATE/$id.meta" worktree)"

  if [ "$backend" = tmux ]; then
    cmd="$(tmux_window "$pane")"
    if [ -z "$cmd" ]; then
      printf 'UNKNOWN\ttmux is not running or window %s is unreadable on this machine\n' "$pane"; return 0
    fi
    case "$cmd" in
      *bash|*zsh|*sh|*fish|*nu)
        printf 'DEAD\tthe pane holds a shell (%s), not an agent\n' "$(printf '%s' "$cmd" | head -1)"; return 0 ;;
      *)
        printf 'ALIVE\tthe pane is running %s\n' "$(printf '%s' "$cmd" | head -1)"; return 0 ;;
    esac
  fi

  # herdr — the ordinary road.
  if ! command -v herdr >/dev/null 2>&1; then
    printf 'UNKNOWN\therdr is not installed on this machine — the pane cannot be read\n'; return 0
  fi
  if hit="$(herdr_agent "$pane" "$wt")"; then
    state="$(printf '%s' "$hit" | cut -f2)"
    case "$state" in
      done|blocked|crashed|exited|error|failed)
        printf 'DEAD\tthe agent in %s is %s and left no terminal line\n' "$(printf '%s' "$hit" | cut -f1)" "$state"; return 0 ;;
      *)
        printf 'ALIVE\tagent %s in %s (%s)\n' "$state" "$(printf '%s' "$hit" | cut -f1)" "$claim"; return 0 ;;
    esac
  fi
  if herdr_pane_exists "$pane"; then
    printf 'DEAD\tthe pane %s holds no agent — a shell, an exit or a crash where a worker should stand\n' "$pane"
    return 0
  fi
  printf 'DEAD\tthe pane %s is gone, and no agent stands in %s\n' "$pane" "${wt:-the worktree}"
}

DEAD_FOUND=0
judged=0
judge_rows() {  # the loop `check` and `sweep` share
  local id verdict evidence
  for id in $(seats "$@"); do
    [ -n "$id" ] || continue
    IFS=$'\t' read -r verdict evidence <<<"$(judge "$id")"
    judged=$((judged + 1))
    printf '  "%s","%s","%s","%s"\n' "$id" "${verdict}" "$(meta_field "$STATE/$id.meta" window)" "$evidence"
    [ "$verdict" = DEAD ] && DEAD_FOUND=$((DEAD_FOUND + 1))
    if [ "$verdict" = DEAD ] && [ "$ACTION" = sweep ]; then
      correct "$id" "$evidence"
    fi
  done
}

correct() {  # <id> <evidence> — write the truth, then hand it to Gná, ONCE
  local id=$1 evidence=$2 claim ts line kind commits
  claim="$(last_status "$id")"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  # A seat that FINISHED is not a seat that failed. Measured 2026-11-05: an errand
  # committed its work and stopped without the terminal `eindri-acclaim`; the sweep
  # called it DEAD, which is the wrong word for a finished job. If the pane says
  # done and the worktree carries commits, the verdict is FINISHED.
  kind=failed
  commits="$(git -C "$(sed -n 's/^worktree=//p' "$STATE/$id.meta" 2>/dev/null | head -1)" rev-list --count origin/main..HEAD 2>/dev/null || echo 0)"
  case "$evidence" in
    *"is done and left no terminal line"*|*"holds no agent"*) [ "${commits:-0}" -gt 0 ] && kind=finished ;;
  esac
  # quote the last checkpoint: "where the work stood" beats "the pane went quiet"
  local cp=""
  cp="$(bash "$SCRIPT_DIR/eindri-checkpoint.sh" show "$id" 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: raise SystemExit(0)
print(f"last checkpoint: {d.get(chr(34)+chr(115)+chr(116)+chr(101)+chr(112)+chr(34),"?")} (next: {d.get(chr(34)+chr(110)+chr(101)+chr(120)+chr(116)+chr(34),"?")})")' 2>/dev/null)"
  if [ "$kind" = finished ]; then
    line="done: finished with $commits commit(s) and no terminal word — ${cp:-no checkpoint saved}; run eindri-acclaim to close it"
  else
    line="failed: the pane held no agent — $evidence (status claimed: ${claim})${cp:+ · $cp}"
  fi
  printf '%s\n' "$line" >>"$STATE/$id.status"
  printf 'liveness=dead corrected=%s evidence=%s\n' "$ts" "$evidence" >>"$STATE/$id.meta" 2>/dev/null || true
  eindri_is_delivered "$id" dead && return 0
  # quote the last checkpoint: "where the work stood" beats "the pane went quiet"
  local cp=""
  cp="$(bash "$SCRIPT_DIR/eindri-checkpoint.sh" show "$id" 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: raise SystemExit(0)
print(f"last checkpoint: {d.get(chr(34)+chr(115)+chr(116)+chr(101)+chr(112)+chr(34),"?")} (next: {d.get(chr(34)+chr(110)+chr(101)+chr(120)+chr(116)+chr(34),"?")})")' 2>/dev/null)"
  if [ "$kind" = finished ]; then
    eindri_queue_wake "seat $id FINISHED: $commits commit(s) in its worktree, pane done, no terminal word — review and close it"
  else
    eindri_queue_wake "seat $id is DEAD: $evidence (status said: ${claim}) — corrected at the sweep by bin/agents/eindri-liveness.sh"
  fi
  eindri_mark_delivered "$id" dead
}

printf 'liveness[%s]{seat,verdict,pane,evidence}:\n' "$(seats "$@" | grep -c . || true)"
judge_rows "$@" || true
if [ "$DEAD_FOUND" -gt 0 ] && [ "$ACTION" != sweep ]; then
  printf 'help: bin/agents/eindri-liveness.sh sweep — correct these records and wake the seat\n' >&2
  exit 3
fi
[ "$DEAD_FOUND" -gt 0 ] && exit 3
exit 0
