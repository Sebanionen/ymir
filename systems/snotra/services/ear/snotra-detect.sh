#!/usr/bin/env bash
# systems/snotra/services/snotra-detect.sh — the door itself (plan 129). The 'RETIRED SHIM' wording below was copied in by the move and removed 2026-10-31: this file IS the door, not a shim of one.
#
# It exists so a caller nobody has repointed yet still works. It is retired by the dated follow-up in
# docs/fixes/snotra/2026-10-24-snotra-becomes-a-system.md, and .agents/paths-ledger.yaml records the move.
set -euo pipefail
# The 'RETIRED SHIM' guard that used to sit here computed its target as $_d/../../../
# — three levels up from systems/snotra/services/ear, which is <repo>/systems, not the
# repo root — so it always found nothing and exited 127. Copied here by the move from
# bin/time/snotra/ (where three levels up WAS the root). Removed 2026-11-04: this file
# is the door, and the door has nothing to point at.
if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  # The hoard library sits beside this file in a flat install (~/.fleet) and four
  # levels up in the tree (systems/snotra/services/ear -> repo root). Both are tried;
  # the fleet copy is what the unit actually runs.
  _door_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  _root="$_door_dir"
  while [ "$_root" != / ] && { [ ! -d "$_root/RULES" ] || [ ! -d "$_root/.agents" ]; }; do
    _root="$(dirname "$_root")"
  done
  [ -d "$_root/RULES" ] || _root=""
  for _lib in "$_door_dir/hoard-lib.sh" ${_root:+"$_root/bin/vault/hoard-lib.sh"}; do
    [ -r "$_lib" ] && . "$_lib" 2>/dev/null && break
  done
fi
if [ -z "${YMIR_HOME:-}" ] && command -v ymir_home_root >/dev/null 2>&1; then
  ymir_home_root YMIR_HOME
fi
if [ -z "${YMIR_HOME:-}" ]; then
  printf 'error: the hoard home could not be resolved — bin/vault/hoard-lib.sh was not found\n' >&2
  printf 'help: seat the watch with bin/fleet/fleet-ensure.sh ensure (it materializes hoard-lib.sh\n' >&2
  printf '      beside the operator commands in ~/.fleet), or set YMIR_HOME\n' >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YMIR_HOME="${YMIR_HOME}"
HOARD="$YMIR_HOME/hodd"
MEETINGS="$HOARD/workspaces/meetings"
STATE_DIR="${YMIR_STATE_DIR:-$YMIR_HOME/state}"
STATE_FILE="$STATE_DIR/.snotra-detect.json"
DETECT_LOG="$STATE_DIR/.snotra-detect.log"
CAPTURE_STATE="$STATE_DIR/.snotra-pid"
CAPTURE_OUT="$STATE_DIR/.snotra-outfile"
LATEST_FILE="$STATE_DIR/.snotra-meetings-latest"

POLL_SECONDS="${SNOTRA_POLL_SECONDS:-2}"
# The shortest gap between two ticks. See the loop in run(): a tick opens its own
# PipeWire clients, and those are events on the same bus the watch listens to.
TICK_MIN_GAP_MS="${SNOTRA_TICK_GAP_MS:-1000}"
ARM_DEBOUNCE="${SNOTRA_ARM_DEBOUNCE:-3}"
RELEASE_GRACE="${SNOTRA_RELEASE_GRACE:-5}"
SILENCE_DB="${SNOTRA_SILENCE_DB:--45}"
SILENCE_SECONDS="${SNOTRA_SILENCE_SECONDS:-300}"
PROBE_SECONDS="${SNOTRA_PROBE_SECONDS:-10}"
MAX_SECONDS="${SNOTRA_MAX_SECONDS:-14400}"
MIN_SECONDS="${SNOTRA_MIN_SECONDS:-5}"
IGNORE_APPS="${SNOTRA_IGNORE_APPS:-}"
IGNORE_BINARIES="${SNOTRA_IGNORE_BINARIES:-ffmpeg}"
IGNORE_APP_RE="${SNOTRA_IGNORE_APP_RE:-^PipeWire ALSA }"
# NOTE: this regex is handed to awk, whose -v strips backslash escapes — an
# escape here would arrive as a bare metacharacter (a `\[` becomes an
# unterminated bracket expression and awk refuses the whole scan). Keep it plain.
COOLDOWN="${SNOTRA_COOLDOWN:-30}"
LANE="${SNOTRA_LANE:-ping}"

# The seat's own policy, kept with the operator (Rule 04/07): a KEY=value file
# in the hoard may name what this seat does NOT treat as a call (a dictation
# tool, a voice-mode helper, a test harness) without editing the tree. It is
# read BEFORE the environment, so an explicit env value still wins.
POLICY_FILE="$HOARD/data/snotra-detect.conf"
if [ -r "$POLICY_FILE" ]; then
  # shellcheck disable=SC1090
  . "$POLICY_FILE"
  IGNORE_APPS="${SNOTRA_IGNORE_APPS:-$IGNORE_APPS}"
  IGNORE_BINARIES="${SNOTRA_IGNORE_BINARIES:-$IGNORE_BINARIES}"
  IGNORE_APP_RE="${SNOTRA_IGNORE_APP_RE:-$IGNORE_APP_RE}"
  COOLDOWN="${SNOTRA_COOLDOWN:-$COOLDOWN}"
fi

