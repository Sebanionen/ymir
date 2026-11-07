#!/usr/bin/env bash
# seat-wire.sh — one seat speaks into another seat's live pane, and says who it is.
#
#   bin/seat/seat-wire.sh seats                 # the peers, with reachability
#   bin/seat/seat-wire.sh who <seat>            # the far side's own answer: host · primary · pane · session
#   bin/seat/seat-wire.sh read <seat> [--lines N]   # the peer's pane tail
#   bin/seat/seat-wire.sh say <seat> "<line>"   # deliver one attributed line into the peer's live agent
#   bin/seat/seat-wire.sh wait <seat> [--timeout MS]  # block until the peer leaves `working`
#   bin/seat/seat-wire.sh nudge <seat> "<line>"  # append one attributed line to the peer's wake queue
#
# Law (plan 189):
#   * a wire line is a PEER's word — never the Allfather's, never a grant; the far seat may refuse;
#   * the pane is resolved LIVE from `herdr agent list`, never from a stored id;
#   * every refusal is loud and named — nothing falls back to a plausible-looking target;
#   * the room is written FIRST (hodd/rooms/<room>/<seat>.jsonl), so a spoken word always leaves a trace.
#
# Registry (private, in the home — never an address in this repo):
#   hodd/identity/seats.yaml
#     seats:
#       <seat>: { primary: <Name>, machine: { host: <tailnet-host>, ssh_user: <user> } }
# An unresolvable part is reported as a clean skip with its reason (RULES/25), never guessed.
set -u

SELF="$(basename "$0")"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"

