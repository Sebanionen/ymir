# The ear had a model and no engine — now it hears

**Date:** 2026-11-12 · **Component:** snotra · **Doors:**
`systems/snotra/services/ear/snotra-ensure.sh` (the install road),
`snotra-transcribe.sh`, `snotra-live.sh`,
`.agents/skills/galdr-ymirsystem/assets/snotra-meeting-ear.md`

Measured on this seat (Ubuntu 26.04 in WSL2, 16 CPUs, `sudo` wants a password). The model
was on disk; the engine column was a dash, so a meeting could be recorded and never read.

## Before

```
snotra[1]{engine,model,voxtype,seat}:
  "—","/home/ymir/whisper.cpp/models/ggml-small.en.bin","—","DESKTOP-FRS81OR"
```

`ensure --install` could not mend it either. On Debian/Ubuntu it only tried
`sudo -n apt-get install whisper.cpp`; with a password-gated sudo that fails, the script
printed nothing useful and the `install` path exited 0 after `status`, so the failure was
indistinguishable from a success.

## After

```
snotra[1]{engine,model,voxtype,seat}:
  "/home/ymir/.local/opt/whisper.cpp/bin/whisper-cli","/home/ymir/whisper.cpp/models/ggml-small.en.bin","—","DESKTOP-FRS81OR"
```

`snotra-ensure.sh ensure --install` is the road that seated it, in under two seconds and
without root. A source build (`~/whisper.cpp.src/build/bin/whisper-cli`, static CPU kernel)
appeared on the seat later the same morning — another hand's work, the fleet's usual shape —
and discovery prefers a build tree over the packaged copy. The packaged copy is the road for
the seat this errand measured: no build tree, no password-free sudo.

## The road that needs no sudo

Debian and Ubuntu publish whisper.cpp as three small packages. `apt-get download` and
`dpkg-deb -x` need no privilege, so the ensure script now unpacks them into
`$SNOTRA_ENGINE_PREFIX` (default `~/.local/opt/whisper.cpp`):

| Path under the prefix | What it is |
|---|---|
| `bin/whisper-cli` | the engine the ear calls (with `whisper-server` and `whisper-quantize`) |
| `lib/libwhisper.so.1`, `libggml.so.0`, `libggml-base.so.0` | the libraries beside it |
| `backends/libggml-cpu-*.so` | one CPU kernel per microarchitecture |

`libggml` loads its CPU kernel from a compiled-in directory
(`/usr/lib/x86_64-linux-gnu/ggml/backends0`) that an unprivileged copy does not have, and
`GGML_BACKEND_PATH` accepts one file, not a directory. So the transcribe door picks one
kernel from `backends/` by `/proc/cpuinfo`: `haswell` for AVX2+FMA, `x64` as the floor.
The choice is worth making — measured here, the same 8-second clip took 2.5 s on
`haswell` and 11.8 s on `x64`.

The road, reproduced from an empty prefix:

```
$ SNOTRA_ENGINE_PREFIX=/tmp/snotra-prefix snotra-ensure.sh ensure --install
snotra: unpacking the packaged engine into /tmp/snotra-prefix (no root) …
snotra: engine seated at /tmp/snotra-prefix/bin/whisper-cli
snotra[1]{engine,model,voxtype,seat}:
  "/tmp/snotra-prefix/bin/whisper-cli","/home/ymir/whisper.cpp/models/ggml-small.en.bin","—","DESKTOP-FRS81OR"
```