mkdir -p "$MEETINGS" "$STATE_DIR" 2>/dev/null || true

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/snotra-detect.XXXXXX")" || exit 1
SUB_PID=""
PROBE_PID=""
FIFO_FD=9
cleanup() {
  [ -z "$PROBE_PID" ] || kill "$PROBE_PID" 2>/dev/null || true
  [ -z "$SUB_PID" ] || kill "$SUB_PID" 2>/dev/null || true
  eval "exec $FIFO_FD<&-" 2>/dev/null || true
  rm -rf "$TMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
# A requested stop is not a failure: systemd's `stop` sends SIGTERM after
# ExecStop has already closed the book, and exiting 143 there would leave the
# unit marked failed for a stop the operator asked for.
trap 'cleanup; exit 0' TERM

say() { printf '%s\n' "$*"; }
log() {
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"$DETECT_LOG" 2>/dev/null || true
}

have() { command -v "$1" >/dev/null 2>&1; }

# ── the doors ───────────────────────────────────────────────────────────────
# The watch is seated from the seat's own materialized copy (%h/.fleet, exactly
# as the ear's engine is), while the fleet doors it calls live in the durable
# tree the unit names. So each door is resolved, never assumed:
#   the PIPELINE doors ship WITH the watch   — beside it first, then the tree
#   the FLEET doors live in the TREE          — the tree first, then beside it
SNOTRA_DOORS_DIR="${SNOTRA_DOORS_DIR:-}"
# The doors: the PIPELINE ships WITH the watch (beside it first, so the seat's
# own materialized copies are what run), the FLEET doors live in the durable tree
# the unit names (the tree first — they own the ledger, the rail, and the queue).
SNOTRA_PIPELINE_DOORS=" snotra-capture.sh snotra-transcribe.sh snotra-mine.sh "
SNOTRA_FLEET_DOORS=" ymir-state.sh runes-append.sh ymir-say.sh rail-resolve.sh "

door() {  # <name> → the path of the door to call
  case "$SNOTRA_PIPELINE_DOORS" in
    *" $1 "*)
      [ -x "$SCRIPT_DIR/$1" ] && { printf '%s' "$SCRIPT_DIR/$1"; return 0; }
      [ -n "$SNOTRA_DOORS_DIR" ] && [ -x "$SNOTRA_DOORS_DIR/$1" ] && { printf '%s' "$SNOTRA_DOORS_DIR/$1"; return 0; }
      ;;
  esac
  case "$SNOTRA_FLEET_DOORS" in
    *" $1 "*)
      [ -n "$SNOTRA_DOORS_DIR" ] && [ -e "$SNOTRA_DOORS_DIR/$1" ] && { printf '%s' "$SNOTRA_DOORS_DIR/$1"; return 0; }
      [ -e "$SCRIPT_DIR/$1" ] && { printf '%s' "$SCRIPT_DIR/$1"; return 0; }
      ;;
  esac
  [ -n "$SNOTRA_DOORS_DIR" ] && [ -e "$SNOTRA_DOORS_DIR/$1" ] && { printf '%s' "$SNOTRA_DOORS_DIR/$1"; return 0; }
  printf '%s' "$SCRIPT_DIR/$1"
}

