---
section: planned-named-and-designed-not-yet-built
---
| People | **Skírnir — the Allfather's assistant** (`bin/assistant/`) | A deliberately limited presence that answers when he is away: an approved digest (never the vault), no tools at all, an output gate that refuses URLs/links/images and fails closed on a canary, and a ledger of every question and refusal. NDA/contracted facts are answered only to the operator or a **named party**. `kb-export.sh` · `ask.sh` · **`voice.sh`** (mic → whisper.cpp → digest-only model → **Kokoro**, sentence by sentence, Piper as fallback) · `walls-test.sh` (10 red-team assertions) · **canaries derived at export time** (194) · a normalising gate | [docs/features/skirnir-the-assistant.md](docs/features/skirnir-the-assistant.md) |
