#!/usr/bin/env bash
# saga-wake-drain.sh - present durable Brokk wakes, or acknowledge them.
#
# Sága sees the queue. `drain` (default) prints each durable wake; `ack` drops
# the queues once the wakes have been handled. Ported/trimmed from the upstream
# wake-drain contract for plan 29.
#
# Usage: saga-wake-drain.sh [drain|ack]
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${BROKK_ROOT_OVERRIDE:-$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)}"
BROKK_HOME="${BROKK_HOME:-$ROOT}"
# The queue lives in the OPERATOR's state, never the code tree (Rule 04). Resolve
# it exactly as every shell tool does, so a standalone drain sees the same queue
# the watcher fills. It once defaulted to $BROKK_HOME/state (the TREE) and
# reported "0 pending" while the hoard queue held unhandled wakes (2026-09-23).
if [ -z "${BROKK_STATE_OVERRIDE:-}" ]; then
  if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
    for _c in "$SCRIPT_DIR/../vault/hoard-lib.sh" "$SCRIPT_DIR/../vault/hoard-lib.sh" "$SCRIPT_DIR/../../vault/hoard-lib.sh"; do
      [ -r "$_c" ] && { . "$_c"; YMIR_HOARD_LIB_LOADED=1; break; }
    done
    unset _c
  fi
  hoard_state_dir _HS 2>/dev/null && BROKK_STATE_OVERRIDE="$_HS"
  unset _HS
fi
STATE="${BROKK_STATE_OVERRIDE:-$BROKK_HOME/state}"

mkdir -p "$STATE"
QUEUE="$STATE/.wake-queue"
# The FM runner's own durable queue (its published check-wakes) lives under the
# .agents home, not the main state. The watcher hollers on BOTH doors; a drain
# that reads only one lets strikes hide in the other. Combine them here.
FMQ="$SCRIPT_DIR/../../state/procevent/.wake-queue"

case "${1:-drain}" in
  -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  ack|--ack)
    # Consume EXACTLY what the last drain PRESENTED — never a wake that arrived
    # after it. The old full-truncate ate undrained wakes (the ack race) and let
    # the sweep's re-presentation ring with an empty hand — the ghost wakes the
    # Allfather saw. A multiset diff: handled lines leave, newer lines stay.
    python3 - "$QUEUE" "$FMQ" "$STATE/.wake-drained" "$STATE/.wake-fmq-drained" <<'PY' 2>/dev/null || true
import os, sys, collections
queue, fmq, qsnap, fsnap = sys.argv[1:5]
def consume(path, snap):
    if not os.path.exists(snap) or not os.path.exists(path):
        return  # no presentation record — nothing consumed from this door
    lines = open(path).read().splitlines()
    cnt = collections.Counter(open(snap).read().splitlines())
    out = []
    for l in lines:
        if cnt.get(l, 0) > 0:
            cnt[l] -= 1
        else:
            out.append(l)
    if out:
        open(path, "w").write("\n".join(out) + "\n")
    else:
        os.remove(path)
consume(queue, qsnap)
consume(fmq, fsnap)
for snap in (qsnap, fsnap):
    if os.path.exists(snap):
        os.remove(snap)
PY
    # The flood-brake hash clears only when both doors are truly empty, so a
    # later terminal wake signals cleanly; preserved newer wakes keep it set.
    if [ ! -s "$QUEUE" ] && { [ ! -f "$FMQ" ] || [ ! -s "$FMQ" ]; }; then
      rm -f "$STATE/.wake-last-hash" 2>/dev/null || true
      printf 'wake queue: acknowledged (0 pending)\n'
    else
      printf 'wake queue: acknowledged handled wakes; newer wakes preserved\n'
    fi
    exit 0
    ;;
  drain|--drain|"") ;;
  *) printf 'error: unknown action %s\nhelp: saga-wake-drain.sh [drain|ack]\n' "$1" >&2; exit 2 ;;
esac

if [ -s "$FMQ" ]; then
  printf 'FM wake queue: %s pending (fm-queued wakes below)\n' "$(awk 'END{print NR}' "$FMQ")"
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] && printf 'WAKE %s\n' "$line"
  done <"$FMQ"
  printf 'FM_ACK_REQUIRED: acknowledge handled fm wakes to drop them from the fm queue\n'
fi

if [ ! -s "$QUEUE" ]; then
  printf 'wake queue: 0 pending\n'
else
  # Count LINES, not newlines: the door is judged non-empty by `[ -s ]`, so a queue
  # holding one unterminated line must present that line too. `wc -l` said 0 for
  # exactly that file, while the extension read the same door as non-empty and
  # re-presented one week-old wake at every turn boundary (2026-10-24).
  count=$(awk 'END{print NR}' "$QUEUE")
  printf 'wake queue: %s pending\n' "${count:-0}"
  dropped=0
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    # A wake is presented until Brokk acks it. The errand's status (done/failed)
    # does NOT make it an echo: a self-finishing worker's terminal wake is the
    # FIRST notice Brokk gets, and dropping it on status makes the worker invisible
    # (plan 137). Echoes from Brokk closing his own errand are still presented once
    # and cleared by `ack` — harmless noise, not a reason to drop the real news.
    printf 'WAKE %s\n' "$line"
  done <"$QUEUE"
  [ "${dropped:-0}" -gt 0 ] && printf 'wake_echo[1]{dropped,why}:\n  %s,"errands already closed — ack clears them, they are not presented as news"\n' "$dropped"
  printf 'WAKE_ACK_REQUIRED: acknowledge handled wakes to drop them from the queue\n'
  # THE OPEN WORK, every wake — not only the morning brief. One line, so a wake says not
  # just "something happened" but "and here is what still stands unmade".
  OW="$SCRIPT_DIR/../records/open-work.sh"
  if [ -x "$OW" ]; then
    ow_json="$("$OW" --json 2>/dev/null)"
    printf '%s' "$ow_json" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: raise SystemExit(0)
from collections import Counter
items=d.get("items",[])
if not items: raise SystemExit(0)
c=Counter(i.get("state","open") for i in items)
print(f"OPEN WORK: {len(items)} item(s) — " + " · ".join(f"{k} {v}" for k,v in sorted(c.items())) + " · bin/records/open-work.sh --md")' 2>/dev/null
  fi
fi

# Snapshot exactly what this drain presented, so ack consumes these lines and
# never a wake that arrives later (the ack race). An empty door clears its
# snapshot — nothing was presented to consume.
if [ -s "$QUEUE" ]; then cp "$QUEUE" "$STATE/.wake-drained" 2>/dev/null; else rm -f "$STATE/.wake-drained"; fi
if [ -s "$FMQ" ]; then cp "$FMQ" "$STATE/.wake-fmq-drained" 2>/dev/null; else rm -f "$STATE/.wake-fmq-drained"; fi

# Open-decision markers (approval gates) left unhandled.
decisions=$(find "$STATE" -maxdepth 1 -name '*.decision' 2>/dev/null | wc -l | tr -d '[:space:]')
printf 'open decisions: %s\n' "${decisions:-0}"