say() { printf '%s\n' "$*"; }
die() { printf '%s: %s\n' "$SELF" "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# The home is RESOLVED through the one resolver, never restated (Rule 07): ten scripts
# once carried their own default, and defaults-guard refused the eleventh — correctly.
# A file may be literal-free and still not know where anything is, so the resolver is
# CALLED, not merely mentioned.
# shellcheck source=bin/vault/hoard-lib.sh
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
HOME_DIR=""
if have ymir_home_root; then ymir_home_root HOME_DIR; fi
[ -n "$HOME_DIR" ] || die "the home does not resolve — bin/vault/hoard-lib.sh names it (YMIR_HOME, or the machine's recorded choice)"

SEATS_YAML="$HOME_DIR/hodd/identity/seats.yaml"
ROOM="${SEAT_ROOM:-the-fleet}"
SSH_TIMEOUT="${SEAT_SSH_TIMEOUT:-6}"
# SEAT_HOME is the TEST door: resolve a peer's home from this LOCAL directory instead
# of over ssh, so a refusal can be proven without touching the peer.
SEAT_HOME="${SEAT_HOME:-}"

have ssh || die "ssh not found — the wire rides ssh over the tailnet"

# --- the registry -------------------------------------------------------------------
# Prints one line per seat: <seat> TAB <primary> TAB <host> TAB <ssh_user>
registry_rows() {
  [ -r "$SEATS_YAML" ] || return 0
  python3 - "$SEATS_YAML" <<'PY'
import sys
try:
    import yaml
except Exception:
    sys.exit(0)
try:
    d = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
except Exception:
    sys.exit(0)
for name, seat in (d.get("seats") or {}).items():
    if not isinstance(seat, dict):
        continue
    machine = seat.get("machine") or {}
    host = (machine.get("host") or "").strip()
    user = (machine.get("ssh_user") or "").strip()
    primary = (seat.get("primary") or "").strip()
    if host and user:
        print(f"{name}\t{primary}\t{host}\t{user}")
PY
}

row_of() {
  local want="$1" name primary host user
  while IFS=$'\t' read -r name primary host user; do
    [ "$name" = "$want" ] && { printf '%s\t%s\t%s\t%s\n' "$name" "$primary" "$host" "$user"; return 0; }
  done <<EOF
$(registry_rows)
EOF
  return 1
}

self_seat() {
  local f="$HOME/.pi/agent/extensions/.ymir-seat"
  [ -r "$f" ] || return 1
  sed -n 's/^host=//p' "$f" | head -1
}

# Work out the ssh destination for a seat. The tailnet IP is resolved first so a LAN
# hostname that also exists on the operator's network can never be picked by mistake.
resolve_dest() {
  local host="$1" user="$2" ip
  ip="$(tailscale ip -4 "$host" 2>/dev/null | head -1 || true)"
  [ -n "$ip" ] && { printf '%s@%s' "$user" "$ip"; return 0; }
  printf '%s@%s' "$user" "$host"
}

remote() { # remote <dest> <command…>
  local dest="$1"; shift
  ssh -n -o BatchMode=yes -o ConnectTimeout="$SSH_TIMEOUT" -o StrictHostKeyChecking=accept-new \
    "$dest" "$@" 2>&1
}

# --- verbs ---------------------------------------------------------------------------
cmd_seats() {
  local name primary host user dest reach seat_primary
  local found=0
  printf 'seats[%s]{seat,primary,reachable,door}:\n' "$(registry_rows | wc -l | tr -d ' ')"
  while IFS=$'\t' read -r name primary host user; do
    [ -n "$name" ] || continue
    found=1
    dest="$(resolve_dest "$host" "$user")"
    if remote "$dest" true >/dev/null 2>&1; then reach=up; else reach=unreachable; fi
    printf '  "%s","%s","%s","ssh %s"\n' "$name" "$primary" "$reach" "$dest"
  done <<EOF
$(registry_rows)
EOF
  [ "$found" = 1 ] || say 'seats[0]{reason}:
  "no peer carries a machine{} block in hodd/identity/seats.yaml — the registry names the seat, not its door"'
}

cmd_who() {
  local seat="${1:-}"
  [ -n "$seat" ] || die "usage: $SELF who <seat>"
  local row name primary host user dest out
  row="$(row_of "$seat")" || die "unknown seat '$seat' — it carries no machine{host,ssh_user} in $SEATS_YAML"
  IFS=$'\t' read -r name primary host user <<EOF
$row
EOF
  dest="$(resolve_dest "$host" "$user")"
  out="$(remote "$dest" bash -lc "'hostname; sed -n \"s/^primary=//p\" ~/.pi/agent/extensions/.ymir-seat 2>/dev/null; herdr agent list 2>/dev/null'")" \
    || die "peer unreachable — $out"
  case "$out" in
    *Agent*d*) : ;;
  esac
  WHO_OUT="$out" PEER="$name" EXPECT="$primary" python3 - <<'PY' || exit 3
import json, os, sys
raw = os.environ.get("WHO_OUT", "")
peer = os.environ.get("PEER", "")
expect = os.environ.get("EXPECT", "")
lines = [l for l in raw.splitlines() if l.strip()]
host = lines[0].strip() if lines else "?"
primary = lines[1].strip() if len(lines) > 1 else "unnamed"
payload = next((l for l in lines if l.lstrip().startswith("{")), "")
agents = []
if payload:
    try:
        agents = (json.loads(payload).get("result") or {}).get("agents") or []
    except Exception:
        agents = []
if not agents:
    print(f"who[1]{{seat,host,primary,pane,session}}:\n  \"{peer}\",\"{host}\",\"{primary}\",\"-\",\"-\"")
    print(f"help: no agent is seated in that machine's herdr — the machine is up, the seat is not")
    sys.exit(4)
if len(agents) > 1:
    print(f"who[1]{{seat,problem}}:\n  \"{peer}\",\"{len(agents)} agents in that herdr — ambiguous, refusing to guess\"")
    for a in agents:
        print(f'  "pane {a.get("pane_id","?")} — {a.get("agent","?")} — {a.get("terminal_title","")}"')
    sys.exit(5)
a = agents[0]
session = ((a.get("agent_session") or {}).get("value") or "").split("/")[-1]
print(f'who[1]{{seat,host,primary,pane,session}}:\n  "{peer}","{host}","{primary}","{a.get("pane_id","-")}","{session}"')
if expect and primary and primary.lower() != expect.lower():
    print(f'help: the registry calls this seat "{expect}" but the far seat calls itself "{primary}" — trust the far seat, fix the registry')
    sys.exit(6)
PY
}

