# Translation at Ymir — the programs, and how to use each

The detailed reference for the translation craft. **Bragi** (the skald) uses
these to translate; **Kvasir** (the knowing) maps them. Read this file fully
before translation work — it is the "how" behind the skill's router.

---

## 1. whisper.cpp — speech → text (transcription)

### Where it lives

```
heimdall (192.0.2.110, user zerwiz):
  binary:   ~/whisper.cpp/build/bin/whisper-cli          (also: .../main, .../whisper-bench, .../whisper-vad-speech-segments)
  models:   ~/whisper.cpp/models/ggml-{tiny,base,small,medium}.en.bin
  GPU:      <gpu> (16 GB, CUDA 8.6) — whisper-cli finds it automatically
```

### The one trap: opus-in-ogg

whisper-cli's internal miniaudio **refuses opus-in-ogg** (`failed to read
audio data`). WhatsApp voice notes are exactly that. Always decode to a
16 kHz mono WAV first:

```bash
ffmpeg -y -i "clip.ogg" -ar 16000 -ac 1 -c:a pcm_s16le clip.wav
```

### Transcribe (the proven path)

```bash
cd ~/whisper.cpp
./build/bin/whisper-cli \
  -m models/ggml-small.en.bin \
  -f ~/Downloads/clip.wav \
  -otxt -of ~/Downloads/clip \
  -l en --no-prints
# output: ~/Downloads/clip.txt  (timestamped segments, plain text)
```

### Model choice

| Model | Size | Speed (GPU) | Accuracy | Use for |
|---|---|---|---|---|
| `ggml-tiny.en` | 75 MB | instant | rough | quick gist of a clip |
| `ggml-base.en` | 145 MB | fast | fair | chat notes |
| `ggml-small.en` | 466 MB | fast | **good** | **default for voice notes** |
| `ggml-medium.en` | 1.5 GB | slower | best | long or accented speech |

The `.en` models are English-only; a non-English clip needs the multilingual
model (download via `~/whisper.cpp/models/download-ggml-model.sh <name>`),
and the target tongue matters for the next step.

### Formats whisper reads

WAV (16-bit PCM), and — via miniaudio — some mp3/flac/m4a. Ogg/opus: decode
through ffmpeg first, always.

### The seat's own door

heimdall has `~/whisper-dictate.sh` — a live dictation wrapper (arecord →
whisper-cli → wl-copy paste). Read it for the seat's recording workflow; for
a **file**, use the direct whisper-cli path above.

---

## 2. ffmpeg — the format door

Present on every seat (`/usr/bin/ffmpeg`). Its only job here: normalize any
audio to what whisper wants.

```bash
# WhatsApp voice note -> whisper-ready
ffmpeg -y -i "WhatsApp Ptt ....ogg" -ar 16000 -ac 1 -c:a pcm_s16le out.wav

# any container -> raw wav (check first)
ffprobe -v error -show_entries stream=codec_name,sample_rate,channels -of default=noprint_wrappers=1 file
```

---

## 3. The llama router — text → text (translation)

After transcription (or for written material that is already text), the
translation itself runs on the machine's own local seats — no API key,
private by construction.

| Seat | Endpoint | Model | Best for |
|---|---|---|---|
| coding | `http://127.0.0.1:8080/v1` | qwen3.6-35b-a3b | general translation, technical text |
| research | `http://127.0.0.1:1234/v1` | apodex-1.0-mini | multi-step, planning-laced translation |

### The text-to-text recipe (curl, OpenAI-compatible)

```bash
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "qwen3.6-35b-a3b",
    "messages": [
      {"role": "system", "content": "You are a professional translator. Translate MEANING, keep names/numbers/dates exact. Output only the translation."},
      {"role": "user", "content": "Translate the following to <TARGET>:\n\n<SOURCE TEXT>"}
    ]
  }'
```

Or through the agents' own model seam (`pi -p` / opencode) when the craft is
performed by an Eindri:

```bash
pi -p --no-session --model "llama-cpp/qwen3.6-35b-a3b@q2_k_xl" \
  "Translate to <TARGET>. Keep names and numbers exact. Only the translation, no preamble." <<'EOF'
<SOURCE TEXT>
EOF
```

### Router notes (the house law)

- One local model rides the router at a time — swap seats by re-pointing the
  router, never by guessing a second model.
- Never point translation at Ollama — it is the machine's own server, not a
  Ymir provider (AGENTS.md provider law).

---

## 4. Caddy / edge — where a translated page is served

When a translation is a *page* (a localized landing), it ships to the server
and is served through its Caddy/cloudflared door — the same deploy path every
site uses. The translated artifact is a file in the record first; deployment
is a separate, deliberate act (never auto-published without the word).

---

## 5. The record (the hoard's law)

Every translation lands in `$YMIR_HOME/hodd/docs/translation/records/`,
append-only, named `YYYY-MM-DD-<slug>.md` (or `.txt` for raw speech text).
The folder's `README.md` is the index. The hoard guard keeps the record
disk-held — private by design, never pushed.

---

## 6. The end-to-end example (2026-09-19 proven)

```bash
# 1. on heimdall — the clip
ls ~/Downloads/"WhatsApp Ptt 2026-09-19 at 19.49.37.ogg"

# 2. decode
ffmpeg -y -i ~/Downloads/"WhatsApp Ptt 2026-09-19 at 19.49.37.ogg" \
  -ar 16000 -ac 1 -c:a pcm_s16le ~/Downloads/whatsapp-2026-09-19.wav

# 3. transcribe (GPU, small.en)
~/whisper.cpp/build/bin/whisper-cli -m ~/whisper.cpp/models/ggml-small.en.bin \
  -f ~/Downloads/whatsapp-2026-09-19.wav -otxt -of ~/Downloads/whatsapp-2026-09-19 \
  -l en --no-prints
# -> ~/Downloads/whatsapp-2026-09-19.txt  (1,136 words, 8:20 clip)

# 4. translate (next step per the Allfather's word) — the llama router recipe above
# 5. record — hodd/docs/translation/records/2026-09-19-<slug>.md
```