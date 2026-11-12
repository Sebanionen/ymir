#!/usr/bin/env bash
# snotra-transcribe.sh — transcribe a meeting recording and produce minutes.
#
# Usage:
#   snotra-transcribe.sh <recording.wav> [topic]
#
# Steps:
#   1. Normalize the audio to 16kHz mono (whisper's native rate)
#   2. Transcribe with the seat's whisper engine (discovered, never assumed)
#   3. Produce structured minutes in Markdown
#   4. Store minutes under $YMIR_HOME/hodd/life/meetings/
#   5. Append a Rune to the audit ledger
#
# Portable across the fleet: the engine is DISCOVERED on each seat —
#   heimdall  ~/whisper.cpp.src/build/bin/whisper-cli   (CUDA)
#   whynot    ~/whisper.cpp/build/bin/whisper-cli       (CUDA)
#   omarchy   /usr/bin/whisper-cli                      (extra/whisper-cpp)
#   fallback  voxtype transcribe                        (omarchy's bundled engine)
#
# Env:
#   YMIR_HOME          — the hoard root (default ~/Documents/ymirhome)
#   SNOTRA_WHISPER_BIN — explicit whisper binary override
#   SNOTRA_WHISPER_MODEL — explicit model override
#   WHISPER_GPU        — informational (whisper auto-detects CUDA)
#   RAIL_URL           — the OpenAI-compatible rail for summaries (default: the
#                        ONE living-rail resolver's serving box, bin/model/rail-resolve.sh;
#                        set it to force one specific rail)
#   RAIL_MODEL         — the model alias (env/personal; unset = loud refusal)
#   RAIL_KEY           — llama-swap API key (from ~/.pi/agent/auth.json)
#   SNOTRA_MINUTES_FILE   — explicit minutes path (default: <meetings>/meeting-<stamp>-minutes.md).
#                           The watch names the minutes after the meeting lane.
#   SNOTRA_TRANSCRIPT_FILE — also write the plain transcript to this path
#   SNOTRA_EAR_URL     — the fleet ear lane to transcribe on when THIS seat has no
#                        engine (default: the first live ear from the fleet registry's
#                        `ear` row, port SNOTRA_EAR_PORT=8322)

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo root, found by walking up to the tree that carries RULES/ and
# .agents/ — never a fixed number of `../`. The old resolver looked two levels
# up, which from services/ear/ is not the repo root, so the door died on an
# unbound YMIR_HOME the moment it ran outside a shell that already knew the home.
ROOT="$SCRIPT_DIR"
while [ "$ROOT" != / ] && { [ ! -d "$ROOT/RULES" ] || [ ! -d "$ROOT/.agents" ]; }; do ROOT="$(dirname "$ROOT")"; done
{ [ -d "$ROOT/RULES" ] && [ -d "$ROOT/.agents" ]; } || ROOT=""
# The ONE resolver (Rule 07): env -> the recorded choice -> the one default.
if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  for _yc in ${ROOT:+"$ROOT/bin/vault/hoard-lib.sh"} "$SCRIPT_DIR/hoard-lib.sh"; do
    [ -r "$_yc" ] && { . "$_yc"; YMIR_HOARD_LIB_LOADED=1; break; }
  done
  unset _yc
fi
if [ -z "${YMIR_HOME:-}" ] && command -v ymir_home_root >/dev/null 2>&1; then
  ymir_home_root YMIR_HOME
fi
[ -n "${YMIR_HOME:-}" ] || {
  printf 'error: the hoard home is unresolved — bin/vault/hoard-lib.sh answered nothing\n' >&2
  printf 'help: run the door from the repo, or set YMIR_HOME\n' >&2
  exit 2
}

