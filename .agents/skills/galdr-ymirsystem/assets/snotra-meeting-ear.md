# Snotra — the meeting ear (Galdr asset)

**Role:** The meeting ear — captures, transcribes, and stores meeting minutes
privately in the hoard. Named for Snotra, the wise one, mistress of counsel.

## Architecture

```
THE WATCH (detect)     a CALL SEAT — any seat with a microphone. Watches PipeWire
                       for an app taking the mic, arms the capture of the
                       conversation pair, and leaves when the room empties.
                       Raised by CAPABILITY, never by role.
THE EAR (capture)      the seat in the meeting — heimdall today, omarchy too
                       PipeWire mic + monitor capture. Nothing else can do this.
THE BRAIN (transcribe) the seat with the GPU — the living-rail resolver's
                       serving box (heimdall's <gpu> first, then whynot)
                       whisper.cpp CUDA (~1.0s) + the LIVE rail for summaries
THE RECORD (store/serve)  the heart (zerwizserver) — minutes in the vault, synced
                       by the home's git road, the MCP face served there
```

**The watch is the half that makes the ear automatic.** Before it, a meeting was
heard only if a hand armed the capture; now the microphone is the signal — a
voice call cannot happen unless the call application opens a capture stream on a
microphone — and the moment the room empties the ear leaves.

**Cost if run otherwise:** If the Allfather insists on transcribing on whynot
(the <gpu>), it costs a 3-5× slowdown on transcription (<gpu> lacks CUDA
acceleration for whisper) and requires the recording to be transferred from the
meeting seat to whynot first. The configuration change is a single env var:
`WHISPER_GPU=off` and `WHISPER_MODEL` pointing to a CPU model. The design
supports this; it is not a rewrite.

## Components

### M1 — Fleet tool (`tools/snotra/`)

- `server.mjs` — MCP server (read-only minutes access, streamable HTTP, port 8321)
- Materialized into `~/.fleet/snotra-server.mjs` by `bin/fleet/fleet-ensure.sh`
- The operator commands (`snotra-capture.sh`, `snotra-transcribe.sh`,
  `snotra-detect.sh`, `snotra-mine.sh`, `snotra-ensure.sh`, `runes-append.sh`)
  are materialized into `~/.fleet` too — **with `hoard-lib.sh` beside them**: each
  of them resolves the operator's home through it, and a seat that has the
  command without the resolver dies on an unbound `YMIR_HOME` the moment it runs
  outside a shell that already knew the home
- Pinned version: Meetily-Local AppImage (see fetch below)

### M0 — the engine ensure (`systems/snotra/services/ear/snotra-ensure.sh`)

- Reports the seat's engine + model; installs what is missing
- Per-OS: `pacman -S whisper-cpp` (Arch/omarchy), `apt-get install whisper.cpp`
  (Debian), else build-from-source guidance
- Model fetched from the whisper.cpp Hugging Face release; a voxtype seat keeps
  its models
- Wired into `bin/engine/ymir-install.sh` (`step_snotra`) and `bin/agents/eir-doctor.sh`
  (`snotra` surface)

### M2 — Systemd unit (`tools/mill/systemd/snotra.service`)

- User unit, `WantedBy=ymir.target` — it joins the ONE target the install enables
  once, and boot pulls the whole role set (the auto-boot law). NOT `default.target`,
  which was the pre-autoboot contract.
- Runs `node ~/.fleet/snotra-server.mjs` on port 8321
- Depends on `$YMIR_HOME` being mounted (the hoard)

### M3 — Capture road (`systems/snotra/services/ear/snotra-capture.sh`)

- `start` — PipeWire mic + system monitor → dated WAV under the hoard
- `stop` — kills the ffmpeg process
- `status` — shows PID and listening indicator state
- Listening indicator: writes `state/.snotra-listening` (value: `recording`)
  so the bar can display it alongside ScreenRecording and Dictation

### M4 — Minutes into the vault (`systems/snotra/services/ear/snotra-transcribe.sh`)