# ── the PipeWire picture, through the portable pactl surface ────────────────
# One snapshot of the four graphs the watch reasons over, emitted as tab-separated
# records so bash can read them without a second JSON parser:
#   SRC <index> <name> <is_monitor>
#   SO  <index> <source_index> <app> <pid> <binary> <corked>
#   SNK <index> <name>
#   SI  <index> <sink_index> <app> <pid> <corked>
snapshot() {  # <out-file> — exit 1 when PipeWire cannot be read
  have pactl || return 1
  pactl -f json list sources        >"$TMP_DIR/sources.json" 2>/dev/null || return 1
  pactl -f json list source-outputs >"$TMP_DIR/so.json"      2>/dev/null || return 1
  pactl -f json list sinks          >"$TMP_DIR/sinks.json"   2>/dev/null || return 1
  pactl -f json list sink-inputs    >"$TMP_DIR/si.json"      2>/dev/null || return 1
  python3 - "$TMP_DIR" <<'PY'
import json, os, sys
d = sys.argv[1]
def load(n):
    try:
        with open(os.path.join(d, n), encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return []
out = []
for s in load("sources.json"):
    out.append("SRC\t%s\t%s\t%s" % (
        s.get("index"), s.get("name") or "", 1 if s.get("monitor_source") else 0))
for s in load("sinks.json"):
    out.append("SNK\t%s\t%s" % (s.get("index"), s.get("name") or ""))
for s in load("so.json"):
    p = s.get("properties") or {}
    out.append("SO\t%s\t%s\t%s\t%s\t%s\t%s" % (
        s.get("index"), s.get("source"), p.get("application.name") or "",
        p.get("application.process.id") or "", p.get("application.process.binary") or "",
        p.get("pulse.corked") or ""))
for s in load("si.json"):
    p = s.get("properties") or {}
    out.append("SI\t%s\t%s\t%s\t%s\t%s" % (
        s.get("index"), s.get("sink"), p.get("application.name") or "",
        p.get("application.process.id") or "", p.get("pulse.corked") or ""))
sys.stdout.write("\n".join(out) + ("\n" if out else ""))
PY
}

# The mic-holding streams, minus the watch's own hands. Emits:
#   <so-index>\t<app>\t<pid>\t<source-name>
mic_holders() {  # <snapshot>
  local capture_pid=""
  [ -r "$CAPTURE_STATE" ] && capture_pid="$(tr -d '[:space:]' <"$CAPTURE_STATE" 2>/dev/null || true)"
  awk -F'\t' -v cap="$capture_pid" -v probe="$PROBE_PID" \
      -v ign_apps="$IGNORE_APPS" -v ign_bins="$IGNORE_BINARIES" \
      -v ign_re="$IGNORE_APP_RE" '
    BEGIN {
      n = split(ign_apps, a, " "); for (i = 1; i <= n; i++) if (a[i] != "") badapp[a[i]] = 1
      n = split(ign_bins, b, " "); for (i = 1; i <= n; i++) if (b[i] != "") badbin[b[i]] = 1
    }
    $1 == "SRC" { if ($4 == "0") mic[$2] = $3; next }
    $1 == "SO" {
      if (!($3 in mic)) next
      if (cap != "" && $5 == cap) next
      if (probe != "" && $5 == probe) next
      if ($4 in badapp) next
      if ($6 in badbin) next
      if (ign_re != "" && $4 ~ ign_re) next
      print $2 "\t" $4 "\t" $5 "\t" mic[$3]
    }
  ' "$1"
}

# The mic-holding source-output indices now (comma separated, numeric order).
holder_indices() {  # <snapshot>
  mic_holders "$1" | cut -f1 | sort -n | paste -sd, -
}

# The mic-holding app pids now (space separated, deduped, no empties).
holder_pids() {  # <snapshot>
  mic_holders "$1" | awk -F'\t' '{ if ($3 != "" && !($3 in seen)) { seen[$3] = 1; printf "%s ", $3 } }'
}

# Playback stream indices now (comma separated, numeric order).
si_indices() {  # <snapshot>
  awk -F'\t' '$1 == "SI" { print $2 }' "$1" | sort -n | paste -sd, -
}

# NEW playback streams opened by a pid that already holds the microphone: the
# conversation's remote side beginning. Emits "<pid>\t<app>" per pid.
talkback_pids() {  # <snapshot> <baseline-mic-pids> <baseline-si-indices>
  awk -F'\t' -v base="$2" -v basesi="$3" '
    BEGIN {
      n = split(base, b, " "); for (i = 1; i <= n; i++) if (b[i] != "") was[b[i]] = 1
      n = split(basesi, s, ","); for (i = 1; i <= n; i++) if (s[i] != "") hadsi[s[i]] = 1
    }
    $1 == "SI" { if ($5 != "" && ($5 in was) && !($2 in hadsi) && !($5 in seen)) { seen[$5] = 1; print $5 "\t" $4 } }
  ' "$1"
}

# The sink name a pid's playback rides, or empty.
sink_of_pid() {  # <snapshot> <pid>
  [ -z "$2" ] && return 0
  awk -F'\t' -v want="$2" '
    $1 == "SNK" { name[$2] = $3; next }
    $1 == "SI" { if ($5 == want && !found) { found = 1; print name[$3] } }
  ' "$1"
}

# The source name a stream index rides.
source_of_index() {  # <snapshot> <so-index>
  awk -F'\t' -v want="$2" '
    $1 == "SRC" { name[$2] = $3; next }
    $1 == "SO" { if ($2 == want) print name[$3] }
  ' "$1"
}

# The app name a stream index carries.
app_of_index() {  # <snapshot> <so-index>
  awk -F'\t' -v want="$2" '$1 == "SO" && $2 == want { print $4; exit }' "$1"
}

pid_of_index() {  # <snapshot> <so-index>
  awk -F'\t' -v want="$2" '$1 == "SO" && $2 == want { print $5; exit }' "$1"
}

default_sink() {
  pactl get-default-sink 2>/dev/null && return
  wpctl status 2>/dev/null | awk '/Sinks:/{f=1} f&&/\*/{print $2; exit}'
}

default_source() {
  pactl get-default-source 2>/dev/null && return
  wpctl status 2>/dev/null | awk '/Sources:/{f=1} f/\*/{print $2; exit}'
}

sink_present() {  # <snapshot> <sink-name> — exit 0 when present or unnamed
  [ -z "$2" ] && return 0
  awk -F'\t' -v want="$2" '$1 == "SNK" && $3 == want { found = 1 } END { exit !found }' "$1"
}

# The room's own level, in dB: the mic and the conversation's monitor mixed for
# one second. Empty when the probe could not run (never a silent "quiet").
probe_level() {  # <monitor> <mic>
  have ffmpeg || return 0
  local out="$TMP_DIR/probe.log"
  : >"$out"
  ffmpeg -hide_banner -nostats -f pulse -i "$1" -f pulse -i "$2" -t 1 \
    -filter_complex "[0:a][1:a]amix=inputs=2:duration=shortest,volumedetect" \
    -f null - >"$out" 2>&1 &
  PROBE_PID=$!
  wait "$PROBE_PID" 2>/dev/null || true
  PROBE_PID=""
  sed -n 's/.*mean_volume: \(-\{0,1\}[0-9.]*\) dB.*/\1/p' "$out" | head -1
}

# ── the watch's own state (crash-recoverable) ──────────────────────────────
state_write() {  # <phase> <slug> <outfile> <topic> <monitor> <mic> <sink> <armed> <triggers-csv> <baseline-csv>
  python3 - "$STATE_FILE" "$@" <<'PY'
import json, os, sys
path = sys.argv[1]
keys = ["phase", "slug", "outfile", "topic", "monitor", "mic", "sink",
        "armed_epoch", "triggers", "baseline"]
d = dict(zip(keys, sys.argv[2:]))
d["triggers"] = [x for x in d["triggers"].split(",") if x]
d["baseline"] = [x for x in d["baseline"].split(",") if x]
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(d, fh, indent=2)
os.replace(tmp, path)
PY
}

state_clear() { rm -f "$STATE_FILE" 2>/dev/null || true; }

state_get() {  # <key> — prints the value, empty when absent
  [ -r "$STATE_FILE" ] || return 0
  python3 - "$STATE_FILE" "$1" <<'PY' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        d = json.load(fh)
except Exception:
    raise SystemExit(0)
v = d.get(sys.argv[2], "")
if isinstance(v, list):
    v = ",".join(str(x) for x in v)
print(v)
PY
}

capture_alive() {
  [ -r "$CAPTURE_STATE" ] || return 1
  local pid
  pid="$(tr -d '[:space:]' <"$CAPTURE_STATE" 2>/dev/null || true)"
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$pid" 2>/dev/null
}

# The Allfather's law, enforced structurally: the ear NEVER lingers. Whatever pid
# the state has lost — a second arm, a crash, a restart — no ffmpeg may still be
# writing into the meetings shelf once a leave has been decided. Only a capture
# of ours names the shelf, so this can never reach an unrelated recorder.
stop_lingering_captures() {
  local p cmd killed=0
  for p in $(pgrep -x ffmpeg 2>/dev/null); do
    cmd="$(tr '\0' ' ' <"/proc/$p/cmdline" 2>/dev/null || true)"
    case "$cmd" in
      *"$MEETINGS/"*)
        kill "$p" 2>/dev/null && { killed=$((killed + 1)); log "stopped a lingering capture (pid $p)"; }
        ;;
    esac
  done
  [ "$killed" -gt 0 ] && sleep 1
  return 0
}

slugify() {  # <text> → a filename-safe token
  local s
  s="$(printf '%s' "${1:-}" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9' '-' | sed 's/-\{1,\}/-/g; s/^-//; s/-$//')"
  s="${s:0:32}"
  printf '%s' "${s:-impromptu}"
}

# ── the ENGINE's residency: awake only while a meeting is ───────────────────
# The watch needs no engine — it is a read of the PipeWire graph. The ENGINE
# (whisper on the ear lane, :8322) is what costs VRAM, and it is not small:
# ~900 MiB on a strong box. On a 16 GiB card that is the whole margin — with
# the engine resident, the rail's 262K model cannot allocate its MTP draft
# context and every request comes back 500. Measured on heimdall 2026-10-01:
# the preset takes 13,790 MiB, the engine 900, and 16,384 is the card.
#
# So the engine follows the SAME question the watch already asks, and nothing
# else: `snotra-iscall.sh` is the one authority on whether a call is live, so
# it is the one authority on whether the engine owes the card any VRAM. Its
# residency is deliberately NOT `WantedBy=ymir.target` and NOT a capability
# raise — those decide by what HARDWARE the seat has, never by whether a
# MEETING is happening, which is how a seat ended up holding 900 MiB for three
# days with no call on the room.
#
# The window is `arm` -> `finalize` complete. Not one tick shorter: the
# transcription of the recording happens AT leave, through this very engine, so
# lowering it when the room empties rather than when the minutes are written
# would lose the meeting it was raised for.
SNOTRA_EAR_UNIT="${SNOTRA_EAR_UNIT:-snotra-ear.service}"

