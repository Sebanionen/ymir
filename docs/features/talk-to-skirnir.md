# Talk to Skírnir

Open **Skírnir – Tala** at the top of Hlidskjalf's left navigation, or use the
same labelled button in the top bar. This is the assistant. **Start listening**
beside it still belongs to Snotra's separate room/meeting record.

Choose **English · Nicole (USA, kvinna)** or **Svenska · Bengt (sv-SE)**.
Tick the microphone consent box, then press **F8** or click **Börja tala**.
Your browser asks for permission if it has not already been granted. Ask one
question, then press **F8 again** or click **Avsluta frågan**. Capture ends before
transcription and the answer. After 30 seconds the question ends automatically.

**Escape** cancels capture, a pending answer or playback, like **Stoppa**.
These keys belong only to the focused **Skírnir – Tala** page in Ymir. They do
not work in another application, a hidden/unfocused page, or while typing in an
editable field. Repeat events and modified key combinations are ignored. There
is no system-global shortcut. Without consent, F8 focuses the visible consent
box and opens no capture; it never bypasses browser permission.

The page shows listening state, the real Whisper transcript, the existing
Skírnir engine's permitted answer or refusal, and local speech audio. If the browser
blocks automatic playback, use **Spela upp svaret**. An unknown fact remains
unknown; this feature does not create knowledge or substitute a demo response.

**Stoppa** cancels capture, pending work and playback. Leaving the page also
releases the microphone and cancels the turn. A shared engine can finish an
inference already submitted to it; stopping discards that turn and starts no
further answer or speech step. It never stops Snotra or the shared voice servers.

## Languages and privacy

English uses the American female Kokoro voice **Nicole (`af_nicole`)**. Swedish
uses **Microsoft Bengt (`sv-SE`)**, a genuine separate local Windows speech
voice. Both input languages go through the installed multilingual Whisper.
Kokoro is never used to imitate Swedish. If Bengt or its required runtime is
missing, Swedish speech is unavailable rather than silently replaced.

Swedish greetings, approved-fact inventory and honest refusals are localized
inside the existing answer gate. An approved fact without a verified Swedish
formulation produces a spoken limitation and offers English source wording;
no fact or translation is invented. A synthetic Swedish round trip proves the
tested phrase and routing, not recognition accuracy for every real speaker.

The audio request goes only to the local gate and installed local engines.
No API key is placed in the browser. Audio files are temporary, separate from
Snotra's meeting shelf. Text uses Skírnir's existing private conversation audit.
No meeting is joined and no external voice or mail channel is activated.

The local operator seat is trusted under the existing gate policy. Voice routes
add actual peer-loopback, local-host, same-origin and non-forwarded-request
checks; a remote connection or a non-operator signed-in session is refused.
A Host header alone is never peer proof. This is not a shared remote voice API.

## If something does not work

- Wait while **ansluter lokalt…** is shown. The existing gate can take time to
  finish its other runtime probes on a cold start. A failed connection offers
  **Anslut igen**.
- **Svenska · kontrollerar röst…** means its status has not arrived yet, not
  that the voice is missing. **Kontrollera röster** reads current availability
  without opening a microphone. Returning focus to the page also refreshes it;
  while Swedish speech is unconfirmed, a visible idle page rechecks every five
  seconds so an installation finishing after page load is picked up. Only a
  confirmed available voice enables **Svenska · Bengt (sv-SE)**.
- Permission denied leaves the microphone off. You decide whether to change
  the browser's microphone permission and click **Börja tala** again.
- A backend failure is shown. Its diagnostic details stay in private runtime
  logs; a failed turn does not display a fabricated answer.
- **Prova med en ljudfil utan mikrofon** accepts an audio file up to 8 MiB and
  exercises the same real transcription/answer/speech chain without capture.

## Worktree preview and verification

On Windows run `systems/skirnir/services/voice-preview.ps1`. It starts an isolated
Hlidskjalf preview on loopback with its own gate state; it does not deploy main
or read the production gate key. Defaults are UI port 3988 and API port 3989,
overridable with `-UiPort` and `-ApiPort`. The route is `/#/skirnir`.

The preview uses the operator's existing `YMIR_HOME` knowledge via `SKIRNIR_HOME`;
it does not export or invent facts. `SKIRNIR_VOICE_TMP` controls private temporary
turn storage; `SKIRNIR_PYTHON` selects the installed Python executable. The
installed engine URLs are `WHISPER_URL` and `KOKORO_URL`, loopback-only for this
UI. Their defaults are the existing inference/speech endpoints. Native Windows
can start the existing services through `voice-service.ps1`; Linux uses its
already running engines. See [file voice controls](voice-files-on-windows.md).

Swedish uses the private installer contract at
`$YMIR_HOME/hodd/state/runtime/skirnir-swedish/installation.json`. Its recorded
`executable` and `arguments` provide the verified file-only invocation; the
actual script bytes must match `script_sha256` before execution. Missing or
changed checksums and unexpected invocation flags disable the Swedish route.
The recorded executable is the default for **PowerShell 7.6.5**, never Windows
PowerShell 5.1. `SKIRNIR_SWEDISH_PWSH` overrides that executable;
`SKIRNIR_SWEDISH_DIR` overrides the private installation directory;
`SKIRNIR_SWEDISH_SCRIPT` overrides the file contract. The script receives
`-TextPath <UTF-8-file> -OutputPath <existing-directory>/answer.wav`, returns
JSON metadata and creates a 24 kHz mono PCM16 WAV with no playback. The gate
checks runtime version, Bengt/culture and format metadata. No account-specific
runtime path belongs in public source. Cancellation owns only the turn's
worker process; temporary text/audio is removed with the turn.

Independent Swedish synthetic recognition has succeeded semantically, with
word-form and name errors (for example `svenskt` → `svensk`, `Skirnir` →
`skinir`). This is usable routing evidence, not a claim of perfect ASR.

Run `npm run typecheck`, `npm run build` and `npm run test:voice` from
`apps/hlidskjalf`. Browser verification uses `npm run test:voice:browser` with
`SKIRNIR_E2E_AUDIO` pointing to a synthetic English WAV,
`SKIRNIR_E2E_AUDIO_SV` pointing to genuine synthetic Swedish WAV, and `SKIRNIR_E2E_REPORT` pointing
to a private report folder. `PLAYWRIGHT_CHROMIUM_EXECUTABLE` can select an
installed test Chromium. The test always uses Chromium's fake-device and
file-input flags; it must never be changed to capture a physical microphone.

`server/swedish-voice.test.ts` checks manifest arguments, checksum tampering and
unsafe flag rejection without starting an interpreter. The opt-in
`npm --prefix apps/hlidskjalf run test:voice:contract` runs the opt-in proof at
`apps/hlidskjalf/scripts/swedish-contract.integration.ts` for a real synthetic Swedish file
round trip on its own ephemeral loopback port, using explicit private
`SKIRNIR_TEST_HOME`, `SKIRNIR_TEST_AUDIO_SV` and `SKIRNIR_TEST_REPORT` settings.
It does not restart the preview or capture a microphone.

`tests/swedish-selection.e2e.mjs` separately verifies the current rendered
Swedish selection and a real prerecorded Swedish answer/audio round trip.
It has no media permission and blocks getUserMedia, so its evidence includes
the actual enabled option, Bengt identity, browser WAV decoding and zero
physical capture attempts.