- Transcribes WAV with whisper.cpp (local GPU)
- Produces structured Markdown minutes
- Stores under `$YMIR_HOME/hodd/life/meetings/`
  (the workspaces shelf: meetings are work-adjacent artifacts that follow the
  operator across domains; the hoard's `workspaces/` is the natural home)
- Appends a Rune via `bin/records/runes-append.sh`

### M5 — MCP face (`tools/snotra/server.mjs`)

- Read-only tools: `snotra_list`, `snotra_read`, `snotra_search`, `snotra_summary`
- Resource: `snotra://ear` (meeting count)
- StreamableHTTP transport (mirrors `tools/tickets-mcp`)
- Wired into seat MCP config by `fleet-ensure.sh` (port 8321)

### M6 — Summaries on the living rail

- Rides the ONE resolver (`bin/model/rail-resolve.sh`, `src/ymir_runtime/fleet/rail.py`, plan 51 Parts 9a/9c): the serving strong box's `http://<box>:8080/v1`, first-alive — a dropped box reroutes, never an outage
- `RAIL_URL` forces one specific rail when set; unset, the resolver's serving box wins (the ear's summaries ride whichever strong box is CONNECTED)
- Model: resolved from the hoard/env (`RAIL_MODEL`; unset = loud refusal — the tree carries no concrete model id)
- No cloud key needed — the rail key is a REFERENCE (env `LLAMA_SWAP_API_KEY` → the hoard vault → `~/.pi/agent/auth.json`), never a value in the tree

### M7 — The proof

- A real 5-minute capture end-to-end: captured, transcribed, minutes written,
  Rune appended, MCP query answered
- Evidence pasted in the PR body (transcript content redacted)

### M8 — The record

- Fix note under `docs/fixes/runtime/`
- This asset updated in the same change
- `compliance-check.sh` clean

### M9 — The watch (`systems/snotra/services/ear/snotra-detect.sh`)

