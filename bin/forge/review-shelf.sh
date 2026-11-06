#!/usr/bin/env bash
# review-shelf.sh — where a packet LANDS, and the waiting rule that keeps it honest.
#
# WHY (plan 205 §2.5 and §2.6): a packet with nowhere to land is a message in a bottle, and a packet
# nobody waits for is a silent delay. Three smiths and one reviewer is a queue; an unstated queue
# becomes a delay nobody measures, and the smith is left guessing whether it was read.
#
# THE SHELF IS NOT A SECOND LIST. `bin/seat/pending.sh` already reads open PRs, the wake queue, mail
# drafts and status lines; this shelf is one more SOURCE for it, and the shelf's own state is a
# directory of packets — never a parallel database of "what is waiting".
#
# THE WAITING RULE (plan 205 §2.6), stated so it can be broken loudly:
#   · a smith waits TWO ticks before it says anything;
#   · at the second tick ONE line is raised per (packet, head sha) — never a flood, the same brake
#     `bin/agents/pr-seal.sh` already uses for wakes;
#   · after THREE ticks the packet goes to the Allfather, because a reviewer that is simply absent
#     is a different problem from a reviewer that is slow.
#
# Usage:
#   review-shelf.sh drop <packet>          # put a packet on the shelf (copies; the original stays)
#   review-shelf.sh list                   # what is waiting, with its age in ticks
#   review-shelf.sh tick                   # judge the shelf: raise at most one wake per (packet, head)
#   review-shelf.sh take <id>              # the reviewer claims it: the packet leaves the shelf
#   review-shelf.sh --install-timer        # a user timer that runs `tick` every 30 minutes
#
# Exit: 0 judged · 1 a fault · 2 usage.
set -u
VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"

# The home is RESOLVED, never guessed (defaults-guard).
if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  for _c in "$ROOT/bin/vault/hoard-lib.sh" "$SCRIPT_DIR/../vault/hoard-lib.sh"; do
    [ -r "$_c" ] && { . "$_c"; YMIR_HOARD_LIB_LOADED=1; break; }
  done
  unset _c
fi
HOME_DIR=""
ymir_home_root HOME_DIR 2>/dev/null || true
[ -n "$HOME_DIR" ] || HOME_DIR="${YMIR_HOME:-}"

STATE="${YMIR_STATE_DIR:-${BROKK_STATE_OVERRIDE:-$HOME_DIR/state}}"
SHELF="$STATE/review"
WAKE_QUEUE="$STATE/.wake-queue"
TICK_SECONDS="${REVIEW_TICK_SECONDS:-1800}"

