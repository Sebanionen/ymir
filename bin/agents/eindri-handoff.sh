#!/usr/bin/env bash
# eindri-handoff.sh — the handoff failsafe. An Eindri's work ALWAYS reaches Brokk.
#
# The fast road is the when-adapter (eindri-seen.sh → eindri-acclaim.sh, driven
# by .agents/backend/fm-procevent.sh). It is good, and it can fail four ways we
# have actually seen:
#
#   1. the poller is not running           → nothing fires, ever
#   2. the arm wrote its spec into a
#      worktree instead of the hoard       → written, then deleted
#   3. nobody looked                       → the report sat on the shelf
#   4. the worker wrote the wrong shelf    → the status line was not swept
#
# A handoff that depends on one poller alive is not a handoff. This is the SLOW
# road that cannot be missed: it sweeps the report and question shelves for
# anything NOT yet delivered to Brokk and puts it in the wake queue, so Sága's
# drain surfaces it in the very next session digest. It is idempotent — the ONE
# shared delivery ledger (bin/agents/eindri-wake-lib.sh) marks each item, so a second
# sweep never re-fires old news and the poller's acclaim never doubles a wake.
#
#   eindri-handoff.sh sweep     # deliver everything undelivered (the failsafe)
#   eindri-handoff.sh status    # what is waiting, without delivering
#
# Exit: 0 nothing waited (or all delivered), 3 something WAS waiting and is now
# delivered, 1 error, 2 usage. `3` means "there was a miss, and it is fixed".
set -u

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  for _c in "$SCRIPT_DIR/../vault/hoard-lib.sh" "$SCRIPT_DIR/../vault/hoard-lib.sh" "$SCRIPT_DIR/../../vault/hoard-lib.sh"; do
    [ -r "$_c" ] && { . "$_c"; YMIR_HOARD_LIB_LOADED=1; break; }
  done
fi
hoard_state_dir YMIR_STATE_DIR
STATE="${BROKK_STATE_OVERRIDE:-$YMIR_STATE_DIR}"

. "$SCRIPT_DIR/eindri-wake-lib.sh"
EINDRI_STATE="$STATE"
QUEUE="$STATE/.wake-queue"

case "${1-}" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help|"") sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
ACTION="${1:-sweep}"; shift || true

mkdir -p "$STATE/eindri-reports" "$STATE/eindri-questions" "$STATE/eindri-delivered" 2>/dev/null || true

