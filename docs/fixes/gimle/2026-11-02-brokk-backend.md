## gimle · 2026-11-02 — Brokk as the backend behind the whiteboard panel

### What

- **`bin/gimle/brokk-backend.py`** — new: Brokk as the AI backend the whiteboard panel can point at.
  Accepts the TTD contract (`POST /v1/ai/text-to-diagram/chat-streaming`), reads a consented shared
  scene when one is named, enriches the prompt with it, and streams Mermaid back. Answers as Brokk
  (house voice, proposes never applies). Port 8491, env `OPENCODE_API_KEY`.

### Why

Plan 157 step 3: the plain bridge forwards to a model; this backend is the door through which Brokk
reasons about the board instead of a bare model.

### Verified

- Syntax checked; deployed to `zerwizserver` pending.
