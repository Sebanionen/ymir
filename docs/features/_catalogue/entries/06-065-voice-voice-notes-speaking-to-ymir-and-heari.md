---
section: planned-named-and-designed-not-yet-built
---
| Voice | **Voice notes — speaking to Ymir and hearing it answer** (`bin/assistant/{ear.sh,mouth.sh,voice-handler.sh}` · `~/.pi/agent/telegram.json` · [how-to](docs/features/voice-notes-in-and-out.md)) | A voice note in becomes a transcript on the house's own ear (Whisper); the reply comes back spoken by its own mouth (Kokoro). The outbound handler is **one step with the reply on stdin** — an array in `outboundHandlers[].template` is a sequence of commands, and reading it as one command split into words is why every voice reply silently failed. The ear now raises the mouth on arrival, so the raise hides under the thinking instead of preceding the first word | owner-only chat |
