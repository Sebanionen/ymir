#!/usr/bin/env bash
# eindri-acclaim.sh — action half of the Eindri→Brokk wake bridge.
#
# Runs when the when-adapter fires on a stable `true`, AND as the WORKER'S OWN
# terminal act (the push path, plan 58 Phase 3): the smith calls it before it
# exits, it writes its report and appends the durable wake to state/.wake-queue.
# The arm only notifies; a finished errand wakes Brokk with no poller, no sweep,
# and no arm alive.
#
# It files the report durably (state/eindri-reports/<agent>.md), marks the
# delivery on the ONE shared ledger (state/eindri-delivered/<agent>.<kind> — see
# bin/agents/eindri-wake-lib.sh, so the failsafe sweep never re-fires the same news),
# appends the wake, and sounds the desktop note. Idempotent via the ledger.
#
# The worker's terminal act may be one command — the status append and the shelf
# are done here so neither can be skipped:
#   bin/agents/eindri-acclaim.sh <agent> --terminal done --line "<one-line report>"
#
# Usage: bin/agents/eindri-acclaim.sh <agent> [<worktree-root>] [--terminal done|failed|needs-decision] [--line "<text>"]
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${BROKK_ROOT_OVERRIDE:-$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)}"

# The roots that live OUTSIDE the code tree: this machine's records and the
# runtime state belong to the home the operator chose at installation, never in
# the tree — a packaged install replaces its tree on upgrade (Rule 04).
if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  _yr="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  for _yc in "$_yr/hoard-lib.sh" "$_yr/../vault/hoard-lib.sh" "$_yr/../../vault/hoard-lib.sh"; do
    [ -r "$_yc" ] && { . "$_yc"; YMIR_HOARD_LIB_LOADED=1; break; }
  done
  unset _yr _yc
fi
hoard_state_dir YMIR_STATE_DIR
hoard_data_dir YMIR_DATA_DIR
STATE="${BROKK_STATE_OVERRIDE:-$YMIR_STATE_DIR}"

. "$SCRIPT_DIR/eindri-wake-lib.sh"
EINDRI_STATE="$STATE"

AGENT=""
WORKTREE=""
TERMINAL=""
LINE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --terminal) TERMINAL="${2-}"; shift 2 ;;
    --terminal=*) TERMINAL=${1#--terminal=}; shift ;;
    --line) LINE="${2-}"; shift 2 ;;
    --line=*) LINE=${1#--line=}; shift ;;
    -h|--help)
      printf 'usage: bin/agents/eindri-acclaim.sh <agent> [<worktree-root>] [--terminal done|failed|needs-decision] [--line "<text>"]\n'
      exit 0 ;;
    -v|-V|--version) printf '1.0.0\n'; exit 0 ;;
    -*) printf 'error: unknown flag %s\nhelp: bin/agents/eindri-acclaim.sh <agent> [<worktree-root>] [--terminal done|failed|needs-decision] [--line "<text>"]\n' "$1" >&2; exit 2 ;;
    *)
      if [ -z "$AGENT" ]; then AGENT=$1
      elif [ -z "$WORKTREE" ]; then WORKTREE=$1
      else printf 'error: too many positional arguments\nhelp: bin/agents/eindri-acclaim.sh <agent> [<worktree-root>]\n' >&2; exit 2
      fi
      shift ;;
  esac
done
[ -n "$AGENT" ] || { printf 'usage: bin/agents/eindri-acclaim.sh <agent> [<worktree-root>] [--terminal done|failed|needs-decision] [--line "<text>"]\n' >&2; exit 2; }
case "$TERMINAL" in
  ''|done|failed|needs-decision) ;;
  *) printf 'error: --terminal must be done|failed|needs-decision (got %s)\n' "$TERMINAL" >&2; exit 2 ;;
esac

mkdir -p "$STATE/eindri-reports" "$STATE/eindri-questions" "$STATE/eindri-done"

# 1. The worker's own terminal act, when it passes its line: append the status
#    line and file the shelf as ONE act, so neither half is ever deferred. Done
#    before delivery so the same shelf the failsafe sweeps is what gets queued.
if [ -n "$TERMINAL" ] && [ -n "$LINE" ]; then
  status_file="$STATE/$AGENT.status"
  last="$(tail -n1 "$status_file" 2>/dev/null || true)"
  [ "$last" = "$TERMINAL: $LINE" ] || printf '%s: %s\n' "$TERMINAL" "$LINE" >>"$status_file"
  case "$TERMINAL" in
    needs-decision) shelf="$STATE/eindri-questions/$AGENT.md" ;;
    *)              shelf="$STATE/eindri-reports/$AGENT.md" ;;
  esac
  [ -s "$shelf" ] || printf '%s\n' "$LINE" >"$shelf"
fi

# 2. Kind and detail from the shelves (a question outranks a report — the smith
#    is blocked and needs an answer, not a review).
kind="reported"
detail=""
corrected=0
if [ -f "$STATE/eindri-questions/$AGENT.md" ]; then
  kind="QUESTION"
  detail="QUESTION at state/eindri-questions/$AGENT.md — answer with bin/agents/eindri-send.sh $AGENT \"…\""
