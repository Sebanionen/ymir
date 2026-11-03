# Voice files on Windows and WSL

Skirnir's ear and mouth can use already installed whisper.cpp and FastKokoro on
Windows. They never install an engine or open a microphone. Native Windows owns
the listeners; WSL calls PowerShell rather than assuming its loopback is Windows.

## What you need

An installed whisper-server, multilingual Whisper model, FastKokoro installation
manifest, Python on Windows PATH and ffmpeg on Windows PATH. The existing
FastKokoro `installation.json` supplies its executable and start environment.

## Control the engines

From PowerShell run `systems/skirnir/services/voice-service.ps1 status`.
The same command accepts `start`, `stop` or `restart`, followed by `whisper`,
`kokoro` or `all`. It reports the local Windows road, listener and health separately.
It verifies executable identity, parent identity for a venv child, and process
creation time before stopping; an unrelated or non-loopback listener is refused.
It never acts on a saved PID alone. Start is idempotent; unhealthy existing engines
require an explicit restart. Logs remain in the private runtime directory.
Use `-Json` for diagnostic process IDs; the default output is compact TOON.

Discovery reads process environment, then user environment, then defaults:
`YMIR_HOME` defaults to Documents/ymirhome; `YMIR_VOICE_RUNTIME` defaults to
`$YMIR_HOME/hodd/state/runtime`; `WHISPER_SERVER` defaults to
`snotra/whisper-v1.9.2/Release/whisper-server.exe` under that runtime;
`WHISPER_MODEL` defaults to `snotra/models/ggml-small.bin`;
`WHISPER_PORT` defaults to 10300. Kokoro uses `kokoro/installation.json`.
Both services must bind loopback. No autostart is registered.

## Transcribe and render files

From PowerShell use `voice-file.ps1 -Action transcribe -Value C:\audio\test.wav
-Language sv` in the same services directory. Use `-Action speak -Value "Hello"
-OutputFile C:\audio\reply.wav -Language en` to render speech. `.ogg` output
encodes Opus. `-Play` plays a generated WAV through Windows SoundPlayer.
The file door starts its installed engine idempotently before requesting audio.

From WSL the existing `ear.sh /mnt/c/audio/test.wav --lang sv` and
`mouth.sh "Hello" /mnt/c/audio/reply.wav en` use the native adapter. The adapter
discovers `WHISPER_URL`, `KOKORO_URL`, `KOKORO_VOICE`, `WHISPER_VOCAB` and
`FFMPEG_BIN` from process/user environment. Defaults are local HTTP inference,
local Kokoro speech, `af_nicole`, empty vocabulary and `ffmpeg` respectively.
Keep configured URLs on the authorised private/local road.

`voice.sh --file <audio> --no-speak` passes through the same ear into Skirnir's
existing answer gate. `VOICE_LANGUAGE` selects input language. Speaking uses the
same mouth and native player on Windows; missing playback is an error.

## Limits and failures

This Kokoro adapter supports English speech only. Swedish speech is explicitly
refused; no English pronunciation is substituted for Swedish. Multilingual
Whisper input does not prove Swedish output or Swedish recognition quality.
File transcription is verified independently of microphone capture, UI buttons,
meeting attendance and external channels. Those remain separate acceptance work.

If an engine is down, start it with the control door and retry. A synthesis error,
invalid WAV or empty transcript fails visibly. No previous temporary transcript
is reused. Failed synthesis preserves an existing destination file.
HTTP uses a direct origin connection without ambient proxies or silent retries.
Linux retains its existing systemd service road; fleet-wide acceptance needs
separate verification on another machine.