YMIR_HOME="${YMIR_HOME}"
HOARD="$YMIR_HOME/hodd"
MEETINGS="$HOARD/workspaces/meetings"
ENGINE_PREFIX="${SNOTRA_ENGINE_PREFIX:-$HOME/.local/opt/whisper.cpp}"
WHISPER_GPU="${WHISPER_GPU:-on}"
# The rail is the LIVING rail (plan 51 Parts 9a/9c): the ear's summaries ride
# whichever strong box is CONNECTED, resolved by the ONE resolver. An explicit
# RAIL_URL still wins; the local seat's own rail is the last-ditch default.
RAIL_URL="${RAIL_URL:-}"
if [ -z "$RAIL_URL" ] && [ -x "$ROOT/bin/model/rail-resolve.sh" ]; then
  RAIL_URL="$(bash "$ROOT/bin/model/rail-resolve.sh" resolve --json 2>/dev/null | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: d={}
print((d.get("serving") or {}).get("url",""))' 2>/dev/null || true)"
fi
RAIL_URL="${RAIL_URL:-http://127.0.0.1:8080/v1}"
RAIL_MODEL="${RAIL_MODEL:-}"
RAIL_KEY="${RAIL_KEY:-}"
TMP_PREFIX="/tmp/snotra-$$"

# Loud refusal: no concrete model in the tree; the hoard or env must provide.
[ -n "$RAIL_MODEL" ] || {
  printf 'error: RAIL_MODEL is unset — set it in your hoard agents.yaml or\n'
  printf '  export RAIL_MODEL=provider/model-id\n'
  printf '  (the public tree carries no concrete model id)\n' >&2
  exit 2
}

mkdir -p "$MEETINGS"

say() { printf '%s\n' "$*"; }

# --- engine + model discovery ----------------------------------------------

find_whisper() {
  # 1) explicit override
  if [ -n "${SNOTRA_WHISPER_BIN:-}" ] && [ -x "$SNOTRA_WHISPER_BIN" ]; then
    printf '%s' "$SNOTRA_WHISPER_BIN"; return 0
  fi
  # 2) PATH (whisper-cli is the current name; whisper-cpp is the Arch package)
  local c
  for c in whisper-cli whisper-cpp whisper; do
    if command -v "$c" >/dev/null 2>&1; then command -v "$c"; return 0; fi
  done
  # 3) the fleet's known build trees (whisper-cli, then the deprecated `main`),
  #    then the no-root packaged copy snotra-ensure.sh seats
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
    "$HOME/.local/share/whisper.cpp/models/ggml-small.en.bin" \
    "/usr/share/whisper.cpp/models/ggml-small.en.bin" \
    "/usr/share/whisper/models/ggml-small.en.bin"; do
    if [ -f "$p" ]; then printf '%s' "$p"; return 0; fi
  done
  return 1
}

# Resolve the API key from auth.json if not set
if [ -z "$RAIL_KEY" ] && [ -f "$HOME/.pi/agent/auth.json" ]; then
  RAIL_KEY=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get("llama-swap",{}).get("key",""))' "$HOME/.pi/agent/auth.json" 2>/dev/null || true)
fi

# The fleet's ear lanes, in the registry's declared order. Prints one URL per
# line; the caller takes the first that answers.
resolve_ear_lane() {
  local url="${SNOTRA_EAR_URL:-}"
  [ -n "$url" ] && { printf '%s\n' "$url"; return 0; }
  local reg="$HOARD/data/fleet.json"
  [ -r "$reg" ] || return 1
  python3 - "$reg" "${SNOTRA_EAR_PORT:-8322}" <<'PY' 2>/dev/null || return 1
import json, sys
reg, port = sys.argv[1], sys.argv[2]
try:
    with open(reg, encoding="utf-8") as fh:
        d = json.load(fh)
except Exception:
    raise SystemExit(1)
hosts = d.get("hosts") or {}
for name in (d.get("ear") or []):
    row = hosts.get(name) or {}
    host = (row.get("tailnet") or row.get("lan") or "").split("://")[-1].split(":")[0]
    if host:
        print("http://%s:%s" % (host, port))
PY
}

# ear_transcribe <url> <audio> — the ear lane's /inference, one clip.
ear_transcribe() {
  local url="$1" audio="$2" out
  [ -s "$audio" ] || return 1
  curl -fsS --max-time 600 -X POST "${url%/}/inference" \
    -F "file=@${audio};type=audio/wav" -F "response_format=text" 2>/dev/null || return 1
}

