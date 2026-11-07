#!/usr/bin/env bash
# autoboot-lib.sh — the boot policy: fleet roles → the Ymir programs they owe.
#
# ONE table, shared by bin/engine/ymir-autoboot.sh (the proof), bin/fleet/fleet-ensure.sh
# (the raise) and the installer's autoboot step. A program's role gate and its
# unit name live HERE and nowhere else, so the seat's raise and its proof can
# never disagree (the class of lie this platform keeps paying for).
#
# Roles come from the fleet registry (hodd/data/fleet.json): heart (owns the
# record) · forge (models/GPU) · dev (a full body) · hand (a phone).
#
# Programs:
#   well-mcp  the well's served MCP door (:8317)          heart,dev
#   mcp-gateway the body's one record door (:8316)        heart,forge,dev
#   ratatoskr the A2A node (:8301)                        heart
#   a2abridge-directory the A2A mesh directory (:7777)    heart,dev
#   mill-worker the well's grinder                         heart
#   cards     the seats' card root (:8318)                heart
#   skills-mcp the skills well MCP door (:8319)           heart
#   skuld     the ticket hall (:8320)                     heart
#   snotra    the meeting ear MCP face (:8321)              heart
#   snotra-detect the ear's WATCH (: the call's start/leave) CAPABILITY: a seat
#                                                         with a microphone (a call
#                                                         seat), never the heart
#   embed     the embedding stone (:8500)                 heart,forge
#   hlidskjalf-spa  the high seat's SPA (:3888)            dev
#   hlidskjalf-gate the gate API (:3889)                  dev
#   mimir     the well bridge (:4602)                     dev
#   bifrost   the model bridge (:4603)                    dev
#   smidja    the smithy's eye (:8437)                    dev
#   nornir    the seat's scheduled jobs (config/cron.yaml) heart,dev
#   syn-watch the arm: Sýn as a standing service (idle-not-dead) heart,dev
#
# A seat rises exactly what its roles owe. The web stack (Hlidskjalf's SPA, the
# gate, Mimir, Bifrost, Smiðja) are SERVICES — dev seats owe them as units; the
# desktop windows an operator opens stay on demand. That line is the law
# (Allfather, 2026-09-24), not an implementation detail.
#
# This file is a library: it defines functions and never runs on its own.
set -u

# --- provenance -----------------------------------------------------------
AUTOBOOT_LIB_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTOBOOT_ROOT="${BROKK_ROOT_OVERRIDE:-$(CDPATH='' cd "$AUTOBOOT_LIB_SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)}"
if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  for _ab_c in "${AUTOBOOT_LIB_SCRIPT_DIR}/../vault/hoard-lib.sh" "$AUTOBOOT_LIB_SCRIPT_DIR/../vault/hoard-lib.sh" "$AUTOBOOT_LIB_SCRIPT_DIR/../../vault/hoard-lib.sh"; do
    [ -r "$_ab_c" ] && { . "$_ab_c"; YMIR_HOARD_LIB_LOADED=1; break; }
  done
  unset _ab_c
fi
AUTOBOOT_HOME_ROOT=""
if command -v ymir_home_root >/dev/null 2>&1; then ymir_home_root AUTOBOOT_HOME_ROOT 2>/dev/null; fi
AUTOBOOT_HOME_ROOT="${AUTOBOOT_HOME_ROOT:-${YMIR_HOME}}"
AUTOBOOT_FLEET_REGISTRY="${YMIR_FLEET_REGISTRY:-$AUTOBOOT_HOME_ROOT/hodd/data/fleet.json}"
AUTOBOOT_HOST="${YMIR_HOST:-$(hostname -s 2>/dev/null | tr 'A-Z' 'a-z')}"
AUTOBOOT_STATE_DIR="${BROKK_STATE_OVERRIDE:-}"
if [ -z "$AUTOBOOT_STATE_DIR" ]; then
  AUTOBOOT_STATE_DIR="${YMIR_STATE_DIR:-}"
  if [ -z "$AUTOBOOT_STATE_DIR" ] && command -v hoard_state_dir >/dev/null 2>&1; then
    hoard_state_dir AUTOBOOT_STATE_DIR 2>/dev/null || true
  fi
  AUTOBOOT_STATE_DIR="${AUTOBOOT_STATE_DIR:-$AUTOBOOT_HOME_ROOT/state}"
fi

# --- the one table --------------------------------------------------------
AUTOBOOT_PROGRAMS="a2abridge-directory well-mcp mcp-gateway ratatoskr mill-worker cards skills-mcp skuld snotra snotra-detect gna-desk embed hlidskjalf-spa hlidskjalf-gate mimir bifrost smidja nornir syn-watch"

autoboot_role_programs() {  # <role> → prints the program ids the role owes
  case "${1-}" in
    heart) printf '%s\n' "a2abridge-directory well-mcp mcp-gateway ratatoskr mill-worker cards skills-mcp skuld snotra gna-desk embed nornir syn-watch" ;;
    forge) printf '%s\n' "embed mcp-gateway gna-desk" ;;
    dev)   printf '%s\n' "a2abridge-directory well-mcp mcp-gateway hlidskjalf-spa hlidskjalf-gate mimir bifrost smidja nornir gna-desk syn-watch" ;;
    hand|*) printf '%s\n' "" ;;
  esac
}