# The pane of a peer, or a loud refusal. Prints the pane id on success.
peer_pane() {
  local seat="$1" row name primary host user dest payload
  row="$(row_of "$seat")" || die "unknown seat '$seat'"
  IFS=$'\t' read -r name primary host user <<EOF
$row
EOF
  dest="$(resolve_dest "$host" "$user")"
  payload="$(remote "$dest" herdr agent list)" || die "peer unreachable — $payload"
  PEER="$seat" PAYLOAD="$payload" python3 - <<'PY'
import json, os, sys
peer = os.environ.get("PEER", "")
payload = os.environ.get("PAYLOAD", "")
line = next((l for l in payload.splitlines() if l.lstrip().startswith("{")), "")
agents = []
if line:
    try:
        agents = (json.loads(line).get("result") or {}).get("agents") or []
    except Exception:
        agents = []
if not agents:
    print(f"{sys.argv[0]}: no agent is seated in {peer}'s herdr — the machine is up, the seat is not", file=sys.stderr)
    sys.exit(4)
if len(agents) > 1:
    names = ", ".join(f'{a.get("pane_id","?")} ({a.get("agent","?")})' for a in agents)
    print(f"{sys.argv[0]}: {len(agents)} agents in {peer}'s herdr — ambiguous ({names}); refusing to guess", file=sys.stderr)
    sys.exit(5)
print(agents[0].get("pane_id") or "-")
PY
}

cmd_read() {
  local seat="${1:-}" lines=40
  shift || true
  while [ $# -gt 0 ]; do case "$1" in --lines) lines="${2:-40}"; shift 2 ;; *) shift ;; esac; done
  [ -n "$seat" ] || die "usage: $SELF read <seat> [--lines N]"
  local row name primary host user dest pane
  row="$(row_of "$seat")" || die "unknown seat '$seat'"
  IFS=$'\t' read -r name primary host user <<EOF
$row
EOF
  dest="$(resolve_dest "$host" "$user")"
  pane="$(peer_pane "$seat")" || exit $?
  remote "$dest" herdr agent read "'$pane'" --lines "'$lines'" --format text
}

cmd_say() {
  local seat="${1:-}"; shift || true
  local text="$*"
  [ -n "$seat" ] && [ -n "$text" ] || die "usage: $SELF say <seat> \"<line>\""

  local mine; mine="$(self_seat || true)"
  [ "$seat" = "$mine" ] && die "refusing to speak to my own seat ('$seat') — a seat that answers itself is a loop"

  case "$text" in *$'\e'*|*$'\r'*) die "refusing text with control sequences — a wire line is plain text, the pane is a terminal" ;; esac
  [ "${#text}" -le 4000 ] || die "refusing text longer than 4000 characters — say it in one line, not a file"

  local row name primary host user dest pane ts line
  row="$(row_of "$seat")" || die "unknown seat '$seat'"
  IFS=$'\t' read -r name primary host user <<EOF
$row
EOF
  dest="$(resolve_dest "$host" "$user")"
  pane="$(peer_pane "$seat")" || exit $?

  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  line="[seat ${mine:-unknown} via the wire, $ts] $text"

  # The record first, then the word: a spoken line that leaves no trace is unrecoverable.
  local roomsh="$HOME_DIR/hodd/bin/room.sh"
  if [ -x "$roomsh" ]; then
    "$roomsh" say "$ROOM" "${mine:-unknown}" "$text" >/dev/null 2>&1 \
      || say "help: the room line could not be written ($ROOM) — speaking anyway"
  fi

  remote "$dest" herdr agent prompt "'$pane'" "$(printf '%q' "$line")" >/dev/null 2>&1 \
    || die "delivery refused by the peer — the line was recorded in the room, not spoken"
  printf 'say[1]{to,pane,road,recorded}:\n  "%s","%s","pane","%s"\n' "$seat" "$pane" "$ROOM"
}