# The shelf an item sits on, its name, and the kind the wake should carry.
# A question needs an ANSWER; a report needs a REVIEW. They never share a marker.
# ── the third shelf: a seat that FINISHED but never said so ───────────────────
#
# The fast road needs the worker to call `eindri-acclaim.sh` as its terminal act.
# Measured 2026-11-05: an errand committed its work and stopped; its `.status` still
# read "working: launched …" and the pane said `done`. Nothing raised a line — the
# arm was healthy, the worker simply never spoke. This detects that state from the
# two facts that are always true instead of from the one that must be remembered:
# the pane's own status, and commits in the worktree.
finished_silently() {  # prints "<id>	<commits>	<pane>" for each silent finish
  local st id meta wt pane commits
  command -v herdr >/dev/null 2>&1 || return 0
  for meta in "$STATE"/*.meta; do
    [ -f "$meta" ] || continue
    id="$(basename "$meta" .meta)"
    # the meta carries `seat_state` (unknown|working|done|failed) and `window` (the pane),
    # NOT `state`/`pane` — a detector reading the wrong keys finds nothing and says nothing
    st="$(sed -n 's/^seat_state=//p' "$meta" 2>/dev/null | head -1)"
    case "$st" in done|failed|needs-decision) continue ;; esac
    wt="$(sed -n 's/^worktree=//p' "$meta" 2>/dev/null | head -1)"
    [ -n "$wt" ] && [ -d "$wt" ] || continue
    pane="$(sed -n 's/^window=//p' "$meta" 2>/dev/null | head -1)"
    [ -n "$pane" ] || pane="$(sed -n 's/^pane=//p' "$meta" 2>/dev/null | head -1)"
    [ -n "$pane" ] || continue
    # the pane's own word: an agent that is gone or done, not one still working
    pane_status="$(herdr agent list 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: raise SystemExit(0)
want=sys.argv[1]
for a in (d.get("result") or {}).get("agents") or []:
    if a.get("pane_id")==want:
        print(a.get("agent_status") or ""); break
' "$pane" 2>/dev/null)"
    case "$pane_status" in
      done|idle|"") ;;
      *) continue ;;
    esac
    commits="$(git -C "$wt" rev-list --count origin/main..HEAD 2>/dev/null || echo 0)"
    printf '%s\t%s\t%s\t%s\n' "$id" "$commits" "$pane" "$pane_status"
  done
}

waiting_items() {
  local f name
  for f in "$STATE/eindri-questions"/*.md; do
    [ -f "$f" ] || continue
    name="$(basename "$f" .md)"
    eindri_is_delivered "$name" question && continue
    printf 'QUESTION\t%s\t%s\n' "$name" "$f"
  done
  for f in "$STATE/eindri-reports"/*.md; do
    [ -f "$f" ] || continue
    name="$(basename "$f" .md)"
    eindri_is_delivered "$name" report && continue
    printf 'REPORT\t%s\t%s\n' "$name" "$f"
  done
}

count_waiting() { waiting_items | grep -c . || true; }

deliver() {  # <kind> <name> <path>
  local kind=$1 name=$2 path=$3 wake_kind line
  case "$kind" in
    QUESTION) wake_kind=question
              line="eindri $name QUESTION: $path — answer with bin/agents/eindri-send.sh $name \"…\" (handoff failsafe)" ;;
    *)        wake_kind=report
              line="eindri $name reported: report filed at $path (handoff failsafe)" ;;
  esac
  eindri_queue_wake "$line"
  eindri_mark_delivered "$name" "$wake_kind"
  if [ -x "$SCRIPT_DIR/../../systems/snotra/services/tts-lease/ymir-say.sh" ]; then
    [ "$kind" = "QUESTION" ] && "$SCRIPT_DIR/../../systems/snotra/services/tts-lease/ymir-say.sh" alarm "Eindri $name asks — answer it" >/dev/null 2>&1 \
                            || "$SCRIPT_DIR/../../systems/snotra/services/tts-lease/ymir-say.sh" note "Eindri $name reported" >/dev/null 2>&1
  fi
}

case "$ACTION" in
  status)
    n="$(count_waiting)"
    printf 'eindri-handoff[1]{action,waiting,state}:\n  "status",%s,"%s"\n' \
      "$n" "$([ "$n" -gt 0 ] && echo 'undelivered work on the shelf' || echo 'nothing waiting')"
    waiting_items | while IFS=$'\t' read -r k a p; do printf '  "%s","%s","%s"\n' "$k" "$a" "$p"; done
    [ "$n" -gt 0 ] && exit 3
    exit 0 ;;

  sweep|"")
    delivered=0
    dead_seats=0
    seal_ready=0
    # The SECOND question comes first: before delivering what the shelves hold,
    # cross-check every live claim against its pane. A seat whose pane holds a
    # shell has no report to deliver and never will, and its status says
    # `working` — the fault plan 189 §18 measured for a whole day. This door
    # corrects the record and hands the word to Gná (bin/agents/eindri-liveness.sh),
    # so the sweep wakes the seat about the silence as well as about the news.
    # A seat that finished and never said so: file its report from the two facts that
    # are always true (the pane's status and its commits), then let the shelf deliver it.
    while IFS=$'\t' read -r sid scommits spane sstate; do
      [ -n "$sid" ] || continue
      latest="$(git -C "$STATE/../.." --version >/dev/null 2>&1; true)"
      report="$STATE/eindri-reports/$sid.md"
      if [ ! -f "$report" ]; then
        {
          printf '# %s — finished without a terminal word\n\n' "$sid"
          printf -- '- pane: %s (agent status: %s)\n' "$spane" "$sstate"
          printf -- '- commits ahead of origin/main: %s\n' "$scommits"
          printf -- '- detected by: eindri-handoff.sh sweep (the arm cycle)\n'
          printf -- '- the worker never ran eindri-acclaim.sh, so the status still read working\n'
        } >"$report" 2>/dev/null || continue
      fi
      sed -i "s/^seat_state=.*/seat_state=done/" "$STATE/$sid.meta" 2>/dev/null || true
      sed -i "s/^state=.*/state=done/" "$STATE/$sid.meta" 2>/dev/null || true
    done < <(finished_silently)

    if [ -x "$SCRIPT_DIR/eindri-liveness.sh" ]; then
      liveness_out="$("$SCRIPT_DIR/eindri-liveness.sh" sweep 2>&1)"
      liveness_rc=$?
      [ -n "$liveness_out" ] && printf '%s\n' "$liveness_out"
      [ "$liveness_rc" = 3 ] && dead_seats=$((dead_seats + 1))
    fi
    # The THIRD question: is a PR of this seat ready to be sealed? The seal itself
    # is the seat's act (bin/agents/pr-seal.sh seal <n>), never the sweep's — but
    # the arm's road must be walked every sweep, or the word that a PR is green
    # waits for a human to run a command he does not know about.
    if [ -x "$SCRIPT_DIR/pr-seal.sh" ]; then
      seal_out="$("$SCRIPT_DIR/pr-seal.sh" watch --quiet 2>&1)"
      seal_rc=$?
      [ -n "$seal_out" ] && printf '%s\n' "$seal_out"
      [ "$seal_rc" = 3 ] && seal_ready=1
    fi
    # Collect first, then deliver — a marker written mid-iteration would shift
    # the glob under us.
    while IFS=$'\t' read -r kind name path; do
      [ -n "${kind:-}" ] || continue
      deliver "$kind" "$name" "$path"
      delivered=$((delivered + 1))
    done < <(waiting_items)

    printf 'eindri-handoff[2]{action,delivered,dead,state}:\n  "sweep",%s,%s,"%s"\n' \
      "$delivered" "$dead_seats" \
      "$([ "$delivered" -gt 0 ] && echo 'undelivered work was waiting — now in the wake queue' || echo 'nothing was waiting')"
    [ "$delivered" -gt 0 ] && exit 3
    [ "$dead_seats" -gt 0 ] && exit 3
    [ "$seal_ready" = 1 ] && exit 3
    exit 0 ;;

  *)
    printf 'error: unknown action %s (sweep|status)\n' "$ACTION" >&2; exit 2 ;;
esac