autoboot_program_desc() {  # <program> → one human line
  case "${1-}" in
    a2abridge-directory) printf '%s\n' "the local A2A directory (:7777)" ;;
    well-mcp)       printf '%s\n' "the well's MCP door (:8317)" ;;
    mcp-gateway)    printf '%s\n' "the body's one record door (:8316)" ;;
    snotra)         printf '%s\n' "the meeting ear's MCP face (:8321, read-only minutes)" ;;
    snotra-detect)  printf '%s\n' "the ear's watch — arms on a call, leaves when the room empties (mic seats)" ;;
    ratatoskr)      printf '%s\n' "the A2A node (:8301)" ;;
    a2abridge-directory) printf '%s\n' "the A2A mesh directory (:7777)" ;;
    mill-worker)    printf '%s\n' "the mill worker" ;;
    cards)          printf '%s\n' "the cards root (:8318)" ;;
    skills-mcp)     printf '%s\n' "the skills well door (:8319)" ;;
    skuld)          printf '%s\n' "the ticket hall (:8320)" ;;
    gna-desk)       printf '%s\n' "the mail desk (:8494) — the inbox the arm is told about, as it arrives" ;;
    embed)          printf '%s\n' "the embedding stone (:8500)" ;;
    hlidskjalf-spa) printf '%s\n' "Hlidskjalf SPA (:3888)" ;;
    hlidskjalf-gate) printf '%s\n' "the gate API (:3889)" ;;
    mimir)          printf '%s\n' "the well bridge (:4602)" ;;
    bifrost)        printf '%s\n' "the model bridge (:4603)" ;;
    smidja)         printf '%s\n' "the smithy's eye (:8437)" ;;
    nornir)         printf '%s\n' "the seat's scheduled jobs (config/cron.yaml)" ;;
    syn-watch)      printf '%s\n' "the arm: Sýn as a standing service (idle-not-dead)" ;;
    *)              printf '%s\n' "${1-}" ;;
  esac
}

# --- the capability axis ---------------------------------------------------
# A program owed by CAPABILITY, never by role: Snotra's watch can only stand on
# a seat that can HEAR — one with a PipeWire graph and a real microphone. The
# heart is headless and owes nothing; a call seat owes the watch. A seat that
# cannot hear reports a clean skip, and the raise's purge lowers the unit where
# it cannot live.
AUTOBOOT_CAPABILITY_PROGRAMS="snotra-detect"

autoboot_capability_detect() {  # exit 0 iff this seat has a microphone to watch
  command -v pactl >/dev/null 2>&1 || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  # a non-monitor source is a microphone; monitor sources are playback taps
  pactl list short sources 2>/dev/null \
    | awk '{ n=$2; if (n != "" && n !~ /\.monitor$/) found=1 } END { exit !found }'
}

autoboot_capability_programs() {  # prints this seat's capability-owed programs
  autoboot_capability_detect && printf '%s\n' "snotra-detect"
  return 0
}

# --- the seat -------------------------------------------------------------
autoboot_roles_result() {  # <result-var> — the seat's roles (space joined)
  local rv="$1" _ab_out=""
  if [ -r "$AUTOBOOT_FLEET_REGISTRY" ]; then
    _ab_out="$(python3 - "$AUTOBOOT_FLEET_REGISTRY" "$AUTOBOOT_HOST" <<'PY' 2>/dev/null || true
import json, sys
reg, host = sys.argv[1], sys.argv[2]
try: doc = json.load(open(reg))
except Exception: print(""); raise SystemExit
print(",".join((doc.get("hosts") or {}).get(host, {}).get("roles") or []))
PY
)"
  fi
  case "${_ab_out:-}" in
    ""|unassigned) printf -v "$rv" '%s' "" ;;
    *) printf -v "$rv" '%s' "${_ab_out//,/ }" ;;
  esac
}

autoboot_owed() {  # <result-var> — this seat's owed programs, dedup'd, in registry order
  local rv="$1" _ab_roles="" _ab_r _ab_p _ab_seen=""
  autoboot_roles_result _ab_roles
  [ -n "$_ab_roles" ] || _ab_roles="dev"   # an unregistered seat is a dev body by default
  for _ab_r in $_ab_roles; do
    for _ab_p in $(autoboot_role_programs "$_ab_r"); do
      case " $_ab_seen " in *" $_ab_p "*) ;; *) _ab_seen="$_ab_seen $_ab_p" ;; esac
    done
  done
  # ... and the capability-owed programs, on the same table's discipline: a
  # seat's raise and its proof must never disagree about what it owes.
  for _ab_p in $(autoboot_capability_programs); do
    case " $_ab_seen " in *" $_ab_p "*) ;; *) _ab_seen="$_ab_seen $_ab_p" ;; esac
  done
  printf -v "$rv" '%s' "${_ab_seen# }"
}