# --- the far seat's wake queue -------------------------------------------------------
# A queue path is resolved from its AUTHORITY, never from a remembered layout: the far
# arm's own `.arm.lease` names its `state=`. `~/.local/state/ymir/.wake-queue` is an
# ORPHAN shelf that no arm reads (measured 2026-11-05 — a line written there was never
# raised), so a nudge that cannot read a lease REFUSES instead of writing into a shelf
# that looks plausible.
#
# One round trip answers the whole question ON THE FAR SIDE, where the pid actually
# lives: the home (the far machine's own record, never a literal here), the lease, and
# liveness — pid alive AND starttime equal, because a recycled pid is not the arm.
#
# Prints one tab-separated line: lease<TAB>path<TAB>state-dir<TAB>pid<TAB>0|1
#                           nohome | nolease<TAB>path | nostate<TAB>lease
FAR_PROBE="$(cat <<'PROBE'
h=${SEAT_PROBE_HOME:-}
if [ -z "$h" ]; then
  h=${YMIR_HOME:-}
  [ -n "$h" ] || h=$(cat "$HOME/.config/ymir/home" 2>/dev/null | head -1)
fi
if [ -z "$h" ]; then
  r=$(sed -n 's/^roster=//p' "$HOME/.pi/agent/extensions/.ymir-seat" 2>/dev/null | head -1)
  h=${r%/hodd/identity/seats.yaml}
fi
if [ -z "$h" ]; then printf 'nohome\n'; exit 0; fi
l="$h/state/.arm.lease"
if [ ! -r "$l" ]; then printf 'nolease\t%s\n' "$l"; exit 0; fi
pid=$(sed -n 's/^pid=\([^ ]*\).*/\1/p' "$l" | head -1)
st=$(sed -n 's/.*starttime=\([^ ]*\).*/\1/p' "$l" | head -1)
dir=$(sed -n 's/.* state=//p' "$l" | head -1)
if [ -z "$dir" ]; then printf 'nostate\t%s\n' "$l"; exit 0; fi
alive=0
case "$pid" in
  ''|*[!0-9]*) : ;;
  *) if [ -r "/proc/$pid/stat" ]; then
       cur=$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null)
       [ -n "$st" ] && [ "$cur" = "$st" ] && alive=1
     fi ;;
esac
printf 'lease\t%s\t%s\t%s\t%s\n' "$l" "$dir" "$pid" "$alive"
PROBE
)"

far_probe() {  # far_probe <dest|empty> — the peer's lease, resolved by the peer itself
  local dest="$1"
  if [ -n "$dest" ]; then
    ssh -o BatchMode=yes -o ConnectTimeout="$SSH_TIMEOUT" -o StrictHostKeyChecking=accept-new \
      "$dest" bash -s <<<"$FAR_PROBE" 2>&1
  else
    SEAT_PROBE_HOME="$SEAT_HOME" bash -s <<<"$FAR_PROBE" 2>&1
  fi
}

cmd_nudge() {
  local seat="${1:-}"; shift || true
  local text="$*"
  [ -n "$seat" ] && [ -n "$text" ] || die "usage: $SELF nudge <seat> \"<line>\""

  local mine; mine="$(self_seat || true)"
  [ "$seat" = "$mine" ] && die "refusing to nudge my own seat ('$seat') — a seat that answers itself is a loop"

  case "$text" in *$'\e'*|*$'\r'*|*$'\n'*) die "refusing text with control sequences — the queue is line-oriented, so one plain line only" ;; esac
  [ "${#text}" -le 4000 ] || die "refusing text longer than 4000 characters — say it in one line, not a file"

  local row name primary host user dest probe kind lease dir pid alive ts line b64 b64dir
  row="$(row_of "$seat")" || die "unknown seat '$seat' — it carries no machine{host,ssh_user} in $SEATS_YAML"
  IFS=$'\t' read -r name primary host user <<EOF