# The unit is seated from the DURABLE tree at arm time, never enabled at boot.
# It is deliberately not in AUTOBOOT_PROGRAMS: that list is the purge list, and
# an entry there would be purged for not being owed — while an entry NOT there
# is ungoverned, which is how a 900 MiB engine came to sit on a seat for three
# days with no meeting and no unit in the tree to audit. Seating it here keeps
# one copy, in the tree, and makes a seat that has never held a meeting cost
# nothing at all.
ear_seat_unit() {  # 0 when the TREE's unit is the one seated (seated, or refreshed)
  local src dst
  dst="$HOME/.config/systemd/user/$SNOTRA_EAR_UNIT"
  mkdir -p "$HOME/.config/systemd/user" 2>/dev/null || return 1
  # SNOTRA_DOORS_DIR is <root>/bin, so the tree that holds tools/mill/systemd
  # is its parent. Beside the watch first, exactly as door() prefers.
  for src in "$SCRIPT_DIR/../tools/mill/systemd/$SNOTRA_EAR_UNIT" \
             "${SNOTRA_DOORS_DIR:-/nonexistent}/../tools/mill/systemd/$SNOTRA_EAR_UNIT"; do
    [ -f "$src" ] || continue
    # Already the tree's copy — nothing to do. Comparing, not merely testing for
    # existence: a seat that was seated by an EARLIER version of this tree still
    # carries that version's unit, and the earlier version is the one with
    # `[Install] WantedBy=ymir.target` in it. Seeding only what is missing leaves
    # exactly the seats that need the fix holding the file that causes it.
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
      return 0
    fi
    if cp -f "$src" "$dst" 2>/dev/null; then
      if [ -f "$dst" ]; then
        log "engine: seated the tree's $SNOTRA_EAR_UNIT into ~/.config/systemd/user (refreshed)"
      else
        log "engine: WARNING — could not seat $SNOTRA_EAR_UNIT"
        return 1
      fi
    else
      log "engine: WARNING — could not seat $SNOTRA_EAR_UNIT"
      return 1
    fi
    # daemon-reload only. Nothing here enables the unit, and the tree's copy has
    # no [Install] section — so there is no longer a way to put the engine back
    # into ymir.target, even by hand.
    systemctl --user daemon-reload >>"$DETECT_LOG" 2>&1 || true
    return 0
  done
  # No template in either tree. A seat's own copy still runs, so this is a
  # warning and not a refusal: an un-auditable unit is worth saying out loud.
  if [ -f "$dst" ]; then
    log "engine: WARNING — no $SNOTRA_EAR_UNIT template in the tree; the seat's own copy stands"
    return 0
  fi
  log "engine: WARNING — no $SNOTRA_EAR_UNIT template in the tree"
  return 1
}

ear_up() {
  have systemctl || return 0
  if systemctl --user is-active --quiet "$SNOTRA_EAR_UNIT" 2>/dev/null; then
    return 0
  fi
  ear_seat_unit || return 0
  log "engine: raising $SNOTRA_EAR_UNIT — a meeting is being recorded"
  if systemctl --user start "$SNOTRA_EAR_UNIT" >>"$DETECT_LOG" 2>&1; then
    log "engine: $SNOTRA_EAR_UNIT is up"
  else
    # Not fatal. The seat's own whisper is the fallback lane, and a meeting that
    # is recorded is a meeting that can still be transcribed.
    log "engine: WARNING — $SNOTRA_EAR_UNIT did not rise; transcription falls to the seat's own whisper"
  fi
  return 0
}

ear_down() {
  have systemctl || return 0
  if ! systemctl --user is-active --quiet "$SNOTRA_EAR_UNIT" 2>/dev/null; then
    return 0
  fi
  log "engine: lowering $SNOTRA_EAR_UNIT — the minutes are written, the card is owed nothing"
  if systemctl --user stop "$SNOTRA_EAR_UNIT" >>"$DETECT_LOG" 2>&1; then
    log "engine: $SNOTRA_EAR_UNIT is down"
  else
    log "engine: WARNING — $SNOTRA_EAR_UNIT did not lower; it will idle at the next boot"
  fi
  return 0
}

# ── the START edge: arm the ear on the conversation pair ───────────────────
do_arm() {  # <snapshot> <trigger-csv> <baseline-csv> [forced-slug]
  local snap="$1" triggers="$2" baseline="$3" forced="${4:-}"
  # THE ALLFATHER'S LAW (2026-10-31): the microphone is NEVER used to hear an
  # online meeting. An app taking the mic on this box is almost always a Meet,
  # Zoom or Teams call — that call is heard by the BOT (snotra-bot.sh, the Vexa
  # participant), never by this seat's microphone. The ear stays down unless the
  # room is LOCAL — people physically here, which must be asked for by name.
  if [ "${SNOTRA_LOCAL_ROOM:-0}" != "1" ]; then
    log "arm REFUSED — the mic is for a LOCAL room only; an online meeting is heard by the bot (snotra-bot.sh join <url>), never by the seat microphone"
    return 1
  fi
  # ONE ear at a time. The watch's loop and the manual door can both ask to arm
  # (and a trigger set can change mid-debounce); a second capture would leave the
  # first one writing into the shelf with no pid anyone holds — a lingering ear.
  if capture_alive; then
    log "arm refused — the ear is already listening (pid $(cat "$CAPTURE_STATE" 2>/dev/null || echo '?'))"
    return 1
  fi
  stop_lingering_captures
  local first_so mic sink slug topic app pid
  first_so="${triggers%%,*}"
  mic="$(source_of_index "$snap" "$first_so")"
  app="$(app_of_index "$snap" "$first_so")"
  pid="$(pid_of_index "$snap" "$first_so")"

  # The remote side must be heard: capture the sink the call itself plays into.
  sink="$(sink_of_pid "$snap" "$pid")"
  [ -n "$sink" ] || sink="$(default_sink)"
  [ -n "$mic" ] || mic="$(default_source)"
  if [ -z "$sink" ] && [ -z "$mic" ]; then
    log "arm refused: no mic and no sink resolved"
    return 1
  fi

  slug="${forced:-$(slugify "${app:-impromptu}")}"
  topic="$LANE meeting — ${app:-impromptu}"
  local date base outfile
  date="$(date +%Y-%m-%d)"
  base="${date}-${LANE}-${slug}"
  outfile="$MEETINGS/${base}.wav"

  log "START edge — app '${app:-?}' (pid ${pid:-?}) took the mic; pair mic='$mic' sink='${sink:-default}'; slug=$slug"
  SNOTRA_MONITOR="${sink:+$sink.monitor}" \
  SNOTRA_MIC="$mic" \
  SNOTRA_TOPIC="$topic" \
  SNOTRA_OUTFILE="$outfile" \
  SNOTRA_MAX_SECONDS="$MAX_SECONDS" \
    "$(door snotra-capture.sh)" start >>"$DETECT_LOG" 2>&1 &
  local i=0
  while [ "$i" -lt 20 ]; do
    capture_alive && break
    sleep 0.5
    i=$((i + 1))
  done
  if ! capture_alive; then
    log "arm FAILED — the capture did not rise (see $DETECT_LOG)"
    return 1
  fi
  state_write "in-call" "$slug" "$outfile" "$topic" "${sink:+$sink.monitor}" "$mic" "$sink" \
    "$(date +%s)" "$triggers" "$baseline"
  # The engine rises only once the capture is confirmed alive — a refused arm
  # must not cost the card a whisper for a meeting that is not being heard.
  ear_up
  say "snotra: the ear is listening — ${base}"
  return 0
}