autoboot_owed_roles() {  # <result-var> — the roles used for the owe computation (for reporting)
  local rv="$1" _ab_roles=""
  autoboot_roles_result _ab_roles
  [ -n "$_ab_roles" ] || _ab_roles="dev (default: unregistered seat)"
  printf -v "$rv" '%s' "$_ab_roles"
}

autoboot_unit_of() {  # <program|target> — the unit file name (the ONE target has none)
  # The name is almost always <program>.service, but the arm's own door is
  # bin/pi/syn-watch.sh while its unit is ymir-syn-watch.service: the map lives HERE
  # so the raise, the proof, the purge, and the materializer all agree.
  case "${1-}" in
    ymir.target) printf '%s\n' "ymir.target" ;;
    syn-watch) printf '%s\n' "ymir-syn-watch.service" ;;
    *) printf '%s\n' "${1-}.service" ;;
  esac
}

autoboot_is_unit_enabled() {  # <program> — exit 0 iff the unit's [Install] links it
  systemctl --user is-enabled --quiet "$(autoboot_unit_of "$1")" 2>/dev/null
}

autoboot_is_unit_active() {  # <program> — exit 0 iff the unit state is active
  systemctl --user is-active --quiet "$(autoboot_unit_of "$1")" 2>/dev/null
}

autoboot_is_unit_failed() {  # <program> — exit 0 iff the unit state is failed
  [ "$(systemctl --user show -p ActiveState --value "$(autoboot_unit_of "$1")" 2>/dev/null)" = "failed" ]
}

# --- the activity probes --------------------------------------------------
# A daemon's truth is its unit state. Nornir's is its scheduler loop: the unit
# is oneshot (it calls bin/time/nornir-cron-start.sh, which daemonizes the loop), so
# the loop's own identity check is the probe — never the unit's stale "exited".
autoboot_probe() {  # <program> — exit 0 iff genuinely active
  case "${1-}" in
    nornir) autoboot_cron_up ;;
    *)      autoboot_is_unit_active "$1" ;;
  esac
}

autoboot_cron_up() {  # exit 0 iff a live scheduler loop carries its identity mark
  # The scheduler's state dir follows the caller's env (BROKK_HOME/OVERRIDE)
  # or the seat's hoard state — probe whichever exists with a live loop.
  local _ab_cand="" _ab_pid=""
  for _ab_cand in "${BROKK_STATE_OVERRIDE:-}" "${BROKK_HOME:-$AUTOBOOT_ROOT}/state" "$AUTOBOOT_STATE_DIR"; do
    [ -n "$_ab_cand" ] || continue
    [ -r "$_ab_cand/cron.pid" ] || continue
    _ab_pid=$(tr -d '[:space:]' <"$_ab_cand/cron.pid" 2>/dev/null || true)
    case "$_ab_pid" in ''|*[!0-9]*) continue ;; esac
    kill -0 "$_ab_pid" 2>/dev/null || continue
    ps -o command= -p "$_ab_pid" 2>/dev/null | grep -q 'cron run:' && return 0
  done
  return 1
}

autoboot_cron_alive_owner() {  # exit 0 iff a live session lock exists (Nornir lives only by a session)
  local mach lockf owner st
  mach="${BROKK_MACHINE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/ymir}"
  lockf="$mach/brokk.lock"
  [ -r "$lockf" ] || return 1
  owner=$(tr -d '[:space:]' <"$lockf" 2>/dev/null || true)
  case "$owner" in ''|*[!0-9]*) return 1 ;; esac
  [ -d "/proc/$owner" ] || return 1
  st=$(ps -o stat= -p "$owner" 2>/dev/null | tr -d ' ')
  case "$st" in ''|Z*|X*) return 1 ;; esac
  return 0
}

# --- the deferred record --------------------------------------------------
# An OPERATOR override, never a silent default: a program a seat owes may be
# marked deferred with a reason (bin/engine/ymir-autoboot.sh deferred <p> <why>), and
# then verify treats its inactivity as understood. Nothing writes this record
# by itself — absence and silence are not success.
AUTOBOOT_DEFERRED_FILE="$AUTOBOOT_STATE_DIR/autoboot-deferred"

autoboot_deferred_reason() {  # <program> → reason, or empty
  local p="$1"
  [ -r "$AUTOBOOT_DEFERRED_FILE" ] || return 0
  awk -F '\t' -v want="$p" '$1==want { print $2; exit }' "$AUTOBOOT_DEFERRED_FILE"
}

autoboot_is_deferred() {  # <program> — exit 0 iff a reason is recorded
  [ -n "$(autoboot_deferred_reason "${1-}")" ]
}

# --- the wall clock of the seat -------------------------------------------
autoboot_linger() {  # prints `yes` or `no`
  local v
  v="$(loginctl show-user "$USER" -p Linger 2>/dev/null | sed 's/^Linger=//')"
  case "$v" in yes) printf '%s\n' yes ;; *) printf '%s\n' no ;; esac
}

autoboot_has_display() {  # exit 0 iff a display is present (a window could open)
  { [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]; } && return 0 || return 1
}

autoboot_is_headless() {  # exit 0 iff no display — boot services need linger here
  autoboot_has_display && return 1 || return 0
}