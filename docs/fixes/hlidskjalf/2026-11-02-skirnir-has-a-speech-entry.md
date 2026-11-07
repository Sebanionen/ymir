# Skírnir has a speech entry in Hlidskjalf

The existing Start listening control belongs to Snotra's room record. It did
not send an assistant question to Skírnir or return Kokoro speech. A separate
Skírnir – Tala gate and topbar entry now make that assistant flow explicit.

Capture starts only after consent and a button click. Finish closes tracks
before upload; Stop and unmount close tracks, abort requests and cancel the
owned backend turn, including an upload that has not finished arriving.
The server reuses the installed file adapter, existing knowledge/answer gate
and Kokoro, with no browser key and no fabricated response. Swedish input is
offered as text-only; unsupported Swedish speech remains absent.

Voice API access checks the actual loopback peer, a local Host, same Origin,
forwarding headers and operator eligibility. A local browser already admitted
by the existing gate policy now receives its operator session label even when
it has no Electron preload; this changes session metadata, not remote access.

Native Windows uploads exposed http-proxy's forced Connection: close. The
Vite development/preview proxy uses a keep-alive agent rather than retrying
or discarding failed audio. The worktree preview uses separate gate state
and a process-only signing key, while the answer engine uses existing private
profile knowledge. No main deployment or meeting capture is involved.

Validation includes boundary/tombstone tests, TypeScript/build, real backend
requests and synthetic browser capture/stop tests. The operator guide is
docs/features/talk-to-skirnir.md. Microphone hardware is never activated by
agent automation.

## Added: keyboard control and genuine Swedish voice

The earlier text-only Swedish implementation above is superseded. F8 is now
owned by the focused Skirnir page: start through the same consent, then finish
and submit; Escape cancels. Repeats, modifiers, editable typing and unfocused
pages are ignored. No OS-wide shortcut or microphone activation by automation
was added.

English is pinned to American female Kokoro af_nicole. Swedish uses the private
Bengt file contract with its recorded PowerShell 7.6.5 executable, never 5.1.
Runtime and voice/format metadata are checked. Generic Swedish replies are
localized before the existing answer gate; unverified translations are refused.
Voice-local delivery/learning/research action branches are refused, not executed.

The final synthetic browser evidence has 11 PASS and zero uncaught browser
errors, including F8 consent/typing/repeat, F8 start/finish, Escape capture and
backend cancellation, Nicole identity, genuine Swedish ASR/reply/Bengt playback,
and Escape stopping Swedish playback. No physical microphone was used. The
private final report preserves earlier failures and their corrections.
## Recorded Swedish interpreter contract integrity

The route now consumes installation.json executable, arguments and
script_sha256, rather than reconstructing the invocation from a guessed script
name. Only the recorded file-only argument shape is accepted; private input
and output filenames replace its placeholders. Actual script bytes must match
the recorded SHA-256, including when a documented script override is used.
Missing/tampered scripts or unexpected flags disable synthesis, with no 5.1 or
Kokoro fallback. Three focused contract tests and a real isolated Swedish file
round trip passed. Earlier 11 browser PASS remain preserved, not rerun.
Independent Swedish ASR is semantic proof with observed inflection/name errors,
not perfect recognition.
## Current rendered Swedish availability

A root browser review saw a disabled Swedish option while the current server
reported speech=true. The client previously initialized availability to false
and read it only once. It now distinguishes pending status from confirmed
unavailability, refreshes on focus/visibility, offers Kontrollera röster and
rechecks unconfirmed availability on a visible idle page. This status refresh
never opens a microphone and does not change the preview/knowledge home route.

The targeted current-preview browser proof confirmed the enabled Svenska ·
Bengt (sv-SE) selection and a real Swedish file -> Whisper -> permitted Swedish
answer -> browser-decoded Bengt WAV. The browser had no media permission and
getUserMedia was blocked, with zero capture attempts. Earlier broad passing
voice tests remain preserved, not rerun.