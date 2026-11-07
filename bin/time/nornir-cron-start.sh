#!/usr/bin/env bash
# nornir-cron-start.sh - ensure Brokk's scheduled jobs are running (idempotent).
#
# Nornir are the fates who govern time. Jobs are declared in config/cron.yaml as
# `HH:MM <command>` lines (one per line, `#` comments). This script keeps exactly
# one lightweight scheduler loop alive via state/cron.pid. The loop:
#   * date-guards each job under state/.cron-fired/<job> so it runs once a day,
#     even across a restarted loop;
#   * runs each command with a per-job flock so a slow job never overlaps itself;
#   * exports the BROKK_* home/state/config/root env to every job;
#   * runs jobs from BROKK_HOME and logs to state/cron.log.
#
# Ported concept from plan 24 (cron schedule) and the upstream stateless-spawn
# pattern for plan 29.
#
# Usage: nornir-cron-start.sh [--status|--stop]
#
# Environment (kept from the original interface):
#   BROKK_ROOT_OVERRIDE, BROKK_HOME, BROKK_STATE_OVERRIDE, BROKK_CONFIG_OVERRIDE
#   BROKK_CRON_LOG_MAX_BYTES  rotation threshold for state/cron.log (default 1 MiB)
set -u

# --- portability shim: bin/fleet/ymir-platform.sh --------------------------------
# One place knows the OS differences (readlink -f, /proc, setsid, stat, nproc).
if [ -z "${YMIR_PLATFORM_LOADED:-}" ]; then
  _ymir_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  for _ymir_c in "${_ymir_dir}/../fleet/ymir-platform.sh" "$(CDPATH='' cd "$_ymir_dir" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)/bin/fleet/ymir-platform.sh"; do
    [ -r "$_ymir_c" ] && { . "$_ymir_c"; YMIR_PLATFORM_LOADED=1; break; }
  done
  unset _ymir_dir _ymir_c
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${BROKK_ROOT_OVERRIDE:-$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)}"
export ROOT  # the job wrapper needs it after bash -c
BROKK_HOME="${BROKK_HOME:-$ROOT}"
# A SEAT MUST NOT SCHEDULE THE HOUSE. Every errand seat runs a session start with
# its OWN state dir (`…/ymir/seats/<id>`), and this door's "is it stopped" check then
# answers yes — so six seats started six schedulers over one config/cron.yaml, each
# keeping its own already-fired marks. A 14:20 job could run six times, each scheduler
# believing it was first (measured 2026-10-24: `cron-leak: 6 cron loops`). Only the
# primary's state starts the house schedule; a seat says so and exits 0.
case "${BROKK_STATE_OVERRIDE:-}" in
  */seats/*)
    printf 'cron[1]{state,why}:\n  "refused","a seat does not schedule the house — %s is a seat state dir; the primary owns config/cron.yaml"\n' "$BROKK_STATE_OVERRIDE" >&2
    exit 0 ;;
esac
# ONE STATE DIR (phase 0): the operator's runtime state belongs to the HOME, never
# the code tree. With no explicit override the default used to be $BROKK_HOME/state
# (the repo's scratch), so any advisory caller — ymir-validate, a session start —
# read a DIFFERENT pidfile than the units and started a second scheduler over the
# same schedule (measured 2026-11-06: one loop under the unit, one under the repo).
# The hoard is the one answer; the repo's state/ is the fallback only when there is
# no home at all.
if [ -n "${BROKK_STATE_OVERRIDE:-}" ]; then
  STATE="$BROKK_STATE_OVERRIDE"
else
  _hoard=""
  if [ -r "$SCRIPT_DIR/../vault/hoard-lib.sh" ]; then
    . "$SCRIPT_DIR/../vault/hoard-lib.sh" 2>/dev/null || true
    ymir_home_root _hoard 2>/dev/null || _hoard=""
  fi
  if [ -n "$_hoard" ] && [ -d "$_hoard/state" ]; then
    STATE="$_hoard/state"
  else
    STATE="$BROKK_HOME/state"
  fi
  unset _hoard
fi
# The schedule is the USER'S, not the distro's: an explicit BROKK_CONFIG_OVERRIDE
# wins, then the home's own config/cron.yaml, then the repo's example (which
# ships what a fresh hour suggests but never claims to be the live schedule).
if [ -n "${BROKK_CONFIG_OVERRIDE:-}" ]; then
  CONFIG="$BROKK_CONFIG_OVERRIDE"
else
  . "$SCRIPT_DIR/../vault/hoard-lib.sh"  # ymir_home_root — one answer, never drift
  ymir_home_root _h
  if [ -r "$_h/config/cron.yaml" ]; then
    CONFIG="$_h/config"
  elif [ -r "$BROKK_HOME/config/cron.yaml" ] && [ "$BROKK_HOME" != "$_h" ]; then
    CONFIG="$BROKK_HOME/config"
  else
    CONFIG="$BROKK_HOME/config"
  fi
fi
CRON_CONFIG="$CONFIG/cron.yaml"
# Fall back to the shipped example ONLY when no user schedule exists yet — the
# example is a template, never the live job list.
if [ ! -r "$CRON_CONFIG" ] && [ -r "$BROKK_HOME/config/cron.yaml.example" ]; then
  CRON_CONFIG="$BROKK_HOME/config/cron.yaml.example"
fi
PID_FILE="$STATE/cron.pid"
LOG_FILE="$STATE/cron.log"
STAMP_DIR="$STATE/.cron-fired"
LOCK_DIR="$STATE/.cron-locks"
IDENTITY_MARK='cron run:'

mkdir -p "$STATE"

job_count() {
  [ -r "$CRON_CONFIG" ] || { printf '0'; return; }
  grep -vE '^[[:space:]]*(#|$)' "$CRON_CONFIG" 2>/dev/null | wc -l | tr -d '[:space:]'
}

# A live loop is a live pid whose command line still carries the scheduler body.
# The identity check guards against pid reuse after a reboot/crash.
running_pid() {
  [ -r "$PID_FILE" ] || return 1
  local pid
  pid=$(tr -d '[:space:]' <"$PID_FILE")
  case "$pid" in
    ''|*[!0-9]*) return 1 ;;
  esac
  kill -0 "$pid" 2>/dev/null || return 1
  # /proc is Linux-only; the shim falls back to `ps -o command=`.
  if ymir_pid_alive "$pid"; then
    ymir_pid_cmdline "$pid" 2>/dev/null | grep -q "$IDENTITY_MARK" || return 1
  fi
  printf '%s' "$pid"
}

rotate_log() {
  [ -r "$LOG_FILE" ] || return 0
  local size max
  size=$(wc -c <"$LOG_FILE" 2>/dev/null | tr -d '[:space:]')
  case "$size" in ''|*[!0-9]*) return 0 ;; esac
  max="${BROKK_CRON_LOG_MAX_BYTES:-1048576}"
  if [ "$size" -gt "$max" ]; then
    mv "$LOG_FILE" "$LOG_FILE.1" 2>/dev/null || true
  fi
}

# ── the schedule SHAPES (plan 140) ─────────────────────────────────────────────
# One parser, used by the loop AND by the start-time warning, because two parsers
# is how a row goes declared-but-dead (2026-09-24, one layer up). A shape decides
# BOTH what fires and which STAMP it writes: a per-day job may fire once a day, a
# per-hour job once an hour, and the stamp is what stops a 45 s loop from firing
# the same row twice.
is_role() { # <token> -> 0 when it is a role gate (@heart, @dev,forge)
  case "${1-}" in @?*) ;; *) return 1 ;; esac
  local _r
  for _r in $(printf '%s' "${1#@}" | tr ',' ' '); do
    case "$_r" in heart|forge|dev|hand) ;; *) return 1 ;; esac
  done
  return 0
}

at_valid() { # <at> -> 0 when the time token is a shape the scheduler understands
  case "${1-}" in
    @hourly|@daily) return 0 ;;
    @hourly:*)
      local _m="${1#@hourly:}"
      case "$_m" in ''|*[!0-9]*) return 1 ;; esac
      [ "$_m" -le 59 ] 2>/dev/null && return 0
      return 1 ;;
    [01][0-9]:[0-5][0-9]|2[0-3]:[0-5][0-9]) return 0 ;;
  esac
  return 1
}

# parse_line <line> -> "gate<TAB>at<TAB>cmd" — the role gate may sit before or after
# the time (plan 54), and a shape may sit in either place too, so the token that is
# a ROLE is found by what it is, never by its position.
parse_line() {
  local _rest="${1-}" _t1 _t2 _rest2=""
  _t1=${_rest%% *}
  if [ "$_t1" = "$_rest" ]; then _rest=""; else _rest=${_rest#* }; fi
  if is_role "$_t1"; then
    _t2=${_rest%% *}
    if [ "$_t2" = "$_rest" ]; then _rest2=""; else _rest2=${_rest#* }; fi
    printf '%s\t%s\t%s\n' "$_t1" "$_t2" "$_rest2"
    return 0
  fi
  _t2=${_rest%% *}
  if [ "$_t2" = "$_rest" ]; then _rest2=""; else _rest2=${_rest#* }; fi
  if is_role "$_t2"; then
    printf '%s\t%s\t%s\n' "$_t2" "$_t1" "$_rest2"
  else
    # `-` stands for 'no role gate': a leading EMPTY field would be eaten by IFS
    # (tab is whitespace to `read`), which silently shifts every field by one.
    printf '%s\t%s\t%s\n' "-" "$_t1" "$_rest"
  fi
}
export -f is_role at_valid parse_line

scheduler='
  config="$1"; log="$2"; state="$3"; home="$4"; confdir="$5"; root="$6"
  export BROKK_HOME="$home"
  export BROKK_STATE_OVERRIDE="$state"
  export BROKK_CONFIG_OVERRIDE="$confdir"
  export BROKK_ROOT_OVERRIDE="$root"
  export BROKK_REALM="${BROKK_REALM:-}"
  export BROKK_ROLES="${BROKK_ROLES:-dev}"
  stamp_dir="$state/.cron-fired"
  lock_dir="$state/.cron-locks"
  # A tab carried in a variable: fields are taken by expansion, never by `read`.
  # On this seat `IFS=<tab> read` put the whole line in the first field, and a
  # schedule parser that can eat a row without saying so is a schedule nobody trusts.
  TAB=$(printf "\t")
  mkdir -p "$stamp_dir" "$lock_dir"
  while :; do
    # Retire when the session that started this scheduler is gone: a seat that
    # ends must not leave its cron loop behind (2026-09-23 -- eight orphan loops
    # from ended seats). The scheduler lives only while the state lock is held by
    # a live process; a headless scheduler with no lock retires too, because
    # Nornir is started BY a session, never before one.
    #
    # EXCEPTION (plan 51 Part 7): the always-on heart has no interactive session,
    # so the record crons would never run. A PERSISTENT seat sets
    # BROKK_NORNIR_PERSIST=1 and the loop binds to the machine ROLE, not a
    # session: it stays up with no lock and is stopped only by --stop or the
    # unit. (A fake session lock was the rejected alternative — it would refuse a
    # real Brokk seat on the heart.)
    if [ "${BROKK_NORNIR_PERSIST:-0}" = "1" ]; then
      : # persistent seat: never retire on a missing session lock
    elif [ -n "${BROKK_MACHINE_STATE_DIR:-}" ]; then
      mach="$BROKK_MACHINE_STATE_DIR"
    elif [ -f "$state/.lock-path" ]; then
      # Phase 0 (one state dir): the helms location is what the pointer says, never the
      # raw legacy default. The pointer is the ONE fact (bin/vault/hoard-lib.sh +
      # src/ymir_runtime/state/lock.py); restating it here is how the cron
      # retired against a missing lock at the OLD path while a fresh session
      # stood — 2026-09-27, the install validation caught it.
      mach="$(dirname "$(cat "$state/.lock-path" 2>/dev/null || true)")"
      if [ -z "$mach" ] || [ "$mach" = "." ] || [ ! -d "$mach" ]; then
        mach="${XDG_STATE_HOME:-$HOME/.local/state}/ymir"
      fi
    else
      mach="${XDG_STATE_HOME:-$HOME/.local/state}/ymir"
    fi
    if [ "${BROKK_NORNIR_PERSIST:-0}" != "1" ]; then
      lockf="$mach/brokk.lock"
      owner=$(tr -d "[:space:]" <"$lockf" 2>/dev/null || true)
      st=$(ps -o stat= -p "$owner" 2>/dev/null | tr -d " ")
      if [ -z "$owner" ] || [ "$owner" = "1" ] || [ ! -d "/proc/$owner" ] \
         || [ "${st#Z}" != "$st" ] || [ "${st#X}" != "$st" ]; then
        printf "%s cron retired - no live session lock at %s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$lockf" >>"$log"
        rm -f "$state/cron.pid" 2>/dev/null || true
        exit 0
      fi
    fi
    now=$(date +%H:%M)
    today=$(date +%Y-%m-%d)
    this_hour=$(date +%Y-%m-%dT%H)
    while IFS= read -r line; do
      case "$line" in ""|\#*) continue ;; esac
      # An optional role gate may sit BEFORE the time (the home config form:
      # @heart 06:00 bin/x) or AFTER it (06:00 @heart bin/x). The 2026-09-24
      # fault: only the after-time shape parsed, so every role-first line was
      # silently DEAD while --status still counted it declared — on every seat,
      # the heart record jobs never fired. Both orders are one gate now (plan 54).
      gate=""; at=""; cmd=""
      _parsed=$(parse_line "$line")
      gate=${_parsed%%"$TAB"*}
      _after=${_parsed#*"$TAB"}
      at=${_after%%"$TAB"*}
      cmd=${_after#*"$TAB"}
      [ "$gate" = "-" ] && gate=""
      [ -n "$cmd" ] || continue
      # A token the scheduler cannot read is a job that would be SILENTLY dead, so
      # it is named once (in state/.cron-invalid, which --status reports) and never
      # fired. It is not allowed to look declared.
      if ! at_valid "$at"; then
        grep -qxF -- "$line" "$state/.cron-invalid" 2>/dev/null \
          || printf "%s\n" "$line" >>"$state/.cron-invalid"
        continue
      fi
      # The shape decides the fire and the STAMP (plan 140): @hourly fires at the
      # top of every hour, @hourly:MM at that minute, @daily at 00:00, HH:MM once a
      # day. The stamp key is derived from the shape — never guessed from the time.
      fire=0; stamp_key=""
      case "$at" in
        @hourly)   stamp_key="$this_hour"; [ "${now#*:}" = "00" ] && fire=1 ;;
        @hourly:*) _want=$(printf "%02d" "${at#@hourly:}" 2>/dev/null)
                   stamp_key="$this_hour"; [ "${now#*:}" = "$_want" ] && fire=1 ;;
        @daily)    stamp_key="$today"; [ "$now" = "00:00" ] && fire=1 ;;
        *)         stamp_key="$today"; [ "$at" = "$now" ] && fire=1 ;;
      esac
      [ "$fire" = 1 ] || continue
      if [ -n "$gate" ]; then
        _match=0
        for _w in ${gate#@}; do
          case ",${BROKK_ROLES:-dev}," in *",$_w,"*) _match=1 ;; esac
        done
        [ "$_match" = 1 ] || continue
      fi
      key=$(printf "%s" "$cmd" | tr -c "A-Za-z0-9._-" "_")
      stamp="$stamp_dir/$key"
      if [ -r "$stamp" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$stamp_key" ]; then continue; fi
      printf "%s\n" "$stamp_key" >"$stamp"
      ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      printf "%s cron run: %s\n" "$ts" "$cmd" >>"$log"
      lock="$lock_dir/$key.lock"
      if command -v flock >/dev/null 2>&1; then
        ( flock -n 8 || { printf "%s cron skip (busy): %s\n" "$ts" "$cmd" >>"$log"; exit 0; }
          cd "$home" 2>/dev/null || true
          bash -lc "$cmd" >>"$log" 2>&1
          _rc=$?
          if [ "$_rc" -ne 0 ]; then
            _tail="$(tail -n 4 "$log" 2>/dev/null | grep -v '^$' | tail -n 1 | cut -c1-160)"
            [ -x "$ROOT/bin/notify/send.sh" ] && bash "$ROOT/bin/notify/send.sh" --source cron --severity HIGH \
              --key "cron-fail:$key:$today" --message "job failed (rc=$_rc): $cmd — ${_tail:-no output}" >/dev/null 2>&1 || true
          fi
        ) 8>>"$lock" &
      else
        ( cd "$home" 2>/dev/null || true
          bash -lc "$cmd" >>"$log" 2>&1
          _rc=$?
          if [ "$_rc" -ne 0 ]; then
            _tail="$(tail -n 4 "$log" 2>/dev/null | grep -v '^$' | tail -n 1 | cut -c1-160)"
            [ -x "$ROOT/bin/notify/send.sh" ] && bash "$ROOT/bin/notify/send.sh" --source cron --severity HIGH \
              --key "cron-fail:$key:$today" --message "job failed (rc=$_rc): $cmd — ${_tail:-no output}" >/dev/null 2>&1 || true
          fi
        ) &
      fi
    done <"$config"
    [ "${BROKK_CRON_ONCE:-0}" = 1 ] && exit 0
    sleep "${BROKK_CRON_TICK:-45}"
  done
'

case "${1-}" in
  --status)
    invalid=0
    [ -r "$STATE/.cron-invalid" ] && invalid=$(grep -c . "$STATE/.cron-invalid" 2>/dev/null || printf '0')
    extra=""; [ "${invalid:-0}" != 0 ] && extra=" invalid=$invalid"
    if pid=$(running_pid); then
      printf 'cron: running pid=%s jobs=%s%s\n' "$pid" "$(job_count)" "$extra"
    else
      printf 'cron: stopped jobs=%s%s\n' "$(job_count)" "$extra"
    fi
    exit 0
    ;;
  --stop)
    if pid=$(running_pid); then
      kill "$pid" 2>/dev/null || true
      rm -f "$PID_FILE"
      printf 'cron: stopped pid=%s\n' "$pid"
    else
      rm -f "$PID_FILE" 2>/dev/null || true
      printf 'cron: already stopped\n'
    fi
    exit 0
    ;;
esac

if pid=$(running_pid); then
  printf 'cron: running pid=%s jobs=%s\n' "$pid" "$(job_count)"
  exit 0
fi

jobs=$(job_count)
if [ "$jobs" = "0" ]; then
  printf 'cron: no jobs configured (%s absent or empty)\n' "$CRON_CONFIG"
  exit 0
fi

# Name every line whose schedule shape the scheduler does not understand, BEFORE the
# loop starts. A row that cannot be read is a job that will never fire, and this house
# has already paid once for a declared-but-dead schedule (2026-09-24).
_bad=$(
  grep -vE '^[[:space:]]*(#|$)' "$CRON_CONFIG" 2>/dev/null | while IFS= read -r _l; do
    _p=$(parse_line "$_l")
    _at=${_p#*	}; _at=${_at%%	*}
    at_valid "$_at" || printf '%s\n' "$_l"
  done
)
if [ -n "$_bad" ]; then
  printf 'cron: WARNING — %s line(s) carry a schedule shape Nornir does not understand, and will NOT fire:\n' "$(printf '%s\n' "$_bad" | grep -c .)" >&2
  printf '%s\n' "$_bad" | sed 's/^/  /' >&2
  printf 'cron: shapes are HH:MM · @hourly · @hourly:MM · @daily (after or before the @role gate)\n' >&2
fi
unset _bad _l _p _at

mkdir -p "$STAMP_DIR" "$LOCK_DIR"
rotate_log

# This machine's roles (plan 51): the scheduler runs only the jobs its roles own.
# Read from the topology resolver; default to `dev` when there is no registry, so
# an unconfigured box runs only ungated jobs (and never a heart's record jobs).
if [ -z "${BROKK_ROLES:-}" ]; then
  _roles="dev"
  if [ -x "$SCRIPT_DIR/../fleet/topology.sh" ]; then
    _roles="$(bash "$SCRIPT_DIR/../fleet/topology.sh" --json 2>/dev/null \
      | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: d={}
print(",".join(d.get("roles") or ["dev"]))' 2>/dev/null)"
    [ -n "$_roles" ] || _roles="dev"
  fi
  BROKK_ROLES="$_roles"
  unset _roles
fi
export BROKK_ROLES

if command -v setsid >/dev/null 2>&1; then
  setsid bash -c "$scheduler" _ "$CRON_CONFIG" "$LOG_FILE" "$STATE" "$BROKK_HOME" "$CONFIG" "$ROOT" >>"$LOG_FILE" 2>&1 &
else
  nohup bash -c "$scheduler" _ "$CRON_CONFIG" "$LOG_FILE" "$STATE" "$BROKK_HOME" "$CONFIG" "$ROOT" >>"$LOG_FILE" 2>&1 &
fi
loop_pid=$!
printf '%s\n' "$loop_pid" >"$PID_FILE"
printf 'cron: started pid=%s jobs=%s\n' "$loop_pid" "$jobs"