A build tree (the fleet's other seats) links its kernel statically, has no `backends/`,
and is untouched by this.

## When only the operator can finish it

The install roads now end in one of four statuses: 0 the ear can transcribe, 1 still
missing, 2 usage, **3 the operator must run one command**. Status 3 prints the command
and does not claim success:

```
snotra: this seat needs the operator. Run exactly:

  sudo apt-get install -y whisper.cpp
```

That path was exercised by pointing `SNOTRA_ENGINE_PREFIX` at an unwritable location:
the unpack fails, passwordless sudo fails, and the door exits 3 with the command above.

## The proof — the ear's own door, not the binary

Audio: the 15-second opening of `en-Wikipedia-Ignore_All_Rules.wav`, the English speech
sample that ships inside Ubuntu's `whisper.cpp` package
(`/usr/share/sounds/debian/samples/`), trimmed with Python's `wave` module. No microphone
was opened.

```
$ RAIL_MODEL=gpt-oss-20b \
  SNOTRA_TRANSCRIPT_FILE=/tmp/opencode/snotra-proof/transcript.txt \
  SNOTRA_MINUTES_FILE=/tmp/opencode/snotra-proof/minutes.md \
  systems/snotra/services/ear/snotra-transcribe.sh \
    /tmp/opencode/snotra-proof/sample-15s.wav "engine proof"

Transcribing: /tmp/opencode/snotra-proof/sample-15s.wav
Topic: engine proof
Seat: DESKTOP-FRS81OR
  engine: /home/ymir/.local/opt/whisper.cpp/bin/whisper-cli
  model:  /home/ymir/whisper.cpp/models/ggml-small.en.bin
Minutes written: /tmp/opencode/snotra-proof/minutes.md
  Skipping summary (no rail key or empty transcript)
Done: /tmp/opencode/snotra-proof/minutes.md
```

The transcript it produced:

```
[00:00:00.000 --> 00:00:08.000] Wikipedia. Ignore all rules from en.wikipedia.org. 2
[00:00:08.000 --> 00:00:15.000] If a rule prevents you from improving or maintaining Wikipedia, ignore it.
```

The trailing `2` on the first line is whisper's own artefact, kept unsmoothed so the
quote is what the door wrote. Whisper is not bit-deterministic: a later run of the same
clip returned `Wikipedia. Ignore all rules. If a rule prevents you from improving or
maintaining Wikipedia, ignore it.` — the same words, one phrase shorter, in one segment.
What matters for this errand is that the door produced text at all.

## Two dead neighbours found on the way

The errand's door could not run either, and neither could its sibling. Both were the same
fault the capture door had on 2026-11-09, still present on this path:

- `snotra-transcribe.sh` looked for `bin/vault/hoard-lib.sh` two directories up, which
  from `services/ear/` is not the repo root. Run from the checkout it died on
  `YMIR_HOME: unbound variable`. It now walks up to the tree carrying `RULES/` and
  `.agents/`, sources the resolver there, and refuses loudly when the home is unresolved.
- `snotra-live.sh` still carried the retired shim's pointer, aimed at a path that does
  not exist, so every verb answered 127. Its repo root was also one level above the tree,
  so the rail resolver and the rune append pointed at nothing. Both are mended; the live
  tail is reachable again.

## What changed

- [x] `snotra-ensure.sh` — the no-root package road; `find_whisper` sees the prefix;
      install returns 3 with the operator's one command; `install` no longer exits 0 on a
      failed install; the header documents the road and the exit codes; version 1.0.1.
- [x] `snotra-transcribe.sh` — the packaged prefix in discovery; `lib/` and `backends/`
      on the engine's environment with `pick_backend`; the resolver walks to the repo root.
- [x] `snotra-live.sh` — the prefix in discovery; the same engine environment; the shim
      pointer and the wrong repo root removed.
- [x] `.agents/skills/galdr-ymirsystem/assets/snotra-meeting-ear.md` — the install road
      and the prefix layout described where M0 describes the engine.
- [x] `docs/features/snotra-the-meeting-ear.md` — the operator-facing install note.

## What is not mended here

- The seat's recorded home (`~/.config/ymir/home`) is a Windows path
  (`/mnt/c/Users/.../ymirhome`); it exists, so the door writes there. Whether this seat
  should keep its home on the Windows side is the Allfather's call, not this fix's.
- The live tail's microphone law (`SNOTRA_LOCAL_ROOM=1`) and the watch are untouched, as
  the errand scoped.
