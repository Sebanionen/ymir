#!/usr/bin/env bash
# mouth.sh — text in, a Telegram voice note out.
#
#   bin/assistant/mouth.sh "text" <out.ogg>
#
# Kokoro (the resident server on :8765) speaks it, `speech-text.py` normalises what may be SPOKEN
# (contractions expanded, punctuation folded), and ffmpeg encodes OGG/Opus — the only format Telegram's
# sendVoice accepts. The voice is the switcher's (~/.local/bin/kokoro-voice), the same one F11 and the
# assistant's own mouth use: one voice for the whole house.
set -u
TEXT="${1:-}"; OUT="${2:-}"
[ "${3:-en}" = en ] || { printf 'mouth: English only; Swedish speech is unavailable\n' >&2; exit 2; }
[ -n "$TEXT" ] && [ -n "$OUT" ] || { printf 'mouth: usage: mouth.sh "text" out.ogg\n' >&2; exit 2; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/native-voice.sh"
if native_voice_available; then
  native_voice_file speak "$TEXT" "$OUT" "${3:-en}"
  exit $?
fi
LEASE="$SCRIPT_DIR/../../snotra/services/tts-lease/tts-lease.sh"
VOICE="${KOKORO_VOICE:-}"
if [ -z "$VOICE" ] && [ -x "$HOME/.local/bin/kokoro-voice" ]; then
  VOICE="$("$HOME/.local/bin/kokoro-voice" 2>/dev/null | sed -n 's/.*voice: \([a-z_0-9]*\).*/\1/p' | head -1)"
fi
VOICE="${VOICE:-af_nicole}"
SERVER="${KOKORO_URL:-http://127.0.0.1:8765/v1/audio/speech}"
HOST="${SERVER#*://}"; HOST="${HOST%%/*}"; PORT="${HOST##*:}"; HOST="${HOST%%:*}"
WAIT="${MOUTH_WAIT_SECONDS:-30}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

port_open() { (exec 3<>"/dev/tcp/${HOST}/${PORT:-80}") 2>/dev/null; }

# ── raise the voice ──────────────────────────────────────────────────────────────────────────
# The TTS server is idle-lowered ON PURPOSE — it gives the card back after five quiet minutes — so
# every speaking door must raise it before it speaks. The meeting mouth does (`snotra-meet.sh
# ensure_voice`); the Telegram mouth did not, and that was the whole of tonight's silence: kokoro was
# lowered at 12:29 and every voice note until 19:30 came back as text, with one stderr line nobody
# reads. The lease is taken BEFORE the wait, so the stop-rule can never lower the server between
# our check and our first word (plan 112's lease guard).
bash "$LEASE" touch 2>/dev/null || true
if ! port_open; then
  systemctl --user start kokoro-serve.service >/dev/null 2>&1 || true
  for _ in $(seq 1 "$WAIT"); do sleep 1; port_open && break; done
fi
port_open || { printf 'mouth: the synthesiser is down — kokoro-serve is not answering on %s:%s\n' \
                 "$HOST" "${PORT:-80}" >&2; exit 3; }

SPOKEN="$(printf '%s' "$TEXT" | python3 "$SCRIPT_DIR/speech-text.py")"
speak() {
  curl -s -m 120 -o "$1" -w '%{http_code}' -X POST "$SERVER" -H 'content-type: application/json' \
    -d "$(python3 -c "import json,sys;print(json.dumps({'model':'kokoro','input':sys.argv[1],'voice':sys.argv[2],'response_format':'wav'}))" "$SPOKEN" "$VOICE")" 2>/dev/null
}
CODE="$(speak "$TMP/say.wav")"
if { [ "$CODE" != "200" ] || [ ! -s "$TMP/say.wav" ]; } && [ -f "$HOME/.local/bin/voice-gpu-lib.sh" ]; then
  # Kokoro also fails SILENTLY when the card is full (500 CUBLAS failure 3 — measured 2026-10-22). The
  # rail shares the card: give it back and try once more, the rule the meeting mouth already follows.
  . "$HOME/.local/bin/voice-gpu-lib.sh"
  voice_ensure_vram 1200 >/dev/null 2>&1 || true
  sleep 1
  CODE="$(speak "$TMP/say.wav")"
fi
[ "$CODE" = "200" ] || { printf 'mouth: the synthesiser did not answer (http %s)\n' "${CODE:-none}" >&2; exit 3; }
[ -s "$TMP/say.wav" ] || { printf 'mouth: empty audio\n' >&2; exit 4; }
# hold the voice: the idle-stop must never lower the card under a conversation (2026-10-23)
bash "$LEASE" touch 2>/dev/null || true
python3 "$SCRIPT_DIR/audio-tighten.py" "$TMP/say.wav" 2>/dev/null || true
case "$OUT" in
  *.wav) cp "$TMP/say.wav" "$OUT" || exit 5 ;;
  *) ffmpeg -hide_banner -loglevel error -y -i "$TMP/say.wav" -c:a libopus -b:a 32k -ar 48000 -ac 1 "$OUT" 2>/dev/null \
     || { printf 'mouth: could not encode the voice note\n' >&2; exit 5; } ;;
esac
printf 'mouth[1]{voice,bytes,file}: "%s","%s","%s"\n' "$VOICE" "$(stat -c%s "$OUT")" "$OUT"