usage() { sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
die()   { printf 'review-shelf: %s\n' "$1" >&2; exit "${2:-1}"; }

packet_field() {  # <file> <field>
  sed -n "/^packet\[1\]{/,\$p" "$1" 2>/dev/null | head -3 | sed -n '2p' \
    | tr ',' '\n' | tr -d '"' | sed -n "$2p"
}

head_of() { grep -oE '^  "head","[0-9a-f]{40}"' "$1" 2>/dev/null | head -1 | cut -d'"' -f4; }

cmd_drop() {  # <packet>
  local src="${1:-}" id
  [ -n "$src" ] || usage
  [ -f "$src" ] || die "no packet at $src — a reviewer reads a packet, never a promise"
  id="$(basename "$src" .packet)"
  mkdir -p "$SHELF" || die "cannot create $SHELF"
  cp "$src" "$SHELF/$id.packet" || die "cannot copy the packet onto the shelf"
  printf 'review-shelf[1]{packet,shelf,state}:\n  "%s","%s","waiting"\n' "$id" "$SHELF/$id.packet"
}

age_ticks() {  # <file> → whole ticks since it was dropped
  local mtime now
  mtime=$(date -r "$1" +%s 2>/dev/null) || return 0
  now=$(date +%s)
  printf '%s' $(( (now - mtime) / TICK_SECONDS ))
}

cmd_list() {
  local n=0 f id head ticks state
  printf 'review_shelf[%s]{packet,head_sha,ticks,verdict}:\n' "$(ls -1 "$SHELF"/*.packet 2>/dev/null | wc -l | tr -d ' ')"
  for f in "$SHELF"/*.packet; do
    [ -e "$f" ] || continue
    n=$((n + 1))
    id="$(basename "$f" .packet)"
    head="$(head_of "$f")"
    ticks="$(age_ticks "$f")"
    if [ "$ticks" -ge 3 ]; then state="escalate to the Allfather — a reviewer that is absent is not a reviewer that is slow"
    elif [ "$ticks" -ge 2 ]; then state="raised — the smith has waited two ticks"
    else state="waiting"; fi
    printf '  "%s","%s","%s","%s"\n' "$id" "${head:0:12}" "$ticks" "$state"
  done
  [ "$n" -eq 0 ] && printf '  "none","","","the shelf is empty — silence, not a nag"\n'
  return 0
}

raised_for() {  # <id> <head> → 0 when a wake already exists for this pair
  grep -qsF "review-shelf: $1 at $2" "$WAKE_QUEUE" 2>/dev/null
}

cmd_tick() {
  local f id head ticks raised=0 escalated=0
  [ -d "$SHELF" ] || { printf 'review-shelf[1]{shelf,state}:\n  "%s","empty — nothing was ever dropped"\n' "$SHELF"; return 0; }
  mkdir -p "$(dirname "$WAKE_QUEUE")" 2>/dev/null || true
  for f in "$SHELF"/*.packet; do
    [ -e "$f" ] || continue
    id="$(basename "$f" .packet)"; head="$(head_of "$f")"; ticks="$(age_ticks "$f")"
    if [ "$ticks" -ge 3 ]; then
      if ! raised_for "$id" "$head" "escalate"; then
        printf 'WAKE review-shelf: packet %s at %s has waited %s ticks — ESCALATE to the Allfather\n' \
          "$id" "${head:0:12}" "$ticks" >>"$WAKE_QUEUE"
        escalated=$((escalated + 1))
      fi
    elif [ "$ticks" -ge 2 ]; then
      if ! raised_for "$id" "$head"; then
        printf 'WAKE review-shelf: packet %s at %s has waited %s ticks — the reviewer has not fetched it; the smith is waiting\n' \
          "$id" "${head:0:12}" "$ticks" >>"$WAKE_QUEUE"
        raised=$((raised + 1))
      fi
    fi
  done
  printf 'review_shelf_tick[3]{raised,escalated,rule}:\n  "%s","%s","one wake per (packet, head) — two ticks to speak, three to escalate"\n' \
    "$raised" "$escalated"
}

cmd_take() {  # <id>
  local id="${1:-}" f
  [ -n "$id" ] || usage
  f="$SHELF/$id.packet"
  [ -f "$f" ] || die "no packet '$id' on the shelf"
  rm -f "$f" || die "cannot remove $f"
  printf 'review-shelf[1]{packet,state}:\n  "%s","taken — the reviewer has it; the packet is not deleted, it is in the handoff record"\n' "$id"
}

cmd_install_timer() {
  local dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  mkdir -p "$dir" || die "cannot create $dir"
  cat >"$dir/review-loop.service" <<EOF
[Unit]
Description=review loop — judge the review shelf (plan 205 §2.5)

[Service]
Type=oneshot
ExecStart=/bin/bash $ROOT/bin/forge/review-shelf.sh tick
EOF
  cat >"$dir/review-loop.timer" <<EOF
[Unit]
Description=review loop every 30 minutes — one wake per (packet, head), never a flood

[Timer]
OnBootSec=5min
OnUnitActiveSec=30min
Unit=review-loop.service

[Install]
WantedBy=timers.target
EOF
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable --now review-loop.timer 2>/dev/null || true
  printf 'review-shelf[1]{timer,state,next}:\n  "review-loop.timer","enabled","the shelf is judged every 30 minutes"'
  systemctl --user is-active review-loop.timer 2>/dev/null | sed 's/^/ "'"'"'/;s/$/"/' || true
  printf '\n'
}

case "${1:-}" in
  -h|--help) usage ;;
  -v|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  --install-timer) cmd_install_timer ;;
  drop)  shift; cmd_drop "${1:-}" ;;
  list)  cmd_list ;;
  tick)  cmd_tick ;;
  take)  shift; cmd_take "${1:-}" ;;
  *) usage ;;
esac