$row
EOF
  if [ -n "$SEAT_HOME" ]; then dest=""; else dest="$(resolve_dest "$host" "$user")"; fi

  probe="$(far_probe "$dest")" || true
  kind="${probe%%$'\t'*}"
  case "$kind" in
    lease) ;;
    nohome)  die "the peer's home does not resolve — no YMIR_HOME, no recorded choice, no .ymir-seat roster on that machine; refusing to guess a queue path" ;;
    nolease) die "the peer's arm lease is ABSENT (${probe#*$'\t'}) — no lease, no live arm, no queue; refusing to guess a path" ;;
    nostate) die "the peer's arm lease names no state= (${probe#*$'\t'}) — the queue path cannot be resolved from it" ;;
    *)       die "the peer's lease could not be read${dest:+ over ssh to $dest} — ${probe:-no answer at all}" ;;
  esac
  IFS=$'\t' read -r kind lease dir pid alive <<EOF
$probe
EOF
  [ "$alive" = 1 ] || die "the peer's arm lease names pid '$pid', which is NOT a live process on that machine — a dead lease names a queue nothing drains"

  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  line="$(printf 'from=%s to=%s at=%s msg=%s' "${mine:-unknown}" "$seat" "$ts" "$text")"
  b64="$(printf '%s' "$line" | base64 | tr -d '\n')"
  b64dir="$(printf '%s' "$dir" | base64 | tr -d '\n')"

  # The write goes through base64, never through quoting: the line is arbitrary text.
  if [ -n "$dest" ]; then
    remote "$dest" "d=\$(printf '%s' '$b64dir' | base64 -d) && mkdir -p \"\$d\" && printf '%s' '$b64' | base64 -d >> \"\$d/.wake-queue\" && printf '\\n' >> \"\$d/.wake-queue\"" >/dev/null 2>&1 \
      || die "the peer refused the queue write — nothing was spoken, and nothing claims it was"
  else
    mkdir -p "$dir" 2>/dev/null || die "cannot create the queue shelf $dir"
    { printf '%s' "$b64" | base64 -d; printf '\n'; } >> "$dir/.wake-queue" \
      || die "the queue write to $dir failed — nothing was spoken, and nothing claims it was"
  fi

  printf 'nudge[1]{to,road,queue,lease,from}:\n  "%s","queue","%s/.wake-queue","%s","%s"\n' \
    "$seat" "$dir" "$lease" "${mine:-unknown}"
}

cmd_wait() {
  local seat="${1:-}"; shift || true
  local timeout=120000
  while [ $# -gt 0 ]; do case "$1" in --timeout) timeout="${2:-120000}"; shift 2 ;; *) shift ;; esac; done
  [ -n "$seat" ] || die "usage: $SELF wait <seat> [--timeout MS]"
  local row name primary host user dest pane
  row="$(row_of "$seat")" || die "unknown seat '$seat'"
  IFS=$'\t' read -r name primary host user <<EOF
$row
EOF
  dest="$(resolve_dest "$host" "$user")"
  pane="$(peer_pane "$seat")" || exit $?
  remote "$dest" herdr agent wait "'$pane'" --until idle --timeout "'$timeout'"
}

case "${1:-}" in
  seats) shift; cmd_seats "$@" ;;
  who)   shift; cmd_who "$@" ;;
  read)  shift; cmd_read "$@" ;;
  say)   shift; cmd_say "$@" ;;
  wait)  shift; cmd_wait "$@" ;;
  nudge) shift; cmd_nudge "$@" ;;
  ''|-h|--help|help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown verb '$1' (seats|who|read|say|wait|nudge)" ;;
esac
