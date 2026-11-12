#!/usr/bin/env bash
# systems/snotra/services/ear/snotra-live.sh — the live tail door (plan 129).
#
# The shim that once stood at systems/snotra/services/snotra-live.sh is retired
# by docs/fixes/snotra/2026-10-24-snotra-becomes-a-system.md; this is the door
# itself, and the move is recorded in .agents/paths-ledger.yaml. The shim's
# pointer at the top of this file was removed 2026-11-12: it aimed at a path
# that does not exist, so the door answered 127 instead of listening.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo root, found by walking up to the tree that carries RULES/ and
# .agents/ — the old `../../../../` from services/ear/ landed one level above
# the repo, so the rail resolver and the rune append were pointed at nothing.
REPO_ROOT="$SCRIPT_DIR"
while [ "$REPO_ROOT" != / ] && { [ ! -d "$REPO_ROOT/RULES" ] || [ ! -d "$REPO_ROOT/.agents" ]; }; do REPO_ROOT="$(dirname "$REPO_ROOT")"; done
{ [ -d "$REPO_ROOT/RULES" ] && [ -d "$REPO_ROOT/.agents" ]; } || REPO_ROOT=""
if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  for _lib in ${REPO_ROOT:+"$REPO_ROOT/bin/vault/hoard-lib.sh"} "$SCRIPT_DIR/hoard-lib.sh"; do
    [ -r "$_lib" ] && { . "$_lib"; YMIR_HOARD_LIB_LOADED=1; break; }
  done
  unset _lib
fi
if [ -z "${YMIR_HOME:-}" ] && command -v ymir_home_root >/dev/null 2>&1; then
  ymir_home_root YMIR_HOME
fi
[ -n "${YMIR_HOME:-}" ] || {
  printf 'error: the hoard home is unresolved — bin/vault/hoard-lib.sh answered nothing\n' >&2
  printf 'help: run the door from the repo, or set YMIR_HOME\n' >&2
  exit 2
}

HOARD="$YMIR_HOME/hodd/life/meetings"
STATE="$YMIR_HOME/state"
WORK="$STATE/snotra-live"
SLICES="$WORK/slices"
LISTENING_FILE="$STATE/.snotra-listening"
SEG="${SNOTRA_LIVE_SEGMENT_SECONDS:-6}"
LANE="${SNOTRA_LANE:-ping}"
ENGINE_PREFIX="${SNOTRA_ENGINE_PREFIX:-$HOME/.local/opt/whisper.cpp}"

mkdir -p "$HOARD" "$STATE" "$WORK" 2>/dev/null || true

say() { printf '%s\n' "$*"; }

# THE ONE DOCUMENT. Every writer and every reader names it through this door —
# an earlier draft had the worker appending to a copy under state/ while `tail`
# and the harvest read the file in the hoard, so the words grew in one place and
# were read in another. There is now exactly one path.
doc_path() { cat "$WORK/docpath" 2>/dev/null; }

have_pactl() { command -v pactl >/dev/null 2>&1; }

default_source() {
  if have_pactl; then pactl get-default-source 2>/dev/null && return; fi
  wpctl status 2>/dev/null | awk '/Sources:/{f=1} f&&/\*/{print $2; exit}'
}

default_sink() {
  if have_pactl; then pactl get-default-sink 2>/dev/null && return; fi
  wpctl status 2>/dev/null | awk '/Sinks:/{f=1} f&&/\*/{print $2; exit}'
}

# ── the engine: DISCOVERED, never assumed (the same order snotra-transcribe.sh uses)
find_whisper() {
  if [ -n "${SNOTRA_WHISPER_BIN:-}" ] && [ -x "$SNOTRA_WHISPER_BIN" ]; then
    printf '%s' "$SNOTRA_WHISPER_BIN"; return 0
  fi
  local c
  for c in whisper-cli whisper-cpp whisper; do
    if command -v "$c" >/dev/null 2>&1; then command -v "$c"; return 0; fi
  done
  local p
  for p in \
    "$HOME/whisper.cpp.src/build/bin/whisper-cli" \
    "$HOME/whisper.cpp/build/bin/whisper-cli" \
    "$HOME/whisper.cpp.src/build/bin/main" \
    "$HOME/whisper.cpp/build/bin/main" \
    "$ENGINE_PREFIX/bin/whisper-cli" \
    "/usr/local/bin/whisper-cli" \
    "/usr/bin/whisper-cli"; do
    if [ -x "$p" ]; then printf '%s' "$p"; return 0; fi
  done
  return 1
}

