# Native voice files and engine control

The moved ear/mouth scripts counted the old directory depth for the TTS lease.
The ear omitted its selected language from HTTP inference; voice.sh used shared
temporary transcripts and could speak a research notice despite --no-speak.
First export wrote canaries before creating the state directory.

Correct the lease paths, forward the language, create export state first and
route voice.sh transcription through ear.sh. Windows/WSL ear and mouth now use
a native file adapter with environment discovery, ffmpeg conversion, validated
WAV output and explicit refusal of unsupported Swedish synthesis. Native engine
control reuses installed Whisper/FastKokoro, checks listener ownership and health,
and supports start/status/stop/restart without saved-PID authority.

The file adapter has failure-contract tests; live synthetic WAV round trips and
service lifecycle checks are required in addition. No microphone, meeting or
external channel is enabled by this change. The Windows file road does not imply
that a listening UI button or Swedish TTS is ready.

Repeated native requests also exposed connection resets with urllib's closing
transport. The adapter uses a direct http.client origin connection, validates the
complete PCM frame payload, and does not retry failed synthesis silently.
PowerShell child failures propagate through the global native exit code; a local
LASTEXITCODE variable must not shadow it and turn a failed call into success.