# run_whisper <bin> <model|''> <audio> <extra flags…>
# audio_channels <file> — the channel count (1 or 2), empty when ffprobe cannot say.
audio_channels() {
  ffprobe -v error -select_streams a:0 -show_entries stream=channels \
    -of default=nw=1:nk=1 "$1" 2>/dev/null | head -1 | tr -d '[:space:]'
}

# pick_backend <dir> — the most specific CPU kernel this host can run.
#
# Debian/Ubuntu ship libggml as one .so per microarchitecture. ggml's own
# loader picks the best from a DIRECTORY, but GGML_BACKEND_PATH takes one FILE,
# so the choice is made from /proc/cpuinfo. `haswell` is the AVX2+FMA baseline
# and on this seat it ran 4.7x faster than the generic `x64` kernel (2.5 s
# against 11.8 s for an 8-second clip, measured 2026-11-12); `x64` is the floor
# that always runs. A build tree links its kernel statically and has no
# backends/, so it never reaches this.
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

# Writes "$TMP_PREFIX.txt"; returns non-zero when the engine failed.
# A build-tree binary needs its own directory on LD_LIBRARY_PATH (libwhisper.so);
# a packaged copy also carries lib/ and backends/ beside bin/.
# Run inside a subshell so a CUDA abort cannot print a signal message into the
# transcript path; the caller retries on the CPU.
run_whisper() {
  local bin="$1" model="$2" audio="$3"; shift 3
  local bindir libdir backenddir
  bindir="$(dirname "$bin")"
  libdir="$(dirname "$bindir")/lib"
  backenddir="$(dirname "$bindir")/backends"
  rm -f "$TMP_PREFIX.txt"
  # `-di` is the stereo-channel diarization: whisper compares the two channels'
  # energy over each segment and prefixes the text `(speaker 0)` / `(speaker 1)`.
  # It is only meaningful on a 2-channel capture (systems/snotra/services/ear/snotra-capture.sh's stereo
  # mode puts the mic on channel 0), and omitting it is harmless — a 2-channel
  # file decoded without `-di` is downmixed to mono by the decoder.
  local DI=""
  if [ "${SNOTRA_DIARIZE:-on}" != "off" ] && [ "$(audio_channels "$audio")" = "2" ]; then
    DI="-di"
  fi
  (
    export LD_LIBRARY_PATH="$bindir:$libdir:${LD_LIBRARY_PATH:-}"
    # A packaged copy's libggml loads its CPU kernel from backends/; name one
    # explicitly (the compiled-in path /usr/lib/.../ggml/backends0 does not
    # exist for an unprivileged copy). An already-exported choice wins.
    if [ -z "${GGML_BACKEND_PATH:-}" ] && [ -d "$backenddir" ]; then
      _backend="$(pick_backend "$backenddir")"
      [ -n "$_backend" ] && export GGML_BACKEND_PATH="$_backend"
    fi
    # --output-srt rides alongside the plain text: it is the ONLY output that
    # carries timestamps, and a mined action item without its moment cannot be
    # jumped to in the recording.
    if [ -n "$model" ]; then
      "$bin" -m "$model" -f "$audio" -l en $DI --output-txt --output-srt --output-file "$TMP_PREFIX" "$@"
    else
      "$bin" -f "$audio" -l en $DI --output-txt --output-srt --output-file "$TMP_PREFIX" "$@"
    fi
  ) >/dev/null 2>&1
  [ -s "$TMP_PREFIX.txt" ]
}

# Free VRAM in MiB (empty when nvidia-smi is unavailable).
free_vram_mb() {
  nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' '
}

