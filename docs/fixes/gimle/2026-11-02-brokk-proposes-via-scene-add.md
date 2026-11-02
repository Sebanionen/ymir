## gimle · 2026-11-02 — Brokk proposes via scene.add and the bridge carries it

### What

- **`bin/gimle/brokk-backend.py`** — defines a `scene_add` tool and passes it to opencode-go with
  `tool_choice: auto`; forwards `delta.tool_calls` as `{type: "tool_call", delta}` frames. The Brokk
  backend now proposes edits instead of only describing them.
- **`server/ttd-bridge/bridge.mjs`** (whiteboard repo) — `buildUpstreamRequest` accepts and forwards
  `tools`/`tool_choice`; `parseUpstreamChunk` extracts `delta.tool_calls`; `translateUpstream` emits
  `ttdToolCall` frames. Tests updated and passing (45/45).

### Why

Plan 157 step 4a: the converse/consent loop needs the model's proposals to reach the panel. Without
tool-call forwarding, every proposal died in the bridge.

### Verified

- `node --test server/ttd-bridge` passes (45/45).
- Live test: a prompt to the Brokk backend returned `tool_call` frames naming `scene_add`.