# ── the LEAVE edge: stop, finalize, deliver ────────────────────────────────
do_leave() {  # <reason>
  local reason="$1" slug outfile topic mic monitor sink armed
  slug="$(state_get slug)"
  outfile="$(state_get outfile)"
  topic="$(state_get topic)"
  mic="$(state_get mic)"
  monitor="$(state_get monitor)"
  sink="$(state_get sink)"
  armed="$(state_get armed_epoch)"
  [ -n "$slug" ] || slug="impromptu"

  log "LEAVE edge ($reason) — stopping the ear"
  "$(door snotra-capture.sh)" stop >>"$DETECT_LOG" 2>&1 || true
  local i=0
  while capture_alive && [ "$i" -lt 30 ]; do
    sleep 0.5
    i=$((i + 1))
  done
  capture_alive && log "WARNING: the capture did not release within 15s"
  # and whatever pid the state lost, the shelf is closed to it
  stop_lingering_captures

  if [ -z "$outfile" ] || [ ! -f "$outfile" ]; then
    [ -r "$CAPTURE_OUT" ] && outfile="$(cat "$CAPTURE_OUT" 2>/dev/null || true)"
  fi
  if [ -z "$outfile" ] || [ ! -f "$outfile" ]; then
    log "leave: no recording on disk — nothing to finalize"
    state_clear
    ear_down
    return 1
  fi
  local bytes secs=""
  bytes="$(stat -c '%s' "$outfile" 2>/dev/null || echo 0)"
  # A blip is not a meeting. The floor is named and configurable: below it the
  # recording is KEPT (never thrown away) and the shelf is left alone, so a
  # dictation-length grab cannot masquerade as minutes.
  if have ffprobe; then
    secs="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$outfile" 2>/dev/null | cut -d. -f1)"
  fi
  case "${secs:-}" in ''|*[!0-9]*) secs=$(( ${bytes:-0} / 192000 )) ;; esac
  if [ "${secs:-0}" -lt "$MIN_SECONDS" ]; then
    log "leave: recording ${secs}s is below the ${MIN_SECONDS}s meeting floor — kept, not mined ($outfile)"
    say "snotra: the ear left; ${secs}s was too short to be a meeting (kept: $outfile)"
    state_clear
    # Still lowered: the recording is kept on the shelf, but nothing will
    # transcribe it now, so holding the engine for it is a cost with no buyer.
    ear_down
    return 1
  fi

  finalize "$outfile" "$slug" "$topic" "$reason" "$armed" "$sink" "$mic"
  # AFTER finalize, never before: finalize transcribes the recording through this
  # engine. Lowering first would leave a recorded meeting with no minutes.
  ear_down
}

finalize() {  # <wav> <slug> <topic> <reason> <armed> <sink> <mic>
  local wav="$1" slug="$2" topic="$3" reason="$4" armed="$5" sink="$6" mic="$7"
  local date base minutes transcript actions
  date="$(date +%Y-%m-%d)"
  base="${date}-${LANE}-${slug}"
  minutes="$MEETINGS/${base}.md"
  transcript="$MEETINGS/${base}.transcript.txt"
  actions="$MEETINGS/${base}.actions.md"

  log "finalize — $base (mic='$mic' sink='${sink:-?}')"

  local rail_model
  rail_model="${SNOTRA_RAIL_MODEL:-${RAIL_MODEL:-}}"
  if [ -z "$rail_model" ] && [ -x "$(door rail-resolve.sh)" ]; then
    rail_model="$(bash "$(door rail-resolve.sh)" resolve --json 2>/dev/null \
      | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: d={}
m=(d.get("serving") or {}).get("models") or []
print(m[0] if m else "")' 2>/dev/null || true)"
  fi

  local ok=0
  if [ -x "$(door snotra-transcribe.sh)" ]; then
    SNOTRA_MINUTES_FILE="$minutes" \
    SNOTRA_TRANSCRIPT_FILE="$transcript" \
    RAIL_MODEL="$rail_model" \
      bash "$(door snotra-transcribe.sh)" "$wav" "$topic" >>"$DETECT_LOG" 2>&1 && ok=1
  fi
  if [ "$ok" != 1 ]; then
    log "finalize: transcription did not complete — the recording is kept at $wav"
    say "snotra: the ear left; transcription failed (recording kept: $wav)"
  fi

  if [ -x "$(door snotra-mine.sh)" ] && [ -s "$transcript" ]; then
    bash "$(door snotra-mine.sh)" "$transcript" "$actions" "$minutes" >>"$DETECT_LOG" 2>&1 || true
  fi

  # `grep -c` prints 0 and exits 1 when nothing matches — never let a second 0
  # ride along, or the wake reads "0 0 actions".
  local counts="0"
  if [ -s "$actions" ]; then
    counts="$(grep -c '^- ' "$actions" 2>/dev/null || true)"
    [ -n "$counts" ] || counts="0"
  fi

  # A short call is seconds, not "0m": say the truth at both scales.
  local dur_secs=0 dur_label="0s"
  case "${armed:-}" in
    ''|*[!0-9]*) ;;
    *)
      dur_secs=$(( $(date +%s) - armed ))
      if [ "$dur_secs" -ge 60 ]; then dur_label="$(( dur_secs / 60 ))m"; else dur_label="${dur_secs}s"; fi
      ;;
  esac

  if [ -x "$(door runes-append.sh)" ]; then
    "$(door runes-append.sh)" snotra meeting.captured \
      --message "snotra: $LANE meeting captured and delivered — $minutes ($dur_label, $reason)" \
      >/dev/null 2>&1 || true
  fi

  printf '%s\n' "$minutes" >"$LATEST_FILE" 2>/dev/null || true

  deliver "$minutes" "$actions" "$slug" "$counts" "$dur_label" "$reason"
  state_clear
}