find_model() {
  if [ -n "${SNOTRA_WHISPER_MODEL:-}" ] && [ -f "$SNOTRA_WHISPER_MODEL" ]; then
    printf '%s' "$SNOTRA_WHISPER_MODEL"; return 0
  fi
  local p
  for p in \
    "$HOME/whisper.cpp/models/ggml-small.en.bin" \
    "$HOME/whisper.cpp/models/ggml-base.en.bin" \
    "$HOME/.local/share/voxtype/models/ggml-small.en.bin" \
    "$HOME/.local/share/voxtype/models/ggml-base.en.bin" \
    "$HOME/whisper.cpp/models/ggml-base.en.bin" \
    "/usr/share/whisper.cpp/models/ggml-small.en.bin" \
    "/usr/share/whisper/models/ggml-small.en.bin"; do
    if [ -f "$p" ]; then printf '%s' "$p"; return 0; fi
  done
  return 1
}

# The rail model for the minutes, resolved the way the seat RESOLVES it — and NOT
# by taking the resolver's first model.
#
# The resolver answers with every alias the rail serves, and `models[0]` on this
# seat is `apodex-1.0-mini`: 21.7 GB and ~36 s for a summary, against ~5,864 MiB
# and ~15 s for the summarizer preset. Taking the first entry is how the meeting
# summarizer was once found holding the wrong model (2026-10-01, recorded in the
# box's own notes). So: the explicit env wins, then the seat's RECORDED choice —
# the same `SNOTRA_RAIL_MODEL` the watch's unit drop-in carries — and only then
# the resolver, as the last resort.
resolve_rail_model() {
  local m="${SNOTRA_RAIL_MODEL:-${RAIL_MODEL:-}}"
  [ -n "$m" ] && { printf '%s' "$m"; return 0; }

  local dropin
  for dropin in "$HOME"/.config/systemd/user/snotra-detect.service.d/*.conf; do
    [ -r "$dropin" ] || continue
    m="$(sed -n 's/^Environment=SNOTRA_RAIL_MODEL=\(.*\)$/\1/p' "$dropin" | head -1)"
    [ -n "$m" ] && { printf '%s' "$m"; return 0; }
  done

  local resolver="${REPO_ROOT:+$REPO_ROOT/bin/model/rail-resolve.sh}"
  [ -x "$resolver" ] || return 1
  bash "$resolver" resolve --json 2>/dev/null | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: d={}
m=(d.get("serving") or {}).get("models") or []
print(m[0] if m else "")' 2>/dev/null || true
}

# The rail is the largest claim on the card and a meeting is the thing that
# matters while it is happening: before a slice, if CUDA is starved, yield the
# rail. This is the same yield snotra-transcribe.sh makes (SNOTRA_FREE_RAIL).
ensure_vram() {
  [ "${SNOTRA_FREE_RAIL:-1}" = "0" ] && return 0
  [ -r "$HOME/.local/bin/voice-gpu-lib.sh" ] || return 0
  local free
  free=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null | head -1)
  case "${free:-}" in ''|*[!0-9]*) return 0 ;; esac
  [ "$free" -ge 2048 ] && return 0
  ( . "$HOME/.local/bin/voice-gpu-lib.sh" 2>/dev/null; voice_ensure_vram 2048 >/dev/null 2>&1 ) || true
}

alive() { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }

# A slice's own offset from the start of the tail, as HH:MM:SS. Contiguous from
# zero, so the index IS the time.
human_ts() {
  local total=$(( ${1:-0} * SEG ))
  printf '%02d:%02d:%02d' $(( total / 3600 )) $(( (total % 3600) / 60 )) $(( total % 60 ))
}

# Whisper's silences are not words. `[BLANK_AUDIO]`, "(silence)", "(upbeat
# music)" — none of them is something the Allfather said, and none belongs in the
# record. A whole annotation is dropped too: whisper labels sound it cannot place
# as "(air whooshing)", "(footsteps)", "(clicking)", and a transcript of what was
# SAID should not carry a line that is only a noise label.
is_noise() {
  local t="${1:-}"
  # The underscore must SURVIVE normalisation: deleting it turns whisper's
  # `BLANK_AUDIO` into `blankaudio`, which no longer matches the pattern that
  # names it — so the loudest silence of all sailed straight into the record.
  # whisper's VAD writes `[_BLANK_AUDIO_]` with the underscores INSIDE the
  # brackets, so the surviving underscores are trimmed before matching.
  case "$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]' | tr -d '[]()*. ' | sed 's/^_*//; s/_*$//')" in
    ''|blank_audio|silence|inaudible|beep*|silence_*) return 0 ;;
  esac
  # entirely a parenthetical annotation -> nothing was spoken in this slice
  case "$(printf '%s' "$t" | tr -d '[:space:]')" in
    '('*')') return 0 ;;
  esac
  return 1
}

