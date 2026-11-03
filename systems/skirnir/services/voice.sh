#!/usr/bin/env bash
# voice.sh — talk to Skírnir with a voice, and hear him answer while he is still answering.
#
#   bin/assistant/voice.sh                          # record 6 s, transcribe, answer, speak
#   bin/assistant/voice.sh --seconds 10
#   bin/assistant/voice.sh --text "what is OptiCat?"       # skip the microphone
#   bin/assistant/voice.sh --file /tmp/ask.wav             # transcribe a file
#   bin/assistant/voice.sh --model qwen3.6-35b-a3b@q4_k_xl-mtp
#   bin/assistant/voice.sh --no-speak
#
# The chain: microphone → whisper.cpp → Skírnir (owner tier, digest only) → the gate → Piper,
# sentence by sentence, so speech starts before the answer is complete.
#
# Everything he says still passes the four walls. The voice does not relax the law: no URL, no link,
# no canary, no NDA fact to someone who is not a party.
set -u
VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo root, found by walking up to the tree that holds .pi and RULES — never counted in
# "../", because this shelf was moved once (bin/assistant/ -> systems/skirnir/, plan 149) and
# 25 scripts kept the old depth, so every $ROOT/bin/... pointed into systems/ instead (2026-11-02).
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)"

SECONDS_TO_REC=6; TEXT=""; WAV=""; MODEL=""; SPEAK=1; KOKORO_URL="${KOKORO_URL:-http://127.0.0.1:8765/v1/audio/speech}"
while [ $# -gt 0 ]; do
  case "$1" in
    --seconds) SECONDS_TO_REC="${2:-6}"; shift 2 ;;
    --text) TEXT="${2:-}"; shift 2 ;;
    --file) WAV="${2:-}"; shift 2 ;;
    --model) MODEL="${2:-}"; shift 2 ;;
    --no-speak) SPEAK=0; shift ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --version|-v) printf '%s\n' "$VERSION"; exit 0 ;;
    *) printf 'error: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
done

transcribe() {
  bash "$SCRIPT_DIR/ear.sh" "$1" --lang "${VOICE_LANGUAGE:-en}"
}

# ── 1 · hear ─────────────────────────────────────────────────────────────────
if [ -n "$TEXT" ]; then
  :
elif [ -n "$WAV" ]; then
  TEXT="$(transcribe "$WAV")"
else
  TMPWAV="$(mktemp --suffix=.wav)"
  printf 'listening for %ss…\n' "$SECONDS_TO_REC" >&2
  arecord -q -f cd -t wav -d "$SECONDS_TO_REC" "$TMPWAV" 2>/dev/null || {
    printf 'error: recording failed (is the microphone free?)\n' >&2; exit 1; }
  TEXT="$(transcribe "$TMPWAV")"
  rm -f "$TMPWAV"
fi
[ -n "${TEXT:-}" ] || { printf 'voice: nothing heard\n' >&2; exit 1; }
printf 'you: %s\n' "$TEXT"

speak_sentence() {
  local text="$1" wav
  wav="$(mktemp --suffix=.wav)" || return 1
  if ! bash "$SCRIPT_DIR/mouth.sh" "$text" "$wav" "${VOICE_LANGUAGE:-en}" >/dev/null; then
    rm -f "$wav"; return 1
  fi
  . "$SCRIPT_DIR/native-voice.sh"
  if native_voice_available; then
    # Synthesis has already passed the WAV validation; use the native player only.
    powershell.exe -NoProfile -NonInteractive -File "$(native_voice_path "$SCRIPT_DIR/voice-play.ps1")" -AudioFile "$(native_voice_path "$wav")"
  elif command -v paplay >/dev/null 2>&1; then
    paplay "$wav"
  else
    aplay -q "$wav"
  fi
  local rc=$?; rm -f "$wav"; return "$rc"
}

# ── 1b · a slow turn announces itself ────────────────────────────────────────
# Research is a provider call plus a model answer: 2.5-4 s before the first word, against the
# council's 1.2 s bar. Silence reads as deafness, so say so first (plan 101, parity law).
if [ "$SPEAK" = 1 ] && printf '%s' "$TEXT" | grep -qiE '\b(look up|search|research|google|find)\b.*\b(online|web|internet)\b|\b(look up|search|research)\b'; then
  speak_sentence "One moment, I'm looking." 2>/dev/null || true
fi

# ── 2 · think (the walls apply) ──────────────────────────────────────────────
ARGS=(--tier owner --channel voice --sender voice --text "$TEXT")
[ -n "$MODEL" ] && ARGS+=(--model "$MODEL")
OUT="$(python3 "$SCRIPT_DIR/skirnir.py" "${ARGS[@]}" 2>/dev/null)"
REPLY="$(printf '%s' "$OUT" | python3 -c "import sys,json
try: print(json.load(sys.stdin).get('answer',''))
except Exception: print('')" 2>/dev/null)"
[ -n "$REPLY" ] || { printf 'voice: no answer\n' >&2; exit 1; }
printf 'skírnir: %s\n' "$REPLY"

# ── 3 · speak it as it comes: one sentence at a time ─────────────────────────
# The shared mouth validates audio and reports synthesis failure.


if [ "$SPEAK" = 1 ]; then
  # Kokoro stumbles on contractions ("do n,,,, t" — measured 2026-10-22). Only what is SPOKEN is
  # normalised: the written answer is untouched.
  REPLY="$(printf '%s' "$REPLY" | python3 "$SCRIPT_DIR/speech-text.py")"
  printf '%s' "$REPLY" | python3 -c "
import re,sys
for part in re.split(r'(?<=[.!?])\s+', sys.stdin.read()):
    part = part.strip()
    if part:
        print(part)
" | while IFS= read -r sentence; do
    speak_sentence "$sentence" || exit 1
  done
  [ "${PIPESTATUS[2]}" = 0 ] || exit 1
fi

printf '%s\n' "$OUT" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(f\"voice[1]{{tier,intent,refused,digest}}: \\\"{d.get('tier')}\\\",\\\"{d.get('intent','')}\\\",\\\"{d.get('refused')}\\\",\\\"{d.get('digest','')}\\\"\")" 2>/dev/null