# ── the delivery: the meeting comes to the Allfather ───────────────────────
deliver() {  # <minutes> <actions> <slug> <counts> <duration> <reason>
  local minutes="$1" actions="$2" slug="$3" counts="$4" dur="$5" reason="$6"
  local headline body
  headline="Meeting captured — $slug ($dur)"
  body="Minutes: $minutes"
  [ -s "$actions" ] && body="$body
Actions: $actions ($counts mined)"

  # ── ONCE ONLY (2026-09-28) ────────────────────────────────────────────────
  # One meeting, one announcement. The watch re-finalises a capture it has already
  # finalised (a released mic that comes back, a restart that finds an abandoned
  # recording, a flap), and each pass announced the SAME minutes again — the
  # Allfather was told about one capture over and over, and separate `check` rows
  # accumulated in the wake queue for it. Key the delivery on the MEETING ARTEFACT
  # — the minutes path, which is unique per capture — and never on the app slug,
  # which collides across meetings and never closes. A suppression is logged and
  # said out loud, never silent.
  local ledger_dir ledger
  ledger_dir="$STATE_DIR/meetings-delivered"
  mkdir -p "$ledger_dir" 2>/dev/null || true
  ledger="$ledger_dir/$(printf '%s' "$minutes" | sha256sum | cut -c1-16)"
  if [ -e "$ledger" ]; then
    log "already delivered — $minutes (suppressed; one meeting is announced once)"
    say "snotra: already delivered — $headline"
    return 0
  fi
  printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$minutes" >"$ledger" 2>/dev/null || true

  # --mark-done is ymir-say's own verb form: it takes the headline and body as
  # its own arguments (a trailing flag would be parsed as the headline).
  if [ -x "$(door ymir-say.sh)" ]; then
    "$(door ymir-say.sh)" --mark-done "$headline" "$body" >>"$DETECT_LOG" 2>&1 || true
  fi

  # The durable wake, through the queue's OWN door (bin/records/ymir-state.sh →
  # src/ymir_runtime/state/queue.py, the one implementation): a `check`, the kind
  # the fleet uses for news that is not a crew status line, so the meeting
  # reaches Brokk with no arm and no sweep.
  #
  # Two deliberate choices. FIRST, the door and not the shell helper
  # (bin/time/brokk-wake-lib.sh's fm_wake_append): that helper takes a lock DIRECTORY
  # at $STATE/.wake-queue.lock while the queue itself owns a lock FILE at the
  # same path — so where the queue's file exists the helper's acquire can never
  # succeed and it waits forever. A watch that waits forever is an ear that never
  # leaves. SECOND, the append is BOUNDED: whatever the queue's health, a
  # delivery must not be able to wedge the watch.
  local state_door
  state_door="$(door ymir-state.sh)"
  if [ -x "$state_door" ]; then
    timeout 20 "$state_door" queue append check "meeting:$slug" \
      "check: $LANE meeting captured — $minutes ($dur, $reason, $counts actions)" \
      >/dev/null 2>&1 || true
  fi

  log "delivered — $minutes"
  say "snotra: $headline"
  say "  minutes: $minutes"
  [ -s "$actions" ] && say "  actions: $actions"
}

# ── one turn of the watch ──────────────────────────────────────────────────
# Carried across ticks by the loop.
PHASE="idle"
BASELINE=""
BASELINE_PIDS=""
BASELINE_SI=""
TRIGGERS=""
ARM_EPOCH=0
CALL_SINK=""
CALL_MONITOR=""
CALL_MIC=""
PENDING_KEY=""
PENDING_SINCE=0
RELEASED_SINCE=0
QUIET_SINCE=0
LAST_PROBE=0
LAST_LEVEL=""
COOLDOWN_UNTIL=0

rebaseline() {  # take the baseline from the graph as it stands now
  local snap="$TMP_DIR/snap0.tsv"
  snapshot >"$snap" 2>/dev/null || return 0
  BASELINE="$(holder_indices "$snap")"
  BASELINE_PIDS="$(holder_pids "$snap")"
  BASELINE_SI="$(si_indices "$snap")"
}

back_to_idle() {  # re-baseline after a meeting ends
  PHASE="idle"
  PENDING_KEY=""
  PENDING_SINCE=0
  RELEASED_SINCE=0
  QUIET_SINCE=0
  LAST_PROBE=0
  LAST_LEVEL=""
  TRIGGERS=""
  ARM_EPOCH=0
  CALL_SINK=""
  CALL_MONITOR=""
  CALL_MIC=""
  # The anti-flap guard. A meeting's own end can raise a microphone (a
  # notification sound, an app closing its device, the seat's voice tooling
  # waking) — and a watch that re-armed on that would deliver forever. So a
  # meeting's close is followed by a named quiet: the graph is re-baselined and
  # nothing arms until it passes.
  COOLDOWN_UNTIL=$(( $(date +%s) + COOLDOWN ))
  rebaseline
  # The safety net for the engine. Reaching idle means no meeting is being
  # recorded, so nothing is owed the card: a watch that restarted mid-meeting
  # (leaving an engine up with no arm behind it), or a seat that was disabled
  # by hand, both land here and give the VRAM back.
  ear_down
}