# pick_backend <dir> — see snotra-transcribe.sh: GGML_BACKEND_PATH takes one
# kernel file, so the choice is made from /proc/cpuinfo (haswell = AVX2+FMA,
# x64 = the floor). A build tree has no backends/ and never reaches this.
pick_backend() {
  local d="$1" flags p
  flags="$(grep -m1 '^flags' /proc/cpuinfo 2>/dev/null || true)"
  for p in sapphirerapids skylakex haswell sse42 x64; do
    case "$p" in
      sapphirerapids) printf '%s' "$flags" | grep -qw avx512vnni || continue ;;
      skylakex) printf '%s' "$flags" | grep -qw avx512f || continue ;;
      haswell) printf '%s' "$flags" | grep -qw avx2 || continue ;;
      sse42) printf '%s' "$flags" | grep -qw sse4_2 || continue ;;
    esac
    [ -f "$d/libggml-cpu-$p.so" ] && { printf '%s' "$d/libggml-cpu-$p.so"; return 0; }
  done
  p="$(ls "$d"/libggml-cpu-*.so 2>/dev/null | head -1)"
  [ -n "$p" ] && printf '%s' "$p"
  return 0
}

# ── the worker: turn finished slices into lines in the document ────────────────
# A slice is COMPLETE only when the NEXT slice exists — the segment muxer writes
# sequentially, so the newest file is always the one being written. That is why
# this loop can never transcribe half a word.
transcribe_slice() {
  local wav="$1"
  [ -s "$wav" ] || return 0
  local bin model out
  bin="$(find_whisper)" || return 0
  model="$(find_model || true)"
  ensure_vram
  out="$WORK/.slice.$$"
  (
    local bindir
    bindir="$(dirname "$bin")"
    export LD_LIBRARY_PATH="$bindir:$(dirname "$bindir")/lib:${LD_LIBRARY_PATH:-}"
    if [ -z "${GGML_BACKEND_PATH:-}" ] && [ -d "$(dirname "$bindir")/backends" ]; then
      _backend="$(pick_backend "$(dirname "$bindir")/backends")"
      [ -n "$_backend" ] && export GGML_BACKEND_PATH="$_backend"
    fi
    # a 16 kHz mono slice carries no speaker split, so `-di` never applies
    if [ -n "$model" ]; then
      "$bin" -m "$model" -f "$wav" -l en -nt -np -otxt -of "$out" >/dev/null 2>&1
    else
      "$bin" -f "$wav" -l en -nt -np -otxt -of "$out" >/dev/null 2>&1
    fi
  )
  local text=""
  [ -f "$out.txt" ] && text="$(tr '\n' ' ' < "$out.txt")"
  rm -f "$out.txt"
  # collapse whitespace: a slice is one thought, and a rolling document reads as
  # prose, not as wrapped STT fragments
  printf '%s' "$text" | tr -s ' \t' ' ' | sed 's/^ *//; s/ *$//'
}

emit_slice() {
  local wav="$1" idx="$2" text ts
  text="$(transcribe_slice "$wav")"
  is_noise "$text" && return 0
  ts="$(human_ts "$idx")"
  printf '[%s] %s\n' "$ts" "$text" >> "$(doc_path)"
  printf '%s %s\n' "$idx" "$(human_ts "$idx")" >> "$WORK/progress"
}