do_transcribe() {
  local WAV="$1"
  local TOPIC="${2:-meeting}"
  local DATESTAMP
  DATESTAMP=$(date +%Y-%m-%d_%H%M%S)
  local MINUTES_FILE="${SNOTRA_MINUTES_FILE:-$MEETINGS/meeting-${DATESTAMP}-minutes.md}"
  local TRANSCRIPT_FILE="${SNOTRA_TRANSCRIPT_FILE:-}"

  if [ ! -f "$WAV" ]; then
    echo "error: recording not found: $WAV" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$MINUTES_FILE")" 2>/dev/null || true

  say "Transcribing: $WAV"
  say "Topic: $TOPIC"
  say "Seat: $(hostname -s 2>/dev/null || hostname)"

  # Step 1: normalize to 16kHz mono (whisper's native rate; keeps the engine
  #         identical on every seat regardless of what the capture wrote)
  local NORM="$TMP_PREFIX-16k.wav"
  if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -y -i "$WAV" -ar 16000 -ac 1 -c:a pcm_s16le "$NORM" >/dev/null 2>&1 || cp "$WAV" "$NORM"
  else
    cp "$WAV" "$NORM"
  fi

  # Step 2: transcribe — engine discovered, never assumed
  local WHISPER MODEL TRANSCRIPT
  WHISPER="$(find_whisper || true)"
  MODEL="$(find_model || true)"
  TRANSCRIPT=""

  if [ -n "$WHISPER" ] && [ -n "$MODEL" ]; then
    say "  engine: $WHISPER"
    say "  model:  $MODEL"
    # Choose the backend by available VRAM: a resident rail model starves CUDA
    # (heimdall <gpu> and whynot <gpu> both run one), so a tight card goes
    # straight to the CPU; otherwise try GPU and fall back on failure. Never a
    # silent empty transcript.
    local VRAM
    VRAM="$(free_vram_mb)"
    if [ -n "$VRAM" ] && [ "$VRAM" -ge 2048 ]; then
      run_whisper "$WHISPER" "$MODEL" "$NORM" "" || \
        run_whisper "$WHISPER" "$MODEL" "$NORM" "-ng" || true
    else
      [ -n "$VRAM" ] && say "  VRAM tight (${VRAM}MiB free) — transcribing on the CPU"
      run_whisper "$WHISPER" "$MODEL" "$NORM" "-ng" || \
        run_whisper "$WHISPER" "$MODEL" "$NORM" "" || true
    fi
    [ -f "$TMP_PREFIX.txt" ] && TRANSCRIPT="$(cat "$TMP_PREFIX.txt")"
    # The rail yields. A resident rail model is the single largest claim on a
    # strong box's VRAM — 13,790 MiB for the 262K MTP preset on heimdall — and
    # the meeting is the thing that matters while it is happening, so the rail
    # is the one that gives way. This path was written and left opt-in; it is
    # on by default now, and `SNOTRA_FREE_RAIL=0` is the deliberate override
    # for a seat that would rather wait than have its rail evicted.
    if [ -z "$TRANSCRIPT" ] && [ "${SNOTRA_FREE_RAIL:-1}" = 1 ] && [ -x "$HOME/.local/bin/voice-gpu-lib.sh" ]; then
      say "  GPU starved — freeing the rail and retrying"
      # shellcheck disable=SC1090
      . "$HOME/.local/bin/voice-gpu-lib.sh"
      voice_ensure_vram 2048 >/dev/null 2>&1 || true
      run_whisper "$WHISPER" "$MODEL" "$NORM" "" || true
      [ -f "$TMP_PREFIX.txt" ] && TRANSCRIPT="$(cat "$TMP_PREFIX.txt")"
    fi
  elif [ -n "$WHISPER" ]; then
    say "  engine: $WHISPER (no model found — transcribing with defaults)"
    run_whisper "$WHISPER" "" "$NORM" "" || true
    [ -f "$TMP_PREFIX.txt" ] && TRANSCRIPT="$(cat "$TMP_PREFIX.txt")"
  elif command -v voxtype >/dev/null 2>&1; then
    say "  engine: voxtype transcribe (the seat's bundled whisper)"
    TRANSCRIPT="$(voxtype transcribe "$NORM" 2>/dev/null || true)"
  else
    say "  WARNING: no whisper engine found on this seat"
    say "  Install: whisper-cli (extra/whisper-cpp) or build whisper.cpp"
  fi

  # A seat with no engine of its own still hears the meeting: the fleet's live
  # ear lane (whisper served at SNOTRA_EAR_PORT) transcribes the clip. Bounded by
  # what one HTTP body can carry — a full-length meeting belongs on a seat that
  # holds the engine, and that limit is named in the asset, not hidden here.
  if [ -z "$TRANSCRIPT" ] && [ -z "$WHISPER" ] && ! command -v voxtype >/dev/null 2>&1; then
    local EAR_URL EAR_TEXT
    EAR_URL="$(resolve_ear_lane || true)"
    if [ -n "$EAR_URL" ]; then
      say "  no local engine — transcribing on the fleet's ear lane"
      EAR_TEXT="$(ear_transcribe "$EAR_URL" "$NORM" || true)"
      if [ -n "$EAR_TEXT" ]; then
        TRANSCRIPT="$EAR_TEXT"
        say "  ear lane answered: $EAR_URL"
      else
        say "  the ear lane did not answer — no transcript"
      fi
    fi
  fi

  TRANSCRIPT="${TRANSCRIPT:-}"
# Whisper's channel labels made legible. The assignment is the capture's:
  # channel 0 is the operator's microphone, channel 1 is everyone else (the sink
  # monitor). A name map per recurring meeting (meetings/.speakers.yaml) is the
  # next step; until then these two labels are always true.
  if [ -n "$TRANSCRIPT" ]; then
    TRANSCRIPT="$(printf '%s\n' "$TRANSCRIPT" | sed \
      -e 's/(speaker 0)/[Me]/g' \
      -e 's/(speaker 1)/[Others]/g' \
      -e 's/(speaker ?)/[?]/g')"
  fi

  if [ -n "$TRANSCRIPT_FILE" ]; then
    mkdir -p "$(dirname "$TRANSCRIPT_FILE")" 2>/dev/null || true
    if [ -s "$TMP_PREFIX.srt" ]; then
      # The timestamped form the miner reads: [start --> end] the words.
      python3 - "$TMP_PREFIX.srt" "$TRANSCRIPT_FILE" <<'PY'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
TS = re.compile(r"^(\d{2}:\d{2}:\d{2})[,.](\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2})[,.](\d{3})\s*$")
out, buf, span = [], [], None
with open(src, encoding="utf-8", errors="replace") as fh:
    for line in fh:
        line = line.rstrip("\n")
        m = TS.match(line.strip())
        if m:
            if span and buf:
                out.append("[%s.%s --> %s.%s] %s" % (span[0], span[1], span[2], span[3], " ".join(buf).strip()))
            span, buf = (m.group(1), m.group(2), m.group(3), m.group(4)), []
            continue
        if line.strip().isdigit() and not buf:
            continue
        if span and line.strip():
            buf.append(line.strip())
if span and buf:
    out.append("[%s.%s --> %s.%s] %s" % (span[0], span[1], span[2], span[3], " ".join(buf).strip()))
with open(dst, "w", encoding="utf-8") as fh:
    fh.write("\n".join(out) + ("\n" if out else ""))
PY
    else
      printf '%s\n' "$TRANSCRIPT" > "$TRANSCRIPT_FILE"
    fi
  # the same labels, in the timestamped form the miner reads
  if [ -s "$TRANSCRIPT_FILE" ]; then
    sed -i -e 's/(speaker 0)/[Me]/g' -e 's/(speaker 1)/[Others]/g' \
           -e 's/(speaker ?)/[?]/g' "$TRANSCRIPT_FILE"
  fi
  fi

  # Step 3: produce structured minutes
  local DATE_TODAY HOUR
  DATE_TODAY=$(date +%Y-%m-%d)
  HOUR=$(date +%H:%M)

  cat > "$MINUTES_FILE" <<MINS
# Meeting Minutes — $DATE_TODAY

**Date:** $DATE_TODAY
**Time:** $HOUR
**Topic:** $TOPIC
**Source:** $WAV
**Seat:** $(hostname -s 2>/dev/null || hostname)

## Transcript

$TRANSCRIPT

## Decisions

_(pending AI summary)_

## Action Items

_(pending AI summary)_

---
*Generated by Snotra — the meeting ear*
MINS

  say "Minutes written: $MINUTES_FILE"

  # Step 4: summarize with the local rail (no cloud key)
  if [ -n "$RAIL_KEY" ] && [ -n "$TRANSCRIPT" ]; then
    say "  Summarizing with the rail: $RAIL_URL ($RAIL_MODEL)"
    local SUMMARY TEXT
    SUMMARY=$(curl -s --max-time 300 "$RAIL_URL/chat/completions" \
      -H "Authorization: Bearer $RAIL_KEY" \
      -H "Content-Type: application/json" \
      -d "$(python3 - "$RAIL_MODEL" "$TRANSCRIPT" <<'PY'
import json,sys
model, transcript = sys.argv[1], sys.argv[2]
print(json.dumps({
  "model": model,
  "messages": [
    {"role":"system","content":"You are a meeting minutes summarizer. Produce concise decisions and action items from the transcript."},
    {"role":"user","content":"Transcript:\n"+transcript[:20000]}
  ],
  "temperature": 0,
  "max_tokens": 1200
}))
PY
)" 2>/dev/null || true)

    if [ -n "$SUMMARY" ]; then
      TEXT=$(printf '%s' "$SUMMARY" | python3 -c '
import json,sys
try:
  d=json.loads(sys.stdin.read())
  print(d.get("choices",[{}])[0].get("message",{}).get("content",""))
except Exception:
  print("")
' 2>/dev/null || true)

      if [ -n "$TEXT" ]; then
        {
          echo ""
          echo "## Decisions"
          echo ""
          printf '%s\n' "$TEXT" | grep -iE '(decision|decided|agreed|confirmed|approved)' | head -10 || echo "(none captured)"
          echo ""
          echo "## Action Items"
          echo ""
          printf '%s\n' "$TEXT" | grep -iE '(action|task|assign|follow up|next)' | head -10 || echo "(none captured)"
          echo ""
          echo "---"
          echo "*Generated by Snotra — the meeting ear*"
        } >> "$MINUTES_FILE"
        say "  Summary appended to minutes"
      fi
    fi
  else
    say "  Skipping summary (no rail key or empty transcript)"
  fi

  # Step 4b: reasoning pass (extraction, classification, suggested steps)
  # Uses the same rail for logic tasks. Falls back to deterministic if unavailable.
  if [ -n "$RAIL_KEY" ] && [ -n "$TRANSCRIPT" ]; then
    say "  Reasoning pass: $RAIL_URL ($RAIL_MODEL)"
    local REASON_TEXT
    REASON_TEXT=$(bash "$ROOT/systems/snotra/services/ear/snotra-reason.sh" extract "$TMP_PREFIX.txt" \
      --provider local --model "$RAIL_MODEL" --api-key "$RAIL_KEY" 2>/dev/null || true)
    if [ -n "$REASON_TEXT" ]; then
      {
        echo ""
        echo "## Reasoning (LLM)"
        echo ""
        printf '%s\n' "$REASON_TEXT"
        echo ""
        echo "---"
        echo "*Generated by Snotra reasoning pass*"
      } >> "$MINUTES_FILE"
      say "  Reasoning appended to minutes"
    else
      say "  Reasoning skipped (rail unavailable or empty result)"
    fi
  fi

  # Step 5: append a Rune
  if [ -x "$ROOT/bin/records/runes-append.sh" ]; then
    "$ROOT/bin/records/runes-append.sh" snotra \
      "meeting minutes created — $MINUTES_FILE" \
      --message "snotra: meeting minutes created — $MINUTES_FILE" >/dev/null 2>&1 || true
  fi

  # cleanup
  rm -f "$NORM" "$TMP_PREFIX.txt" "$TMP_PREFIX.srt"
  say "Done: $MINUTES_FILE"
}

case "${1:-}" in
  -h|--help|"")
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *)
    do_transcribe "$@"
    ;;
esac
