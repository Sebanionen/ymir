# Snotra — the meeting ear

## What it is

**Snotra** is Ymir's meeting ear: it **captures** a call, **transcribes** it locally, and
**mines the minutes** into the hoard. On the meeting seat it watches for the call edges,
records, transcribes with whisper.cpp, extracts action items, and exposes a **read‑only**
face so an agent can read meetings without writing them.

## What you need

- A seat with a **microphone** (a call seat); a headless heart reports a clean skip.
- The engine: `systems/snotra/services/ear/snotra-ensure.sh` discovers it and installs what is
  missing (whisper.cpp + one model). Arch: `pacman -S whisper-cpp`. Debian/Ubuntu: the same
  packages are unpacked **without root** into `~/.local/opt/whisper.cpp` (needs only
  `apt-get download` and `dpkg-deb`), so a seat whose `sudo` wants a password still gets an
  engine. If neither road can finish, the installer prints the one command for you and exits
  3 — it never claims success.

## Do it

```bash
systems/snotra/services/ear/snotra-ensure.sh status            # engine + model present?
systems/snotra/services/ear/snotra-ensure.sh ensure --install  # install what is missing
```

- **The watch** (`snotra-detect`) is raised by capability on any seat with a mic; it is
  what notices the call.
- **The MCP face** is read‑only, on `:8321` (the heart) — an agent reads meetings; it
  cannot post.
- **The minutes** land in the hoard (`$YMIR_HOME/hodd/...`), never the tree.

## Notes and limits

- **Local and private.** Transcription is whisper.cpp on the seat — audio does not go to
  a cloud by default.
- **Read‑only face.** The MCP lets an agent *read*; writing minutes is the pipeline's, not
  the agent's.
- **Capability‑gated.** No microphone, no watch — and the seat says so rather than
  pretending.

## If it does not work

| What you see | What to do |
|---|---|
| `status` shows the engine missing | `snotra-ensure.sh ensure --install` (per‑OS road printed). |
| The installer exits 3 | It needs your hand: run the one command it printed (usually `sudo apt-get install -y whisper.cpp`), then `status`. |
| The engine is found but nothing transcribes | Check the audio is 16 kHz mono; the door normalises with `ffmpeg` when present and copies otherwise. |
| The watch never fires | The seat has no mic — expected on a headless seat; check the `fleet` step's capability raise. |
| No minutes in the hoard | The pipeline did not complete — check the job log and the hoard's minutes path. |
