Craig,

Following up on the record corrections and the work we've been doing on Snotra.
We're now planning the next phase — extracting Skírnir as a standalone module.

## Skírnir as a standalone module

Skírnir is Ymir's assistant system — the messenger who is sent on errands and
returns with news. He handles Telegram (voice and text), knowledge base (research,
grounding, querying), gate (asks, approval, escalation), and rooms (coordination
spaces). He is the Allfather's primary interface to Ymir.

We're extracting Skírnir from Ymir into a standalone, reusable module that any
application can use — without Ymir. The goal is to make the assistant/knowledge
base available as a library (Python package + optional web UI + REST API) that
works with online model APIs (OpenAI, Anthropic, Google) instead of requiring
local infrastructure.

## What this means for you

1. **Knowledge base** — Skírnir's knowledge base (facts, questions, approvals,
   evidence) becomes a standalone module. Any app can store, query, and ground
   facts without Ymir.

2. **Research engine** — Web search and source verification, powered by online
   search APIs (Exa, etc.). No Ymir wrapper needed.

3. **Gate (asks/approval/escalation)** — Human-in-the-loop approval for facts
   and decisions. Works standalone with local state.

4. **Voice I/O** — Speech-to-text and text-to-speech via online APIs (OpenAI
   Whisper, Google STT, OpenAI TTS, etc.). No local whisper.cpp or piper needed.

5. **Telegram bot** — Standalone Telegram bot with knowledge base integration.
   User provides their own bot token.

6. **Rooms** — Coordination spaces for multi-agent collaboration. Local state.

## Multi-harness support

Skírnir will work with any AI harness:
- Pi (current — already working)
- Claude Code (MCP server + CLI)
- Cursor (MCP server + CLI)
- Codex (CLI + Python SDK)
- OpenCode (MCP server + CLI)
- Any HTTP client (REST API)
- Any Python app (Python SDK)
- Any shell script (CLI)

## What we need to remove (Ymir dependencies)

- bin/records/mimir.sh → Optional (skip or use simple JSON store)
- bin/records/runes-append.sh → Optional (skip or use simple log)
- bin/model/rail-resolve.sh → Direct API calls (OpenAI, Anthropic, etc.)
- Pi/OpenCode harness → Direct API calls or MCP
- Ymir's tool registry → Bundled tool registry

## What Skírnir uses AI for

- Paraphrasing approved facts (model_small)
- Summarizing conversations (summary_maybe_update)
- Research (via Exa MCP, no LLM)

The model is called via the rail (llama-swap in Ymir, online API in standalone).
Without a model, Skírnir still works — knowledge base, grounding, querying, and
gate all work without AI. Only paraphrasing and summarization need a model.

## Relationship to Snotra

Skírnir and Snotra are complementary but independent:
- Snotra = meeting-to-action pipeline (transcripts → records → cards → routing)
- Skírnir = assistant/knowledge base (research, grounding, querying, gate)

They can be used together (Skírnir learns from Snotra's meeting records) or
independently.

## Open questions for you

1. Would a standalone assistant/knowledge base be useful for your projects?
2. Which features would you use most: knowledge base, research, gate, or voice?
3. Would you prefer Python-only or also a TypeScript/Node.js version?
4. Any specific integration needs for your workflow?

Looking forward to your thoughts.

— <the operator>

**2026-11-03 (correction, appended):** the operator's name was redacted — it is personal data and belongs in the home, not in a public repository (RULES/04, RULES/06).