elif [ -f "$STATE/eindri-reports/$AGENT.md" ]; then
  # The shelf may be the SWEEP's snapshot rather than the worker's word: a liveness
  # pass files "# <id> — finished without a terminal word" when it finds a quiet
  # pane. That was a GUESS, and a guess must not outlive the evidence that corrects
  # it — measured 2026-11-06, when a live errand was judged dead at 3m59s, the sweep
  # filed its snapshot, the once-only `report` mark was spent on it, and the worker's
  # own terminal word could neither heal the shelf nor raise a wake. So: a shelf
  # carrying the sweep's header and nothing better is replaced by the terminal word,
  # and the correction travels as its own kind so the spent `report` cannot mute it.
  if grep -q ' — finished without a terminal word' "$STATE/eindri-reports/$AGENT.md" 2>/dev/null; then
    last="$(tail -n1 "$STATE/$AGENT.status" 2>/dev/null || true)"
    case "$last" in
      done:*|failed:*)
        printf '%s\n' "$last" >"$STATE/eindri-reports/$AGENT.md"
        detail="report healed from the terminal status line, replacing the sweep's snapshot (state/eindri-reports/$AGENT.md)"
        corrected=1 ;;
      *)
        detail="report filed at state/eindri-reports/$AGENT.md (the sweep's snapshot; no terminal word yet)" ;;
    esac
  else
    detail="report filed at state/eindri-reports/$AGENT.md"
  fi
else
  # No shelf. A terminal status line IS a report (the worker wrote one shelf and
  # died before the other): heal the report shelf from it, so the two roads read
  # one ground and nothing is stranded.
  last="$(tail -n1 "$STATE/$AGENT.status" 2>/dev/null || true)"
  case "$last" in
    done:*|failed:*)
      printf '%s\n' "$last" >"$STATE/eindri-reports/$AGENT.md"
      detail="report healed from the terminal status line (state/eindri-reports/$AGENT.md)" ;;
    needs-decision:*)
      kind="QUESTION"
      printf '%s\n' "$last" >"$STATE/eindri-questions/$AGENT.md"
      detail="question healed from the terminal status line (state/eindri-questions/$AGENT.md)" ;;
    *)
      if [ -n "$WORKTREE" ] && [ -f "$WORKTREE/REPORT.md" ]; then
        cp "$WORKTREE/REPORT.md" "$STATE/eindri-reports/$AGENT.md" 2>/dev/null || true
        detail="report filed from $WORKTREE/REPORT.md (state/eindri-reports/$AGENT.md)"
      else
        detail="left working (herdr state flipped; read the pane: herdr agent read $AGENT)"
      fi ;;
  esac
fi

# 3. Deliver exactly once, on the shared ledger. The poller and the sweep are
#    the same road: whoever arrives first writes the wake, the other stands down.
wake_kind=report
[ "$kind" = "QUESTION" ] && wake_kind=question
[ "$corrected" = 1 ] && wake_kind=corrected
if eindri_is_delivered "$AGENT" "$wake_kind"; then
  detail="$detail (already delivered — no duplicate wake)"
else
  if [ "$kind" = "QUESTION" ]; then
    eindri_queue_wake "eindri $AGENT QUESTION: $STATE/eindri-questions/$AGENT.md — answer with bin/agents/eindri-send.sh $AGENT \"…\""
  elif [ "$corrected" = 1 ]; then
    eindri_queue_wake "eindri $AGENT CORRECTED: the sweep's snapshot was a guess — $detail"
  else
    eindri_queue_wake "eindri $AGENT reported: $detail"
  fi
  eindri_mark_delivered "$AGENT" "$wake_kind"
  if [ -x "$SCRIPT_DIR/../../systems/snotra/services/tts-lease/ymir-say.sh" ]; then
    if [ "$kind" = "QUESTION" ]; then
      "$SCRIPT_DIR/../../systems/snotra/services/tts-lease/ymir-say.sh" alarm "Eindri $AGENT asks — answer it" >/dev/null 2>&1 || true
    else
      "$SCRIPT_DIR/../../systems/snotra/services/tts-lease/ymir-say.sh" note "Eindri $AGENT reported" >/dev/null 2>&1 || true
    fi
  fi
fi
# 4. The review spine (FORSETI the Judge). The delivery gate's other half: a
#    ship errand that reached `done` with a PR wakes its own reviewer. One per
#    task (the .reviewed marker); YMIR_AUTO_REVIEW=off is the loud override; a
#    failed spawn is a loud wake, never silence.
if [ "$TERMINAL" = done ] && [ -x "$SCRIPT_DIR/eindri-review-spawn.sh" ]; then
  if _rv_out="$("$SCRIPT_DIR/eindri-review-spawn.sh" "$AGENT" 2>&1)"; then
    printf '%s\n' "$_rv_out"
  else
    _rv_rc=$?
    printf '%s\n' "$_rv_out" >&2
    if [ ! -f "$STATE/.reviewed/$AGENT.failed" ]; then
      mkdir -p "$STATE/.reviewed" 2>/dev/null || true
      printf '%s\n' "$_rv_out" >"$STATE/.reviewed/$AGENT.failed" 2>/dev/null || true
      eindri_queue_wake "eindri $AGENT review spawn FAILED (rc=$_rv_rc): $(printf '%s' "$_rv_out" | grep -m1 . || true)"
      if [ -x "$SCRIPT_DIR/../../systems/snotra/services/tts-lease/ymir-say.sh" ]; then
        "$SCRIPT_DIR/../../systems/snotra/services/tts-lease/ymir-say.sh" alarm "Forseti's review spawn failed for $AGENT" >/dev/null 2>&1 || true
      fi
    fi
  fi
fi
printf 'eindri-acclaim[1]{agent,kind,detail}:\n  "%s","%s","%s"\n' "$AGENT" "$kind" "$detail"