- `run` — the standing watch (the unit's `ExecStart`); `status` — TOON row;
  `scan` — the PipeWire picture, once; `once` — one scan and act
- `arm [slug]` / `leave` — the manual doors, for a call the detector cannot see
- **The START edge.** A NEW record stream on a non-monitor source, sustained for
  `SNOTRA_ARM_DEBOUNCE` (3 s). The graph is read through the portable `pactl`
  surface (PipeWire serves the PulseAudio protocol on every seat), one snapshot
  per tick emitting tab-separated records for sources, source-outputs, sinks and
  sink-inputs. A stream **already open when the watch started is not a call** —
  the watch takes a baseline at start, because Discord holds the microphone open
  while idle on a real seat. A second signal covers an app that already holds the
  mic: a NEW playback stream from that same app is the remote side beginning.
- **The conversation pair.** At arm the watch resolves the microphone the call
  app is actually reading and the SINK the call itself is playing into (the sink
  its playback stream rides, falling back to the default sink), and arms the
  capture with that pair — so both sides are heard. No loopback module, no
  virtual device: the pair is resolved from the graph.
- **The LEAVE edge.** Three independent signs, first to fire:

```
leave_edges[4]{id,sign,default}:
  "L1","every stream that armed the ear is gone (sustained)","SNOTRA_RELEASE_GRACE=5s"
  "L2","the conversation's sink left the graph","—"
  "L3","mic AND monitor below a dB floor, sustained","SNOTRA_SILENCE_DB=-45 · SNOTRA_SILENCE_SECONDS=300"
  "L4","the capture's own safety cap","SNOTRA_MAX_SECONDS=14400"
```

- **The ear never lingers.** `do_arm` refuses to arm while a capture is already
  alive (one ear at a time), and `stop_lingering_captures` kills any ffmpeg still
  writing into the meetings shelf at leave and at start-up — so a lost pid, a
  crash or a restart can never leave a recording running.
- **The anti-flap quiet.** After a meeting closes the watch re-baselines and arms
  nothing for `SNOTRA_COOLDOWN` (30 s): a meeting's own end can raise a
  microphone (a notification's sound, an app closing its device), and a watch
  that re-armed on that would deliver forever.

### M10 — The pipeline and the delivery (at leave)

Stop the capture → transcribe through the seat's whisper (the same engine the ear
serves) → mine → write → deliver:

- `<date>-<lane>-<slug>.md` — the dated minutes (lane default `ping`)
- `<date>-<lane>-<slug>.actions.md` — the mined decisions and actions
- `<date>-<lane>-<slug>.transcript.txt` — the transcript with its timestamps
- `<date>-<lane>-<slug>.wav` — the recording
- **delivery**: `systems/snotra/services/tts-lease/ymir-say.sh --mark-done` (a desktop note) AND a durable wake
  through the queue's own door — `bin/records/ymir-state.sh queue append check
  "meeting:<slug>" "check: …"` — so the meeting reaches Brokk with no arm and no
  sweep. The append is **bounded** (`timeout 20`): no queue pathology may wedge a
  delivery.

### M11 — The miner (`systems/snotra/services/record/snotra-mine.sh`)

- Mechanical commitment cues over the transcript: decisions ("we decided",
  "agreed", "confirmed", "the decision is", …) and action items ("I will",
  "we need to", "let's", "follow up", "send", "by <day>", …)
- Every line carries its **verbatim quote** and its **timestamp**, so it can be
  jumped to in the recording; the transcript is normalized from whisper's SRT,
  because `--output-txt` carries no times
- The trust note is written into the header, not implied: machine STT, wording may
  be imperfect, **no speaker diarization — owners are never assigned**, nothing
  invented
- A small exclusion list keeps openers ("good morning, let's get started") out of
  the action list

### M12 — The boot (`tools/mill/systemd/snotra-detect.service`)

- A user unit, `WantedBy=ymir.target`, seated from the seat's materialized copy
  (`%h/.fleet/snotra-detect.sh`) with `SNOTRA_DOORS_DIR` naming the durable tree
- Raised by **capability**, never by role: it joins the one table in
  `bin/engine/autoboot-lib.sh` (`AUTOBOOT_CAPABILITY_PROGRAMS`), so a seat's raise and
  its proof can never disagree about what it owes. A seat with a microphone owes
  the watch; a headless heart reports a clean skip.
- `ExecStop=-… leave` closes the book on a stop; a stop with nothing armed is a
  no-op, not a failure

## What the watch guarantees — and what it does not

```
guarantee[3]{edge,what,whose}:
  "guaranteed","every call whose start and end THIS machine can see — an app taking and releasing the microphone, or a conversation sink appearing and leaving","the watch's"
  "not guaranteed","a call that never touches this machine (a phone, another seat, a browser elsewhere) leaves nothing here to hear","the LANE's — a live-lane ear on the seat in the meeting, or the platform's own recording"
  "named false positives","any client that opens a microphone capture stream arms the ear, the seat's own voice tooling included","the seat's policy, below"
```

No claim is made beyond the machine's reach. The manual door (`snotra-detect.sh
arm`, and `snotra-capture.sh` by hand) stays for any call the watch cannot see.

### The seat's policy (what this seat does NOT treat as a call)

The ignore list and the thresholds are configurable per seat, and a seat may keep
its policy **in the hoard** at `hodd/data/snotra-detect.conf` (a `KEY=value` file
sourced before the environment) — so a room is tuned without editing the tree:

```
detect_env[10]{key,default,meaning}:
  "SNOTRA_IGNORE_APPS","—","space-separated app names never treated as a call"
  "SNOTRA_IGNORE_BINARIES","ffmpeg","process binaries likewise (the watch's own probe)"
  "SNOTRA_IGNORE_APP_RE","^PipeWire ALSA","an awk-matched app-name regex. The ALSA-plugin utility clients are never a call — and on a real seat BOTH the seat's dictation (voxtype) and arecord report under this name, so the rule also keeps dictation out of the meetings shelf. No backslash escapes: awk's -v strips them"
  "SNOTRA_ARM_DEBOUNCE","3","seconds a new mic stream must persist to arm"
  "SNOTRA_RELEASE_GRACE","5","seconds the mic must stay released to leave"
  "SNOTRA_SILENCE_DB","-45","the room-quiet floor in dB"
  "SNOTRA_SILENCE_SECONDS","300","seconds of quiet that end a meeting"
  "SNOTRA_COOLDOWN","30","the anti-flap quiet after a meeting closes"
  "SNOTRA_MIN_SECONDS","5","the shortest capture that is a meeting at all; below it the recording is KEPT and the shelf left alone"
  "SNOTRA_LANE","ping","the filename lane token"
```

## Private data

Audio recordings, transcripts, and meeting content are **private data**. They
live under `$YMIR_HOME/hodd/life/meetings/` and are never committed to
the public repo. The repo carries only the wiring scripts and the MCP server.

## First Law compliance

- No participant names in the repo
- No meeting content in the repo
- No audio files in the repo
- The hoard is the vault; the repo is the wiring

## The fleet's engines (measured 2026-09-24)

| seat | engine | model | notes |
|---|---|---|---|
| heimdall | `~/whisper.cpp.src/build/bin/whisper-cli` (CUDA) | `~/whisper.cpp/models/ggml-small.en.bin` | the brain (<gpu>) |
| whynot | `~/whisper.cpp/build/bin/whisper-cli` (CUDA) | `~/whisper.cpp/models/ggml-small.en.bin` | needs `LD_LIBRARY_PATH` |
| omarchy | `/usr/bin/whisper-cli` (CPU, `extra/whisper-cpp`) | `~/.local/share/voxtype/models/ggml-small.en.bin` | voxtype also has a full `meeting` mode |

The transcribe script discovers the engine (env → PATH → build trees →
`voxtype transcribe`), normalises to 16 kHz mono, sets `LD_LIBRARY_PATH` for a
build-tree binary, and picks GPU vs CPU by free VRAM (a resident rail model
starves CUDA — whynot's <gpu> always falls to the CPU).

### M13 — The live tail (`systems/snotra/services/ear/snotra-live.sh`), 2026-10-07

The ear above is **batch**: it records, and it writes the minutes **at the leave**.
The live tail is the other door — text that grows while the mouth moves.

```
snotra-live.sh start <slug> [topic]   begin; the document grows as spoken
snotra-live.sh status                 one TOON row + the newest line
snotra-live.sh tail                   follow the document
snotra-live.sh stop                   close -> mine -> minutes -> Rune
```

- **A chunked tail, deliberately.** ffmpeg segments the microphone into `N`s
  slices (`SNOTRA_LIVE_SEGMENT_SECONDS`, default 6); a worker transcribes each
  finished slice and appends `[hh:mm:ss] text`. Chosen over `whisper-server`'s SSE
  because it **resumes** — a crash loses at most one slice — and because it rides
  the engine discovery, the VRAM choice and the rail-yield the transcribe script
  already owns. The price is ~6-9 s behind the voice, and that was the trade.
- **A slice is complete only when the NEXT slice exists** (the segment muxer writes
  sequentially), so the loop can never transcribe half a word.
- **ONE document, ONE door.** Every writer and reader names the path through
  `doc_path()`; an earlier draft appended to a copy under `state/` while `tail` read
  the hoard copy, and the words grew where nobody looked.
- **This machine's microphone only.** `SNOTRA_LIVE_MONITOR=1` adds the default
  sink's monitor when a room needs both sides. Off is the truth of what one seat hears.
- **The source is the sentinel, not an unset.** `SNOTRA_MONITOR` unset resolves to
  the default sink, so `SNOTRA_MONITOR=off` was added to `snotra-capture.sh` to
  mean *microphone only*; unset behaviour is unchanged for the watch.
- **At the leave it calls the SAME pipeline `finalize` calls** —
  `snotra-transcribe.sh` with `SNOTRA_MINUTES_FILE`/`SNOTRA_TRANSCRIPT_FILE`, then
  `snotra-mine.sh`, then a Rune. The live document keeps its own `.live.md` name so
  the rolling record and the polished minutes never overwrite each other.
  `SNOTRA_LIVE_SKIP_MINUTES=1` skips the re-transcription when only the rolling
  record is wanted.
- **The rail model is resolved in order:** `SNOTRA_RAIL_MODEL` → the seat's recorded
  systemd drop-in choice → the resolver's `models[0]`. **Never `models[0]` first** —
  on a seat where that is a 21.7 GB model, taking it is a 3x slower summary.
- **THE WATCH IS UNTOUCHED.** `snotra-detect.sh` does not know this script exists; a
  call is still recorded by the ear exactly as before. The tail is a manual door.

Records: `docs/fixes/snotra/2026-10-07-the-live-tail-listens-and-writes.md`, and for
the resolver defect it leans on,
`docs/fixes/runtime/2026-10-07-the-living-rail-resolver-walked-one-level-short.md`.

## Dependencies

- **PipeWire** (system audio capture) — already present on Omarchy
- **ffmpeg** (audio recording) — already present
- **whisper.cpp** (transcription) — already built on heimdall
- **llama-swap** (summarization) — already running on the rail
- **Node.js** (MCP server) — already available
- **bun** (optional, for faster startup) — already installed on seats

## The watch and the engine

Meetily-Local is the recommended *capturer*; the **watch** (M9–M12) is Ymir's
own and needs no engine at all — it is a read of the PipeWire graph and a
capture of the conversation pair. Meetily has no call detection, and its Pro tier
lists auto-detect as future work; the watch is that half, built around whatever
capturer the seat uses.

### The engine's residency is the watch's to decide (2026-10-01)

`tools/mill/systemd/snotra-ear.service` — the whisper engine on `:8322` — is
**not a boot resident and carries no `[Install]` section**, so nothing can put
it in `ymir.target`. `systems/snotra/services/ear/snotra-detect.sh` seats it into
`~/.config/systemd/user/` at arm time and owns its whole lifecycle:

| when | what | why there |
|---|---|---|
| `do_arm`, after the capture is confirmed alive | `ear_up` | a refused arm must not cost the card a whisper for a meeting that is not being heard |
| `do_leave`, on **all three** exits | `ear_down` | no meeting, no VRAM owed — whichever way the leave ended |
| `do_leave`, **after** `finalize` returns | `ear_down` | `finalize` transcribes *through this engine*; lowering first leaves a recorded meeting with no minutes |
| `back_to_idle` | `ear_down` | the net for a watch that restarted mid-meeting, or a seat disabled by hand |

**Why a boot target was the wrong owner.** The engine is the largest VRAM claim
the ear makes — ~900 MiB on a strong box — and a strong box is also serving a
rail whose 262K model needs 13,790 MiB of a 16 GiB card. On heimdall the unit
being resident from login is what made **every rail request fail with a 500 that
named the model**: the preset's MTP draft context found no room. `WantedBy` and a
capability raise both decide by *what hardware the seat has*; only the watch's gate
decides by *whether a meeting is happening*. The old unit comment claimed a
capability raise that never existed — `AUTOBOOT_CAPABILITY_PROGRAMS` is
`snotra-detect` alone.

**The ear is deliberately absent from `AUTOBOOT_PROGRAMS`.** That list is the purge
list: `purge_stale_units` drops any unit in it that is not owed, and the ear is
owed by nothing (a headless heart must never load whisper). Adding it would have
the engine's own unit purged out from under the watch. Staying out leaves the copy
governed by exactly one file — the one in this tree — instead of a materialized
copy in `~/.config/systemd/user/` that nobody audits, which is how a 900 MiB engine
came to sit on a seat for three days with no meeting and no unit in the tree.

**`ear_seat_unit` REFRESHES, it does not merely seed** (corrected 2026-10-01, after
PR #258 shipped a version that tested only `[ -f "$dst" ]`). A seat is not
provisioned or unprovisioned — it is provisioned *to some version*, and that is
exactly where a stale `[Install] WantedBy=ymir.target` hides. So the function
`cmp -s`es the seated copy against the tree's and refreshes when they differ,
returning quietly when they match. The failure it prevents is the sharp one:
seeding-only would have removed the engine's residency from a seat that had
**never** had the unit and left it pinned on a seat that **always** did — the seats
that need the fix most. A seat that hand-wrote its own engine unit is **not**
refused: the watch warns and leaves it standing, because silently replacing a
hand-made unit is the same sin in the other direction.

**The rail yields during transcription.** `systems/snotra/services/ear/snotra-transcribe.sh` defaults
`SNOTRA_FREE_RAIL=1`: when the GPU is starved it sources
`~/.local/bin/voice-gpu-lib.sh` and calls `voice_ensure_vram 2048`, unloading the
resident rail model and retrying on GPU. A meeting is the thing that matters while
it is happening and the rail is the largest claim on the card, so the rail gives
way. `SNOTRA_FREE_RAIL=0` is the deliberate override for a seat that would rather
wait than have its rail evicted. The transcribe path already falls back to CPU by
free VRAM, and then to the seat's own `whisper-cli` when the ear lane is
unreachable — so a meeting is never lost to an engine that would not start.

Record: `docs/fixes/snotra/2026-10-01-the-ear-follows-the-gate.md`.
Measured: `~/CHANGELOG.md` 2026-10-01 and `$YMIR_HOME/hodd/docs/devtools/text-to-speech.md` 2026-10-01.

## Meetily-Local integration (future)

Meetily-Local (`github.com/Hankanman/Meetily-Local`) is the recommended engine
for the capture phase. The AppImage can be fetched from upstream releases:

```bash
# Pin the version (update this when a new release is verified)
SNOTRA_VERSION="0.1.0"
curl -L -o ~/.fleet/meetily-local.AppImage \
  "https://github.com/Hankanman/Meetily-Local/releases/download/v${SNOTRA_VERSION}/meetily-local-${SNOTRA_VERSION}-linux-x86_64.AppImage"
```

The AppImage is not vendored into the repo (100+ MB). A checksummed fetch from
the upstream release is the chosen path — it keeps the repo lean and the
version pinned. The ensure script can include this fetch step.

## Naming

- **Snotra** — the meeting ear (wise one, mistress of counsel)
- The watch is the **ear's own watch** (pricks up when a call begins; `snotra-detect`)
- The capture is the **ear** (hears the meeting)
- The transcription is the **brain** (processes what was heard)
- The miner is the **counsel** (what was decided, and who owes what)
- The minutes are the **record** (what was decided)
- The MCP face is the **voice** (speaks the record to agents)

---

## The store contract and the four doors (appended 2026-10-20)

The ear is one transport. The record is now a contract every transport writes into:

```
$YMIR_HOME/hodd/life/meetings/<work|personal>/<YYYYMMDD-HHMM>-<slug>/
  meeting.json  transcript.md  minutes.md  decisions.md  actions.md  cards.json
  audio/  .owner  .state  .transcribe.lock  .corrections.md
```

The lane is a **directory**; `meeting.json.workspace` must equal it. Audio is never in
git; `put` refuses it when the home does not ignore it. The record is append-only:
`put` refuses to overwrite, and a correction is `--as corrections`. `index.md` is
generated, never hand-edited.

| Door | Does |
|---|---|
| `systems/snotra/services/record/snotra-store.sh` | `new · put · state · index · list · verify · path` |
| `bin/thing/ping-room.sh` | raises MiroTalk on the current seat, `local|tailnet|public`, exclusive `ping.zerwiz.org` claim |
| `systems/snotra/services/ear/snotra-autojoin.sh` | calendar scan → plan → bot dispatch (dry-run unless `--apply`) |
| `systems/snotra/services/ear/snotra-bot.sh` | Vexa API door; the participant name is **Snotra**; HTTPS and a vault key required |

Transport is recorded, not inferred: `source` (`ear|bot|ping|telegram`), `transport`
(`pipewire|webrtc`), `platform` (`google_meet|zoom|teams|jitsi|ping|local`). If two
transports hear one room, the bot's transcript is authoritative for speaker labels and
the ear's audio is kept as evidence.

The private network law that governs where these run is `$YMIR_HOME/RULES/network.md`:
the always-on control plane is zerwizserver; whynot is compute; the dev seats are where
the operator is; and Þing is raised on demand, never assumed.

Tests: `bash tests/run.sh` — four suites, 61 assertions.

---

## Appended 2026-10-23 — the meeting pipeline, the place contract, and the reply path

The ear is one door in a chain now. This section is the owner's list of what exists and what each part refuses;
the full specification is the `docs/snotra/` shelf (README · the-pipeline · the-doors · the-places · the-record ·
the-letters · the-sound).

### The chain — one command

```bash
systems/snotra/services/cron/snotra-pipeline.sh run <meeting-dir> [--dry-run] [--draft] [--shrink]
systems/snotra/services/cron/snotra-pipeline.sh run --recent [DAYS]
```

`record → harvest → signal → transcribe → speakers → layout → project → agenda → letters` (+ `ladder` with
`--shrink`), one meeting at a time (flock), a rune per run, and four verdicts: **PASS · WARN · SKIP · FAIL**. A
step that cannot be proven stops the chain and names itself; a skip always prints its reason (Rule 25).

### The doors added with it

| door | what it does | what it refuses |
|---|---|---|
| `snotra-harvest.sh` | the bot's own audio out of its store, verified against `file_size_bytes`; `speakers` splits by `speakerIndex`; `signal` audits the STT log | a download whose bytes do not match; a log of `ok:true, text:""` (exit 1) |
| `snotra-transcribe-bot.sh` | whisper over the meeting's own audio → `evidence/bot/transcript.bot.txt` + `transcribe.json` | audio that is not `is_meeting_stream: true` (Rule 33); fewer than 50 words |
| `snotra-project.sh` | the record onto the place's boards by kind: member · native due · checklist · verified read-back | a card moved by a human (`drift`, left in place); a place on another surface |
| `snotra-agenda.sh` | the dated agenda card — proposed → due → **open questions last** | a record that names no company/place |
| `snotra-letter.sh` | one letter per participant: text + HTML + attachments, multipart draft | an attachment it does not carry; a send without an approval record |
| `snotra-promote.sh` | accept · reject · hold, appended to `promotions.jsonl`, read back | a promotion with no `--by "<person>"`; a record that does not validate |
| `snotra-layout.sh` | the folder standard; `apply` retires a stray to `evidence/hand-built/` | a fifth hand-built letter at the top level |
| `snotra-audio-ladder.sh` | verify → require a transcript → Opus 16 kbps → strip the duplicated `pcm` | shrinking before a transcript exists |
| `snotra-board.sh` | `check`/`ensure` a declared board: lists, labels, private, in the house's org | creating a board that already exists by name |
| `snotra-mail-watch.sh` | replies: `status` · `check` · `record` · `register` (each decision beside the reply that names it) | counting a reply that names no decision id; promoting without `--by` |
| `snotra_paths.py` | every meetings shelf in one resolver | — |

### The place contract (where a shape lives)

`hodd/identity/places/<company>/<place>/place.yaml` — `surface` (trello | gimle | jira) · `board` (a NAME,
resolved through `trello-map.yaml`) · `lists` per kind · `labels` · `roles` (chair, operator) · `cadence` ·
`retention` · `authority` (the decisions or documents the shape comes from) · `never` (the laws quoted by the
doors). **No company, board or list name appears in `systems/snotra/*.py`** — grep-proven; a second company
files correctly with no code change, and a place declaring `surface: gimle` is refused until that adapter exists.

### Installation and updates

- the doors ship with `bin/` in the npm package; `bin/engine/ymir-install.sh`'s snotra step installs the ear;
- **migration `0012-places-shelf`** gives an existing home the `places/` shelf and one declared example
  (`example/projects`), because before it a fresh install could only answer "no place profile";
- **cron**: `@dev 07:10 bin/time/nornir-job-snotra-mail.sh` (in `config/cron.yaml.example`) reads the letters'
  replies nightly; the pipeline may be scheduled as `--recent 1 --draft` once the Allfather says so;
- the state the doors need (`VEXA_API_URL`, `VEXA_S3_*`, the Trello grant in `~/.pi/agent/mcp-auth.json`) is
  read from env/config with one documented default each — never invented.

## Appended 2026-10-24 — the outbound gate stands in every door (plan 124 §7)

Before this day the approval gate existed and was **enforced by a caller**. `snotra-approve.sh` bound the
operator's word to a draft's exact RFC822 bytes, and `snotra-letter.py send` asked it — but the other doors never
did. The audit (plan 124 §7) measured three: `mail-send.sh send` POSTed `drafts/send` without asking,
`calendar-invite.sh` posted with `sendUpdates=all` so **Google mailed every attendee the instant an event was
made**, and Gná's absent send path was a debt nobody had written down.

**The contract now, and it is a contract of the DOOR, not of a caller:**

```
outbound_gate[6]{rule,why}:
  "every outbound door calls `snotra-approve.sh gate <kind> <key>` before it builds a request","a check in a caller is a habit; a check in the door is a gate"
  "kinds: `mail` (a Gmail draft id) and `event` (an event key naming the body that would be posted)","one word, two shapes of thing that can leave"
  "the word is bound to BYTES: mail → `mail-send.sh raw <id>`; event → the rendered payload, held by `approve-event <key>`","edit one character and it reads STALE, not 'approved earlier'"
  "an approval is SPENT by the send it authorised (a `.sent` sidecar), and a replay is refused ALREADY SENT","one word, one send; a second click is not a second letter"
  "google mails nobody by default: `sendUpdates=none` unless a fresh approved event body says otherwise; `cancel --notify` is gated the same way","an invitation is outbound mail, and so is a cancellation"
  "every refusal, spend and approval is carved into the Runes with subject, operator and reason","a refusal is evidence; 'what did we tell them, on whose word' is answerable without reading mail"
```

**Where it lives.** The record is **state, not a document**: `$XDG_STATE_HOME/ymir/approvals/<key>.json` (with
`<key>.sent` after a send) and `…/approvals/pending/<key>.json` for a held event body — never in git, never in
the home.

**Endpoints are configuration (Rule 07), never constants:** `YMIR_GMAIL_API_BASE` · `YMIR_CALENDAR_API_BASE` ·
`YMIR_OAUTH_TOKEN_URL`, each defaulting to the real Google door. That is also what makes the gate **provable
without a mailbox** — `bin/time/snotra/tests/test_outbound_gate.py` stands a local HTTP server behind those three
variables, builds a throwaway home with a real `age` vault, and runs the shipping doors unchanged: 12 proofs
(unapproved refused and recorded · approved sends once · replay refused · stale refused · invite with attendees
posts nothing · approved invite sets `sendUpdates=all` · stale event refused · no attendees mails nobody ·
cancel gated · the door's own default · Gná's ward · no door in `bin/` sends around the gate). Each door carries
its half as `--self-test`.

**Doors, at a glance**

| door | verb | asks the gate when |
|---|---|---|
| `mail-send.sh` | `send <draft-id>` | always — before the send request; spends the word on success |
| `calendar-invite.sh` | `create … --attendees` | always — `sendUpdates=all` only on a fresh approved body |
| `calendar-invite.sh` | `cancel <id> --notify` | always — the cancellation body is its own key |
| `snotra-letter.sh` / `snotra-letter.py` | `send <dir> --approved` | its own check remains, but it is now a courtesy: `mail-send.sh send` refuses anyway |

**What is owed, and deliberately not built.** Gná (`bin/mail/`) still has **no send path**. Her drafts and
approvals are owed to plan 116 (P1) and must arrive through this same gate — `tests/test_gna.py::NoSendCapability`
fails if a send verb appears in that directory, and `bin/mail/README.md` says so on its face. The approval record
lives on one seat; plan 126 decides which records must ride the vault.

**Owner docs.** How-to: `docs/features/the-outbound-gate.md` · the gate's own history:
`docs/fixes/snotra/2026-10-23-the-approval-gate-was-not-in-the-tree.md`,
`docs/fixes/snotra/2026-10-24-the-gate-is-in-every-door.md` · the shelf: `docs/snotra/the-letters.md`.

## Windows/WSL file voice road (2026-11-02)

Skirnir's services/ear.sh and mouth.sh use native-voice.sh to invoke voice-file.ps1
and voice-io.py on Windows, keeping Windows loopback local when WSL has a separate
network namespace. The adapter reuses Whisper inference and Kokoro speech APIs,
ffmpeg, speech-text.py and WAV validation. Whisper receives the selected language;
unsupported Swedish synthesis is refused. voice-service.ps1 controls installed
engines with status/start/stop/restart, loopback, executable and creation-time
checks, never saved-PID authority. It installs nothing and opens no microphone.

Configuration, defaults and limits: docs/features/voice-files-on-windows.md.
File-chain verification is separate from microphone/UI/meeting acceptance and
second-machine fleet proof. voice.sh --no-speak suppresses early and final speech;
synthesis/playback failures return nonzero.## Windows UTF-8 voice restart (2026-11-03)

The API passes UTF-8 to its Python children. The speech cleaner subprocess now
also uses explicit UTF-8 for its text pipes: Windows locale encoding otherwise
encoded accented answer text differently from the child's UTF-8 stdin, failing
before Kokoro synthesis. A Unicode-answer regression exercises the real cleaner
under PYTHONIOENCODING=utf-8; ASCII-only smoke cannot prove this boundary.
