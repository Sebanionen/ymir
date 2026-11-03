#!/usr/bin/env bash
# ear.sh — a voice note in, the words out. The meeting ear's engine, used by the assistant's own bot.
#
#   bin/assistant/ear.sh <audio-file> [--lang en]
#
# Whisper lives in `snotra-whisper.service` (:10300, CUDA, small.en) — the same ear Snotra uses in a
# meeting, so there is one transcription path in this house and not two. If the service is down the
# local `whisper-cli` is the fallback; if neither answers, the caller is told so, never given a guess.
set -u
FILE=""; LANG_CODE="en"
while [ $# -gt 0 ]; do
  case "$1" in
    --file=*) FILE="${1#--file=}"; shift ;;      # the pi-telegram handler template's shape
    --file) FILE="${2:-}"; shift 2 ;;
    --lang=*) LANG_CODE="${1#--lang=}"; shift ;;
    --lang) LANG_CODE="${2:-en}"; shift 2 ;;
    *) [ -z "$FILE" ] && FILE="$1"; shift ;;
  esac
done
[ -n "$FILE" ] && [ -r "$FILE" ] || { printf 'ear: no audio file\n' >&2; exit 2; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/native-voice.sh"
if native_voice_available; then
  native_voice_file transcribe "$FILE" "" "$LANG_CODE"
  exit $?
fi
URL="${WHISPER_URL:-http://127.0.0.1:10300/inference}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# whisper wants 16 kHz mono PCM — and TELEGRAM'S NOTES ARE QUIET. Measured 2026-10-22: the same note
# without gain heard "OptiCAD"; with gain and a vocabulary hint it heard "OptiCat". Level first, then
# the words.
ffmpeg -hide_banner -loglevel error -y -i "$FILE" \
  -af "volume=6dB,loudnorm=I=-16:TP=-1.5:LRA=11" -ar 16000 -ac 1 "$TMP/16k.wav" 2>/dev/null \
  || ffmpeg -hide_banner -loglevel error -y -i "$FILE" -ar 16000 -ac 1 "$TMP/16k.wav" 2>/dev/null \
  || { printf 'ear: could not decode the audio\n' >&2; exit 3; }

# ── raise the mouth NOW, while the ear is still listening (plan 121, phase 2) ─────────────────────
# The voice is idle-lowered after five quiet minutes; raising it costs up to 30 s, and the Telegram
# mouth used to pay that wait BEFORE its first word. His note is the earliest proof a conversation is
# live, so the mouth is raised here — in the background, overlapping the transcription and the head's
# thinking — never on the critical path. Output goes nowhere: this file's stdout IS the transcript.
raise_mouth() {
  local lease="${SCRIPT_DIR}/../../snotra/services/tts-lease/tts-lease.sh" url="${KOKORO_URL:-http://127.0.0.1:8765/v1/audio/speech}"
  local host="${url#*://}"; host="${host%%/*}"; local port="${host##*:}"; host="${host%%:*}"
  port="${port:-80}"
  bash "$lease" touch >/dev/null 2>&1 || true
  (exec 3<>"/dev/tcp/${host}/${port}") 2>/dev/null && return 0
  systemctl --user start kokoro-serve.service >/dev/null 2>&1 || true
  local i; for i in $(seq 1 30); do
    sleep 1
    (exec 3<>"/dev/tcp/${host}/${port}") 2>/dev/null && return 0
  done
  return 1
}
raise_mouth >/dev/null 2>&1 &

# A VOCABULARY HINT, because a general model hears "OptiCAD" and this house has an OptiCat. Names only,
# never a private fact: it biases the decoder toward the words the house actually says.
VOCAB="${WHISPER_VOCAB:-OptiCat, OVK, Skírnir, Snotra, Boverket, WayOf, Whynot Productions, Synteon, ventilation inspection, Isabella, Craig, Brokk, Ymir}"
OUT="$(curl -s -m 120 "$URL" -F "file=@$TMP/16k.wav" -F response_format=json -F temperature=0 \
  -F "language=$LANG_CODE" -F "prompt=$VOCAB" 2>/dev/null)"
TEXT="$(printf '%s' "$OUT" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("text","").strip())
except Exception: print("")' 2>/dev/null)"
if [ -n "$TEXT" ]; then printf '%s\n' "$TEXT"; exit 0; fi

# the fallback: the local binary, same models directory
CLI="${WHISPER_CLI:-$HOME/whisper.cpp.src/build/bin/whisper-cli}"
MODEL="${WHISPER_MODEL:-$HOME/whisper.cpp.src/models/ggml-small.en.bin}"
if [ -x "$CLI" ] && [ -r "$MODEL" ]; then
  "$CLI" -m "$MODEL" -f "$TMP/16k.wav" -l "$LANG_CODE" -nt 2>/dev/null | tr -s ' ' | sed '/^$/d' && exit 0
fi
printf 'ear: neither the whisper service nor the local model answered\n' >&2
exit 4