tick() {
  local snap="$TMP_DIR/snap.tsv"
  if ! snapshot >"$snap"; then
    log "PipeWire unreadable — the watch waits"
    return 0
  fi
  # An empty graph read is not a quiet room: name it, so a broken scan can never
  # masquerade as "no call began".
  if ! grep -q '^SRC' "$snap"; then
    log "the graph read carried no sources — the watch waits"
    return 0
  fi
  local now
  now="$(date +%s)"

  if [ "$PHASE" = "idle" ]; then
    if [ "$now" -lt "$COOLDOWN_UNTIL" ]; then
      # inside the anti-flap quiet: keep the baseline current, arm nothing
      rebaseline
      return 0
    fi
    local new talk talk_key key triggers
    new="$(awk -F'\t' -v base="$BASELINE" '
      BEGIN { n = split(base, b, ","); for (i = 1; i <= n; i++) if (b[i] != "") was[b[i]] = 1 }
      { if (!($1 in was)) print $1 }' <<<"$(mic_holders "$snap")" | sort -n | paste -sd, -)"
    talk="$(talkback_pids "$snap" "$BASELINE_PIDS" "$BASELINE_SI")"
    talk_key=""
    [ -n "$talk" ] && talk_key="$(printf '%s\n' "$talk" | cut -f1 | sort -n | paste -sd, -)"

    key="$new"
    [ -n "$talk_key" ] && key="${key:+$key|}talk:$talk_key"
    if [ -z "$key" ]; then
      PENDING_KEY=""
      PENDING_SINCE=0
      return 0
    fi
    if [ "$key" != "$PENDING_KEY" ]; then
      PENDING_KEY="$key"
      PENDING_SINCE="$now"
      return 0
    fi
    [ $((now - PENDING_SINCE)) -ge "$ARM_DEBOUNCE" ] || return 0

    triggers="$new"
    if [ -z "$triggers" ]; then
      # talkback-only arm: the mic was already held, so the trigger set is the
      # streams of the app whose remote side began.
      triggers="$(awk -F'\t' -v pids="$talk_key" '
        BEGIN { n = split(pids, p, ","); for (i = 1; i <= n; i++) if (p[i] != "") want[p[i]] = 1 }
        $1 == "SO" { if ($5 in want) print $2 }' "$snap" | sort -n | paste -sd, -)"
    fi
    # ── THE CALL GATE (2026-09-28) ────────────────────────────────────────
    # A mic grab is NOT a meeting. On 2026-09-28 this watch armed on a seat where
    # nobody was in a call, because an idle Chromium mic hold looks identical to a
    # call to anything that only asks "does an app hold the mic?" — it recorded the
    # room and announced the same minutes over and over. Require a stream that
    # CARRIES a call role (`media.role`), or an explicit arm written by the Thing
    # room or the operator. bin/time/snotra/snotra-iscall.sh is the one owner of that call.
    _iscall="$(door snotra-iscall.sh 2>/dev/null || true)"
    [ -n "$_iscall" ] && [ -x "$_iscall" ] || _iscall="${HOME}/.fleet/snotra-iscall.sh"
    if [ -x "$_iscall" ] && ! "$_iscall" >/dev/null 2>&1; then
      log "no call: $("$_iscall" --why 2>/dev/null || printf 'no call role on any mic stream')"
      PENDING_KEY=""
      PENDING_SINCE=0
      return 0
    fi
    if do_arm "$snap" "$triggers" "$BASELINE"; then
      PHASE="in-call"
      TRIGGERS="$triggers"
      ARM_EPOCH="$now"
      RELEASED_SINCE=0
      QUIET_SINCE=0
      LAST_PROBE=0
      LAST_LEVEL=""
      CALL_SINK="$(state_get sink)"
      CALL_MONITOR="$(state_get monitor)"
      CALL_MIC="$(state_get mic)"
    else
      PENDING_KEY=""
      PENDING_SINCE=0
    fi
    return 0
  fi

  # ── in-call ──
  local live triggers_now
  live="$(mic_holders "$snap")"
  triggers_now="$(awk -F'\t' -v want="$TRIGGERS" '
    BEGIN { n = split(want, w, ","); for (i = 1; i <= n; i++) if (w[i] != "") t[w[i]] = 1 }
    { if ($1 in t) print $1 }' <<<"$live" | sort -n | paste -sd, -)"

  # L1 — the mic released by every stream that armed the ear.
  if [ -z "$triggers_now" ]; then
    [ "$RELEASED_SINCE" -ne 0 ] || RELEASED_SINCE="$now"
    if [ $((now - RELEASED_SINCE)) -ge "$RELEASE_GRACE" ]; then
      do_leave "mic released"
      back_to_idle
      return 0
    fi
  else
    RELEASED_SINCE=0
  fi

  # L2 — the call's own sink left the graph (the device the room was using).
  if [ -n "$CALL_SINK" ] && ! sink_present "$snap" "$CALL_SINK"; then
    do_leave "call sink gone"
    back_to_idle
    return 0
  fi

  # L4 — the capture's own hard cap.
  if [ $((now - ARM_EPOCH)) -ge "$MAX_SECONDS" ]; then
    do_leave "safety cap"
    back_to_idle
    return 0
  fi

  # L3 — the room quiet, mic and monitor together, for the named stretch.
  if [ $((now - LAST_PROBE)) -ge "$PROBE_SECONDS" ]; then
    local mon micv level
    mon="$CALL_MONITOR"; micv="$CALL_MIC"
    [ -n "$mon" ] || mon="$(default_sink).monitor"
    [ -n "$micv" ] || micv="$(default_source)"
    if [ -n "$mon" ] && [ -n "$micv" ]; then
      level="$(probe_level "$mon" "$micv")"
      LAST_PROBE="$now"
      LAST_LEVEL="$level"
    fi
  fi
  if [ -n "$LAST_LEVEL" ] && awk -v v="$LAST_LEVEL" -v f="$SILENCE_DB" 'BEGIN { exit !(v + 0 < f + 0) }'; then
    [ "$QUIET_SINCE" -ne 0 ] || QUIET_SINCE="$now"
    if [ $((now - QUIET_SINCE)) -ge "$SILENCE_SECONDS" ]; then
      do_leave "room quiet ${SILENCE_SECONDS}s"
      back_to_idle
      return 0
    fi
  else
    QUIET_SINCE=0
  fi
  return 0
}