worker() {
  local cursor=0 i n limit s
  while :; do
    if [ -f "$WORK/stop" ]; then
      # DRAIN: at the leave the newest slice is complete too, because ffmpeg is
      # gone. Nothing spoken may be dropped at the door.
      mapfile -t all < <(ls -1 "$SLICES" 2>/dev/null | sort)
      for ((i=cursor; i<${#all[@]}; i++)); do
        emit_slice "$SLICES/${all[$i]}" "$i"
        cursor=$((i+1))
      done
      echo "$cursor" > "$WORK/cursor"
      exit 0
    fi
    mapfile -t all < <(ls -1 "$SLICES" 2>/dev/null | sort)
    n=${#all[@]}
    limit=$(( n - 1 ))          # the newest slice is still being written
    [ "$limit" -lt 0 ] && limit=0
    for ((i=cursor; i<limit; i++)); do
      emit_slice "$SLICES/${all[$i]}" "$i"
      cursor=$((i+1))
      echo "$cursor" > "$WORK/cursor"
    done
    sleep 1
  done
}

# ── the doors ────────────────────────────────────────────────────────────────
do_start() {
  local slug="${1:-note}" topic="${2:-$1}"
  slug="$(printf '%s' "$slug" | tr -c 'a-zA-Z0-9._-' '-' | sed 's/^-*//; s/-*$//')"
  [ -n "$slug" ] || slug="note"

  # THE ALLFATHER'S LAW (2026-10-31): the microphone is NEVER used to hear an
  # online meeting. The live tail is the LOCAL ROOM door — people physically in
  # the room — and an online meeting is heard by the bot (snotra-bot.sh), which
  # joins the call itself and needs no microphone here at all.
  if [ "${SNOTRA_LOCAL_ROOM:-0}" != "1" ]; then
    say "refused: the mic is for a LOCAL room only — never an online meeting"
    say "hint: an online meeting is heard by the BOT — snotra-bot.sh join <meet-url>"
    say "hint: tail your own room only with SNOTRA_LOCAL_ROOM=1"
    exit 2
  fi

  if alive "$(cat "$WORK/ffmpeg.pid" 2>/dev/null)"; then
    say "error: a live tail is already running — 'snotra-live.sh status', or stop it first"; exit 1
  fi
  if alive "$(cat "$STATE/.snotra-pid" 2>/dev/null)"; then
    say "error: snotra-capture.sh is recording — ONE ear at a time. Stop it first."; exit 1
  fi

  local mic; mic="${SNOTRA_MIC:-$(default_source)}"
  [ -n "$mic" ] || { say "error: no microphone resolved; set SNOTRA_MIC"; exit 1; }

  rm -rf "$SLICES"; mkdir -p "$SLICES"
  rm -f "$WORK/stop" "$WORK/progress" "$WORK/cursor" "$WORK/doc" "$WORK/docpath"

  local date base
  date="$(date +%Y-%m-%d)"
  base="${date}-${LANE}-${slug}"
  # The LIVE document is its own name. The minutes the pipeline writes at the
  # leave take `$base.md` — the same name the watch's finalize uses — so the
  # rolling record and the polished summary can never overwrite each other.
  printf '%s\n' "$base" > "$WORK/base"
  printf '%s\n' "$base.live.md" > "$WORK/docname"
  printf '%s\n' "$HOARD/$base.live.md" > "$WORK/docpath"
  : > "$(doc_path)"
  printf '%s\n' "$topic" > "$WORK/topic"
  date -Is > "$WORK/started"

  {
    printf '# %s — live transcript\n\n' "$base"
    printf -- '- started: %s\n' "$(date -Is)"
    printf -- '- source: %s (microphone only)\n' "$mic"
    printf -- '- engine: %s\n' "$(find_whisper || echo 'NOT FOUND')"
    printf -- '- model: %s\n' "$(find_model || echo 'NOT FOUND')"
    printf -- '- slice: %ss (so the text trails the voice by about that much)\n' "$SEG"
    printf -- '- machine transcription; wording may be imperfect, no speaker diarization.\n\n'
    printf '> The lines below are written as they are spoken. `snotra-live.sh stop` closes the book.\n\n'
  } >> "$(doc_path)"

  local monitor="${SNOTRA_LIVE_MONITOR:-0}"
  local -a DUR=( -t "${SNOTRA_MAX_SECONDS:-14400}" )

  say "The live tail opens…"
  say "  Microphone: $mic"
  if [ "$monitor" = "1" ]; then
    local sink; sink="$(default_sink)"
    [ -n "$sink" ] && case "$sink" in *.monitor) ;; *) sink="$sink.monitor" ;; esac
    say "  Monitor:    $sink (both sides)"
    ffmpeg -y -hide_banner -loglevel error \
      -f pulse -i "$mic" -f pulse -i "$sink" \
      -filter_complex "[0:a][1:a]amix=inputs=2:duration=longest:dropout_transition=0" \
      -vn -ar 16000 -ac 1 -c:a pcm_s16le \
      -f segment -segment_time "$SEG" -segment_atclocktime 1 -reset_timestamps 1 \
      "${DUR[@]}" "$SLICES/seg-%04d.wav" >"$WORK/ffmpeg.log" 2>&1 &
  else
    ffmpeg -y -hide_banner -loglevel error \
      -f pulse -i "$mic" \
      -vn -ar 16000 -ac 1 -c:a pcm_s16le \
      -f segment -segment_time "$SEG" -segment_atclocktime 1 -reset_timestamps 1 \
      "${DUR[@]}" "$SLICES/seg-%04d.wav" >"$WORK/ffmpeg.log" 2>&1 &
  fi
  local ff=$!
  echo "$ff" > "$WORK/ffmpeg.pid"

  sleep 1
  if ! alive "$ff"; then
    say "error: the capture died at once — see $WORK/ffmpeg.log"; rm -f "$WORK/ffmpeg.pid"; exit 1
  fi

  # The worker MUST NOT inherit this script's stdout: a background child holding
  # the pipe open makes `snotra-live.sh start | tee` hang forever, because the
  # shell waits for every writer to the pipe, not just the first.
  ( worker ) >/dev/null 2>&1 &
  echo $! > "$WORK/worker.pid"
  echo "live" > "$LISTENING_FILE"

  local base_name; base_name="$(cat "$WORK/docname")"
  say "LIVE — listening. The document grows here:"
  say "  $HOARD/$base_name"
  say "  follow:  snotra-live.sh tail"
  say "  close:   snotra-live.sh stop"
}

do_status() {
  local ff worker_pid cursor base_name
  ff="$(cat "$WORK/ffmpeg.pid" 2>/dev/null)"
  worker_pid="$(cat "$WORK/worker.pid" 2>/dev/null)"
  cursor="$(cat "$WORK/cursor" 2>/dev/null || echo 0)"
  base_name="$(cat "$WORK/docname" 2>/dev/null)"
  if ! alive "$ff"; then
    say "live_tail{state:stopped}"
    exit 0
  fi
  say "live_tail{state:listening,ffmpeg:$ff,worker:${worker_pid:-none},slices_done:$cursor,doc:$(doc_path)}"
  local last; last="$(grep -E '^\[' "$(doc_path)" 2>/dev/null | tail -1)"
  [ -n "$last" ] && say "  $last"
}

do_tail() {
  local path; path="$(doc_path)"
  [ -n "$path" ] && [ -f "$path" ] || { say "error: no live tail is running"; exit 1; }
  say "— following $(basename "$path") (ctrl-c stops following, NOT the tail — use 'stop') —"
  tail -n 20 -f "$path"
}

# Join the slices back into one recording: the pipeline needs a single WAV, and
# the slices are the recording. It PRINTS the path on success — the caller must be
# able to tell "joined" from "could not join", and an earlier draft returned only
# an exit code, so a stop could never know it had a recording to hand over.
join_wav() {
  local base="$1" out="$HOARD/$base.wav" list="$WORK/concat.txt"
  : > "$list"
  local f
  for f in "$SLICES"/seg-*.wav; do
    [ -f "$f" ] || continue
    printf "file '%s'\n" "$f" >> "$list"
  done
  [ -s "$list" ] || return 1
  ffmpeg -y -hide_banner -loglevel error -f concat -safe 0 -i "$list" -c copy "$out" >/dev/null 2>&1 || return 1
  [ -s "$out" ] || return 1
  printf '%s' "$out"
}

do_stop() {
  local ff worker_pid
  ff="$(cat "$WORK/ffmpeg.pid" 2>/dev/null)"
  worker_pid="$(cat "$WORK/worker.pid" 2>/dev/null)"
  if ! alive "$ff" && [ ! -f "$WORK/docname" ]; then
    say "error: no live tail is running"; exit 1
  fi

  say "The live tail closes…"
  # 1) silence the ear first, so the newest slice is finished and complete
  if alive "$ff"; then kill "$ff" 2>/dev/null; local n=0
    while alive "$ff" && [ "$n" -lt 20 ]; do sleep 0.5; n=$((n+1)); done
    alive "$ff" && kill -9 "$ff" 2>/dev/null
  fi
  rm -f "$WORK/ffmpeg.pid"

  # 2) tell the worker to drain the last slice, and wait for it
  : > "$WORK/stop"
  n=0
  while alive "$worker_pid" && [ "$n" -lt 120 ]; do sleep 0.5; n=$((n+1)); done
  alive "$worker_pid" && kill -9 "$worker_pid" 2>/dev/null
  rm -f "$WORK/worker.pid" "$LISTENING_FILE"

  local base base_name topic minutes transcript actions
  base="$(cat "$WORK/base" 2>/dev/null)"
  base_name="$(cat "$WORK/docname" 2>/dev/null)"
  topic="$(cat "$WORK/topic" 2>/dev/null)"
  minutes="$HOARD/$base.md"
  transcript="$HOARD/$base.transcript.txt"
  actions="$HOARD/$base.actions.md"

  local cursor; cursor="$(cat "$WORK/cursor" 2>/dev/null || echo 0)"
  say "  slices written: $cursor"

  local wav; wav="$(join_wav "$base" || true)"
  [ -n "$wav" ] && say "  recording: $wav"

  local transcribe="$SCRIPT_DIR/snotra-transcribe.sh"
  local mine="$SCRIPT_DIR/snotra-mine.sh"
  local rail_model; rail_model="$(resolve_rail_model || true)"

  # 3) the SAME pipeline the watch's finalize runs — never a second one.
  if [ "${SNOTRA_LIVE_SKIP_MINUTES:-0}" != "1" ] && [ -n "$wav" ] && [ -x "$transcribe" ]; then
    say "  writing the minutes (this transcribes the recording once more)…"
    SNOTRA_MINUTES_FILE="$minutes" \
    SNOTRA_TRANSCRIPT_FILE="$transcript" \
    RAIL_MODEL="$rail_model" \
      bash "$transcribe" "$wav" "$topic" >>"$WORK/pipeline.log" 2>&1 \
      && say "  minutes:   $minutes" \
      || say "  (minutes did not complete — the recording is kept at $wav)"
  else
    # no minutes: the rolling document IS the transcript, header stripped
    grep -E '^\[' "$(doc_path)" > "$transcript" 2>/dev/null || true
    say "  transcript: $transcript (from the live document)"
  fi

  if [ -x "$mine" ] && [ -s "$transcript" ]; then
    bash "$mine" "$transcript" "$actions" "$minutes" >>"$WORK/pipeline.log" 2>&1 || true
    say "  actions:   $actions"
  fi

  # 4) the Rune — every significant act is inscribed. The door's own signature is
  #    `runes-append.sh <actor> <event> --message "..."`; it refuses a bare
  #    positional, and it refuses LOUDLY, which is how the mis-call surfaced.
  local runes="${REPO_ROOT:+$REPO_ROOT/bin/records/runes-append.sh}"
  if [ -x "$runes" ]; then
    bash "$runes" "snotra-live" "live-tail-closed" \
      --message "the live tail closed — $base ($cursor slices from this machine's microphone); live document $HOARD/$base_name" \
      >>"$WORK/pipeline.log" 2>&1 || true
  fi

  rm -f "$WORK/docname" "$WORK/base" "$WORK/topic" "$WORK/stop" "$WORK/docpath"
  say "The book is closed.  $HOARD/$base_name"
  say "Minutes (if written): $minutes"
}

case "${1:-}" in
  start)  shift; do_start "${1:-note}" "${2:-}" ;;
  status) do_status ;;
  tail)   do_tail ;;
  stop)   do_stop ;;
  *)
    cat <<'USAGE'
The live tail — the microphone transcribed as it is spoken.

  snotra-live.sh start <slug> [topic]   begin; the document grows as you talk
  snotra-live.sh status                 one row, and the newest line
  snotra-live.sh tail                   follow the document
  snotra-live.sh stop                   close, then mine -> minutes -> Rune

The document lands in $YMIR_HOME/hodd/life/meetings/<date>-<lane>-<slug>.live.md
USAGE
    ;;
esac