# ── the loop: event-driven on the PipeWire bus, with a periodic tick ────────
start_subscribe() {
  rm -f "$TMP_DIR/events"
  mkfifo "$TMP_DIR/events" 2>/dev/null || return 1
  pactl subscribe >"$TMP_DIR/events" 2>/dev/null &
  SUB_PID=$!
  eval "exec $FIFO_FD< '$TMP_DIR/events'" 2>/dev/null || return 1
  return 0
}

run() {
  have pactl || { say "error: pactl is absent — the watch cannot read PipeWire" >&2; return 1; }
  have python3 || { say "error: python3 is absent — the watch cannot read the graph" >&2; return 1; }
  mkdir -p "$MEETINGS" "$STATE_DIR" 2>/dev/null || true
  log "watch started (poll ${POLL_SECONDS}s, arm ${ARM_DEBOUNCE}s, grace ${RELEASE_GRACE}s, quiet ${SILENCE_SECONDS}s @ ${SILENCE_DB} dB)"

  # Crash recovery: an in-call context that survived a restart is resumed; one
  # whose capture already died is finalized rather than abandoned.
  # A capture left behind by a crash is not a meeting in progress: close it.
  if [ "$(state_get phase)" != "in-call" ]; then
    capture_alive && log "a capture was left without a watch — closing it"
    stop_lingering_captures
    [ -r "$CAPTURE_STATE" ] && ! capture_alive && rm -f "$CAPTURE_STATE" "$LISTENING_FILE" 2>/dev/null
  fi

  if [ "$(state_get phase)" = "in-call" ]; then
    TRIGGERS="$(state_get triggers)"
    ARM_EPOCH="$(state_get armed_epoch)"
    CALL_SINK="$(state_get sink)"
    CALL_MONITOR="$(state_get monitor)"
    CALL_MIC="$(state_get mic)"
    case "$ARM_EPOCH" in ''|*[!0-9]*) ARM_EPOCH="$(date +%s)" ;; esac
    if capture_alive; then
      PHASE="in-call"
      log "resumed an in-call watch ($(state_get slug))"
    else
      log "an in-call watch was left without a live capture — finalizing"
      do_leave "recovered after restart"
    fi
  fi

  rebaseline
  start_subscribe || { say "error: cannot watch the PipeWire bus" >&2; return 1; }
  # A tick is not free of the bus it watches. Every snapshot opens four pactl
  # clients and a python3, and each of those connects and disconnects on the same
  # PipeWire bus that pactl subscribe reports — so a tick generates the events
  # that wake the read that runs the next tick. Left event-triggered, the watch
  # hears only its own hands: measured 2026-11-04 at 178 forks/second and ~0.85
  # of a core, on a machine where nothing was happening.
  # So a tick is spaced: when one is due, run it; when one is not, block on the bus
  # for the remainder of the floor and swallow what arrives. Blocking (not polling)
  # is what keeps the guard itself free — a `read -t 0` drain spins at 97% CPU.
  local line="" rc=0 last_tick_us=0 now_us=0 gap_us=$(( TICK_MIN_GAP_MS * 1000 )) rem_us=0 rem_s=""
  while :; do
    line="" rc=0
    if ! IFS= read -r -t "$POLL_SECONDS" -u "$FIFO_FD" line; then
      rc=$?
      if [ "$rc" -le 128 ]; then
        # EOF: the subscriber left (PipeWire restarted). Re-seat it.
        eval "exec $FIFO_FD<&-" 2>/dev/null || true
        kill "$SUB_PID" 2>/dev/null || true
        SUB_PID=""
        sleep 2
        start_subscribe || { sleep 5; continue; }
      fi
    fi
    now_us="${EPOCHREALTIME//[!0-9]/}"
    rem_us=$(( gap_us - ( now_us - last_tick_us ) ))
    if [ "$rem_us" -gt 0 ]; then
      printf -v rem_s '%d.%06d' $(( rem_us / 1000000 )) $(( rem_us % 1000000 ))
      IFS= read -r -t "$rem_s" -u "$FIFO_FD" _ || true
      continue
    fi
    tick || log "tick failed"
    last_tick_us="${EPOCHREALTIME//[!0-9]/}"
  done
}

# ── the proofs and the manual doors ────────────────────────────────────────
status() {
  local phase slug outfile armed cap="idle"
  phase="$(state_get phase)"
  slug="$(state_get slug)"
  outfile="$(state_get outfile)"
  armed="$(state_get armed_epoch)"
  capture_alive && cap="active"
  say "snotra-detect[1]{phase,slug,capture,since,recording}:"
  say "  \"${phase:-idle}\",\"${slug:--}\",\"$cap\",\"${armed:--}\",\"${outfile:--}\""
  [ "$phase" = "in-call" ] && return 0
  return 1
}

scan() {
  local snap="$TMP_DIR/snap.tsv"
  snapshot >"$snap" || { say "error: PipeWire unreadable" >&2; return 1; }
  say "mic holders:"
  mic_holders "$snap" | awk -F'\t' '{ printf "  so=%-7s app=%-24s pid=%-8s source=%s\n", $1, $2, $3, $4 }'
  say "default sink:   $(default_sink)"
  say "default source: $(default_source)"
  local lvl
  lvl="$(probe_level "$(default_sink).monitor" "$(default_source)")"
  say "room level:     ${lvl:-unknown} dB"
}

case "${1:-}" in
  run)    run ;;
  status) status ;;
  scan)   scan ;;
  once)   rebaseline; tick ;;
  arm)
    shift
    rebaseline
    if ! snapshot >"$TMP_DIR/snapA.tsv"; then say "error: PipeWire unreadable" >&2; exit 1; fi
    arm_forced="${1:-}"
    arm_holder="$(mic_holders "$TMP_DIR/snapA.tsv" | head -1)"
    if [ -z "$arm_holder" ] && [ -z "$arm_forced" ]; then
      say "error: no application holds the microphone — nothing to arm" >&2
      exit 1
    fi
    arm_so="$(printf '%s' "$arm_holder" | cut -f1)"
    if do_arm "$TMP_DIR/snapA.tsv" "$arm_so" "$BASELINE" "$arm_forced"; then
      say "snotra: armed by hand — stop it with 'snotra-detect.sh leave'"
    else
      exit 1
    fi ;;
  leave)
    if [ -z "$(state_get phase)" ]; then
      say "error: no capture is armed by the watch" >&2
      exit 1
    fi
    do_leave "manual leave" ;;
  *) say "error: unknown command (run|status|scan|once|arm|leave)" >&2; exit 2 ;;
esac
