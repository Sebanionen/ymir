# Snotra — Business Launch Document

**Prepared for:** Reygan Assareh (Synteon Technologies)
**Prepared by:** <the operator> <the operator> (Ymir / Whynot Productions)
**Date:** 2026-10-31
**Status:** Draft for partner review

---

## 1. Executive Summary

Snotra is a **meeting-to-action pipeline** that turns transcripts into accountable records.
It extracts decisions, actions, open questions, and sign-offs from meeting transcripts,
projects them onto organization tools (Trello, Monday, Asana, Jira, and more), and routes
them to the right people through the right channels (email, todo, calendar, chat).

**The differentiator:** Snotra is "hygiene-out, not funnel-in." Competitors (Fireflies, tl;dv,
Otter) create new issues — often duplicates. Snotra checks against existing issues and produces
"board truth" metrics (stale issues, ownerless, duplicates, decisions without follow-up,
PM hours saved) that no notetaker can claim.

**The market:** Every team that has meetings and uses a project management tool. The SaaS
model charges per seat, with ~82% gross margin and break-even at ~20 users.

**The vision:** Snotra is not just a standalone product — it is a module that can be embedded
into any application we build. The meeting-to-action pipeline becomes a feature, not a separate
product. Any app with meetings, decisions, or action items can benefit.

---

## 2. The Problem

### 2.1 What happens after a meeting today

1. Someone takes notes (or a bot records it)
2. Notes are shared (or not)
3. Action items are forgotten or duplicated
4. Decisions are lost or disputed
5. Open questions never get answered
6. The board (Trello/Jira/Asana) drifts from reality

### 2.2 What competitors do

Fireflies, tl;dv, Otter, and others:
- Record and transcribe meetings
- Extract action items (often as new tasks)
- Create new issues/tasks (often duplicates)
- Send a summary email

**What they don't do:**
- Check against existing issues (hygiene)
- Track board truth (stale, ownerless, duplicates, decisions without follow-up)
- Route to multiple channels (email + todo + calendar + chat)
- Enforce sign-off workflows
- Provide a rules engine for per-board behavior

### 2.3 What Snotra does differently

- **Evidence-based:** Every decision and action carries a timestamp and verbatim quote
  from the transcript, or it's marked unverified and withheld.
- **One owner, one date:** "We", "the team", "someone" are not owners. A date that
  was not stated becomes "date unresolved" with a decide-by date.
- **Board truth:** No new issues without a receipt against existing ones. Metrics
  show stale, ownerless, duplicates, decisions without follow-up, PM hours saved.
- **Capture-agnostic:** Doesn't care which notetaker the customer already pays for.
  Ingests from 8 sources (Read AI, Fathom, Zoom, Teams, Meet, Gong, Otter, Knit).
- **Org-tool-agnostic:** 7 adapters (Trello, Monday, Asana, Jira, ClickUp, Notion,
  Linear). The place contract declares which tool; the automation doesn't know.
- **Rules engine:** Per-board, per-project, per-company behavioral rules with
  inheritance. Rule A (This Week + member → assign + notify + steps), Rule B
  (Done + sign-off → To Sign-off), note-on-mis-move for every automated correction.
- **Never auto-close:** Transcript evidence + human confirmation required before close.
- **Identity matching:** Speaker-to-user mapping table per customer.
- **AI models:** Three AI models: transcription (speech to text), summarization
  (transcript to structured minutes), and reasoning (extraction, classification,
  dedup, suggested steps, identity matching). Extraction and mining have a
  deterministic baseline (no AI). The reasoning model is optional and improves
  quality but is never the authority. Users configure their own API keys (OpenAI,
  Anthropic, Google, Azure) through env vars, config file, or web UI. All keys
  stored encrypted at rest.

---

## 3. The Product

### 3.1 Core pipeline

```
Transcript → Parse → Extract → Merge → Validate → Render → Cards → Route
```

1. **Parse:** Transcript → segments (speaker, timestamp, text)
2. **Extract:** Deterministic extraction of decisions, actions, open questions
3. **Merge:** Curated entries win over machine candidates by ID
4. **Validate:** 8 validation gates (evidence, owner, date, definition of done, etc.)
5. **Render:** Minutes, decision log, action register, per-person briefs, follow-up email
6. **Cards:** Trello/organization tool payloads (idempotent by record-key)
7. **Route:** Dispatch to channels (email, todo, calendar, chat, knowledge base)

### 3.2 Organization tool adapters

| Tool | Status | API | Auth | Complexity |
|------|--------|-----|------|------------|
| Trello | Built | REST | OAuth2 | Low |
| Monday.com | Built (stub) | GraphQL | OAuth2 | Medium |
| Asana | Built (stub) | REST | OAuth2 | Medium |
| Jira | Built (stub) | REST v3 | OAuth2 | High |
| ClickUp | Built (stub) | REST | OAuth2 | Medium |
| Notion | Built (stub) | REST | OAuth2 | Medium |
| Linear | Built (stub) | GraphQL | OAuth2 | Medium |

### 3.3 Transcript ingestion sources

| Source | Status | API | Auth |
|--------|--------|-----|------|
| Knit (unified) | Built | REST | API key |
| Read AI | Built (stub) | REST | OAuth2 |
| Fathom | Built (stub) | REST | OAuth2 |
| Zoom | Built (stub) | REST | OAuth2 |
| Teams | Built (stub) | Graph | Azure AD |
| Google Meet | Built (stub) | REST | Google OAuth |
| Gong | Built (stub) | REST | OAuth2 |
| Otter | Built (stub) | REST | OAuth2 |

### 3.4 Rules engine

Per-board, per-project, per-company behavioral rules with inheritance:
- House defaults → company → project → board
- Boolean flags: rule_a, rule_b, note_on_mis_move, friday_synch, grooming, auto_assign, notify_on_assign, never_auto_close, identity_matching
- Routing channels: decision, action, question, signoff → board, email, todo, calendar, chat, kb
- Escalation rules: overdue_days, escalate_to

### 3.5 Action routing

From transcription to action across channels:
- **Board:** Create/move cards on organization tool
- **Email:** Draft emails to owners/deciders/participants
- **Todo:** Create todo items
- **Calendar:** Create calendar events for due dates
- **Chat:** Post to Slack/Teams/Discord (stub)
- **Knowledge base:** File in Notion/Confluence (stub)

### 3.6 AI models

Snotra needs three AI models:
- **Transcription** (speech → text): OpenAI Whisper, Google STT, Azure Speech, AssemblyAI, Deepgram, or local whisper.cpp
- **Summarization** (transcript → structured minutes): OpenAI GPT-4o, Anthropic Claude, Google Gemini, or local LLM
- **Reasoning/Logic** (extraction, classification, dedup, suggested steps, identity matching): OpenAI GPT-4o-mini, Anthropic Claude Haiku, Google Gemini Flash, or local LLM

Extraction and mining have a deterministic baseline (no AI). The reasoning model is optional and improves quality but is never the authority. Without a reasoning model, Snotra falls back to deterministic logic. Without a transcription model, Snotra cannot process audio at all.

Users configure their AI models via env vars, config file (~/.snotra/config.yaml), or web UI settings page. All keys stored encrypted at rest.

### 3.7 Model connection (UI and backend)

Users connect models through a provider registry with a unified adapter interface:
- Select provider (OpenAI, Anthropic, Google, Azure, or local)
- Enter API key (masked input)
- Test connection (small API call, shows latency)
- Select model (dropdown populated from provider's API)
- Configure fallback (optional secondary provider if primary is down)

Backend: TranscriptionAdapter and SummarizationAdapter ABCs, config storage encrypted
with age, connection testing, fallback support. API endpoints for provider list,
config get/update, connection test, and model list.

### 3.8 What Snotra does that we haven't covered yet

The following features exist in Ymir's Snotra but need to be built for the
standalone module:

- **Live tail / real-time transcription** — transcribe while the meeting is
  happening (chunked, 6-second slices, growing document). Browser-based
  MediaRecorder → WebSocket → transcription API.
- **Audio ladder / retention** — Opus 16 kbps compression, 24-day retention,
  auto-cleanup. Audio is ephemeral; text is the record.
- **Letter system** — per-person emails (briefs), follow-up emails, agenda
  drafts. All require operator approval before sending.
- **Store contract enforcement** — append-only, no overwrite. Corrections are
  appended as new entries. index.md is generated, never hand-edited.
- **Provenance enforcement** — every card carries record-key: <meeting-id>:<item-id>
  for traceability. Second run updates, never duplicates.
- **Sign-off flow (grade-based)** — Grade A (everyone confirms), Grade B
  (approver + affected owners), Grade C (silence = acceptance after 2 business
  days). Chair signs last.
- **Friday Synch and Monthly Grooming** — status updates on This Week cards,
  Backlog triage into overdue/due-soon/backlog.

Build order: provenance (1 day) → store contract (1 day) → audio ladder (1 day) →
letter system (2-3 days) → live tail (2-3 days). Total: 7-9 days.

---

## 4. Competitive Positioning

### 4.1 The "hygiene-out" differentiator

Competitors (Fireflies, tl;dv, Otter) are **funnel-in**: they create new issues,
often duplicates. Snotra is **hygiene-out**: no new issues without a receipt against
existing ones.

### 4.2 Board truth metrics

| Metric | What it measures | Why a notetaker can't claim it |
|--------|-----------------|------------------------------|
| Stale issues | Open too long | Notetakers don't track issue age |
| Ownerless issues | No assignee | Notetakers don't check assignment |
| Duplicates | Same action captured twice | Notetakers create new, don't check existing |
| Decisions without follow-up | Decided but no action | Notetakers don't track decision-to-action |
| PM hours saved | Hours of manual PM work avoided | Notetakers don't measure PM effort |

### 4.3 Competitive moat

1. **Evidence-based:** Every status change points to a timestamped transcript row.
   Builds trust that "AI summary" never earns.
2. **Capture-agnostic:** Doesn't care which notetaker the customer pays for.
   Selling argument against IT.
3. **Depth:** Agenda logic, drift detection, review gate, rules engine. Not just
   "transcript → status change" — that's what Atlassian (Rovo + Loom) already does.
4. **Never auto-close:** Transcript evidence + human confirmation required.
   A hallucinated "this is done" is worse than a missed action.
5. **Identity matching:** Speaker-to-user mapping table per customer.
6. **Rules engine:** Per-board, per-project, per-company behavioral control.
7. **AI for logic:** Three AI models (transcription, summarization, reasoning).
   Deterministic baseline with optional LLM pass. The reasoning model improves
   extraction, classification, dedup, suggested steps, and identity matching.

### 4.4 Competitive threats

- **Atlassian (Rovo + Loom):** Already does transcript → status change. Defense is
  depth, not the feature itself.
- **Fireflies/tl;dv/Otter:** Feature parity on transcription + extraction.
  Defense is hygiene (checking against existing issues) and board truth metrics.

---

## 5. Business Model

### 5.1 Pricing

| Tier | Price | Features |
|------|-------|----------|
| Free | $0 | 5 meetings/month, basic transcription, Trello only |
| Pro | $10/user/month | Unlimited meetings, all org tools, all sources, rules engine |
| Enterprise | Custom | SSO, audit log, dedicated support, "Runs on Atlassian" |

### 5.2 Unit economics

| Metric | Value |
|--------|-------|
| API cost per user/month | ~$1.83 (transcription + summarization + reasoning) |
| Gross margin | ~82% |
| Break-even | ~20 users |
| At 100 users | ~$817/month profit |
| At 1000 users | ~$8,170/month profit |

### 5.3 Cost structure

| Component | Cost/month (100 users) |
|-----------|----------------------|
| Hosting (Railway/Fly.io) | $10-20 |
| Database (Supabase/Neon) | $0-25 |
| Domain + SSL | $1-2 |
| Monitoring (Sentry) | $0 (free tier) |
| Email (Resend) | $0 (free tier) |
| API costs | $183 |
| **Total** | **~$195-230/month** |

### 5.4 Go-to-market

1. **Phase 1:** Forge app (Jira/Confluence/JSM) — Atlassian Marketplace
2. **Phase 2:** Trello Power-Up (separate platform)
3. **Phase 3:** Standalone SaaS (web app + API)
4. **Phase 4:** Enterprise (SSO, audit log, dedicated support)

### 5.5 Snotra as a module/add-on for other applications

Snotra is not just a standalone product. It's designed as a module that can be
embedded into other applications. Any app that has meetings, decisions, or action
items can benefit from Snotra's pipeline.

Integration patterns:
- Webhook trigger (meeting ends → Snotra processes → projects → routes)
- SDK import (from snotra import pipeline, project, route)
- REST API (POST /api/snotra/process)
- CLI (snotra process transcript.txt)

Business models: standalone SaaS ($10/user/month), embedded module (revenue share),
white-label ($5-8/user/month), API-only (per-meeting or per-seat).

This means Snotra can be an "add-on" for any app we build — CRM, helpdesk,
document management, calendar, chat. The meeting-to-action pipeline becomes a
feature, not a separate product.

---

## 6. Technical Architecture

### 6.1 Package structure

```
snotra/                          # standalone Python package
├── core/                        # record pipeline (transport-agnostic)
├── capture/                     # audio capture (browser, manual, pipewire)
├── transcribe/                  # transcription + summarization (online APIs)
├── store/                       # record storage (filesystem, S3, GCS)
├── adapters/                    # organization tool adapters (7)
├── ingest/                      # transcript ingestion (8 sources)
├── channels/                    # action routing (email, todo, calendar, chat, KB)
├── rules/                       # rules engine (inheritance)
├── router/                      # action router
├── config/                      # configuration (YAML + env vars)
├── cli/                         # command-line interface
└── api/                         # REST API (FastAPI)
```

### 6.2 Online model support

| Function | Local (Ymir) | Online (standalone) |
|----------|-------------|---------------------|
| Transcription | whisper.cpp (CUDA) | OpenAI Whisper, Google STT, Azure Speech |
| Summarization | llama-swap (local LLM) | OpenAI GPT-4o, Anthropic Claude, Google Gemini |
| Reasoning/Logic | llama-swap (local LLM) | OpenAI GPT-4o-mini, Anthropic Claude Haiku, Google Gemini Flash |
| Speaker diarization | None (manual) | AssemblyAI, Deepgram, or provider-native |

### 6.3 Configuration

```yaml
# snotra.yaml — standalone configuration
transcription:
  provider: openai
  model: whisper-1
  api_key: ${OPENAI_API_KEY}

summarization:
  provider: openai
  model: gpt-4o-mini
  api_key: ${OPENAI_API_KEY}

reasoning:
  provider: openai
  model: gpt-4o-mini
  api_key: ${OPENAI_API_KEY}
  enabled: true

organization:
  surface: trello
  board: "My Board"

rules:
  path: ./rules.yaml

routing:
  decision: [email, board]
  action: [email, todo, board]
```

### 6.4 Running on the user's own machine

Two deployment modes:

**Mode A: Local CLI (no server, no UI)**
```bash
pip install snotra
snotra transcribe meeting.wav --provider openai
snotra process transcript.txt --date 2026-10-31
snotra project ./meetings/2026-10-31-topic --surface trello
snotra route ./meetings/2026-10-31-topic --channels email,todo
```

**Mode B: Local web app (with UI)**
```bash
pip install snotra[web]
snotra serve --port 8080
```

Data sovereignty: audio, transcripts, records, rules, and speaker maps stay on the
user's machine. Only audio (to transcription API) and card data (to org tool API)
leave. No Snotra servers exist.

Offline mode: parse, extract, merge, validate, render all work offline. Transcribe,
summarize, project, route, ingest require network.

System requirements: Python 3.10+, 256MB RAM, 100MB disk + records.

Installation: `pip install snotra` (core), `pip install snotra[web]` (with UI),
`pip install snotra[all]` (with all adapters).

---

## 7. Production Readiness

### 7.1 What exists today (MVP)

All components compile and pass syntax checks. None tested against live APIs.
Adapters are functional stubs.

### 7.2 What needs to be built

- 25+ unit test files
- 5+ integration tests (live API)
- 3+ end-to-end tests
- Error handling and retry logic
- OAuth token auto-refresh
- API key encryption at rest
- PII redaction in logs
- CI/CD pipeline
- Documentation (getting started, API reference, troubleshooting)
- Packaging (pip + npm)
- Atlassian Marketplace review (10-15 business days)

### 7.3 Estimated effort

8-10 weeks total.

### 7.4 Testing priority

1. Trello adapter (reference implementation)
2. Rules engine (inheritance and overrides)
3. Action router (routing logic)
4. Knit ingestion (covers 6 tools)
5. Read AI + Fathom ingestion (most popular sources)
6. Jira adapter (production target — Forge)
7. Monday + Asana adapters (secondary)
8. Remaining adapters (ClickUp, Notion, Linear)
9. Channel adapters (email, todo, calendar, chat, KB)
10. End-to-end (full pipeline from audio to board)

---

## 8. Open Questions

1. **Python or TypeScript?** Core pipeline is Python. Should we also provide
   a TypeScript/Node.js version?
2. **Package registry:** PyPI, npm, or both?
3. **License:** MIT or Apache 2.0?
4. **Monetization:** Free OSS, freemium, or paid?
5. **Browser capture or manual upload?**
6. **Forge-first or standalone-first?** Reygan recommends Forge. We're following that.

---

## 9. Next Steps

1. **Immediate:** Test Trello adapter against a live Trello board (sandbox)
2. **Short-term (2-4 weeks):** Unit tests for all adapters, rules engine, action router
3. **Medium-term (4-8 weeks):** Integration tests, error handling, security, docs
4. **Long-term (8-12 weeks):** Packaging, Atlassian Marketplace review, launch
5. **Ongoing:** Identity matching table, board truth metrics dashboard, chat/KB channels

---

## Appendix A: Competitive Landscape

| Competitor | What they do | What they don't do |
|-----------|-------------|-------------------|
| Fireflies | Record, transcribe, extract actions, create tasks | No hygiene (duplicates), no board truth, no multi-channel routing |
| tl;dv | Record, transcribe, summarize, create tasks | Same gaps as Fireflies |
| Otter | Record, transcribe, summarize, action items | Same gaps |
| Atlassian Rovo + Loom | Transcript → status change on work items | No agenda logic, no drift detection, no review gate, no rules engine |
| Snotra | All of the above + hygiene + board truth + rules + multi-channel + AI for logic | (this is us) |

## Appendix B: Key Metrics to Track

| Metric | Target | Why |
|--------|--------|-----|
| Meetings processed/user/month | 15-20 | Core usage |
| Transcription accuracy | >95% | Trust |
| Action extraction precision | >90% | No false closures |
| Board truth (stale issues) | Decreasing | The differentiator |
| PM hours saved/user/month | >5 | The value prop |
| Churn rate | <5%/month | Product-market fit |
| NPS | >50 | Customer satisfaction |

---

## Appendix C: Cost Reference

### Transcription (per minute of audio)

| Provider | Model | Cost/min | Cost/hour |
|----------|-------|----------|-----------|
| OpenAI | Whisper-1 | $0.006 | $0.36 |
| OpenAI | gpt-4o-mini-transcribe | $0.003 | $0.18 |
| Google | Speech-to-Text Standard | $0.003 | $0.18 |
| AssemblyAI | Universal | $0.00025/s | $0.015/min |
| Deepgram | Nova-2 | $0.0043/min | $0.26/min |

### Summarization (per meeting, ~5000 input + ~1000 output tokens)

| Provider | Model | Cost/meeting |
|----------|-------|-------------|
| OpenAI | GPT-4o-mini | ~$0.0014 |
| Anthropic | Claude Haiku 4.5 | ~$0.0025 |
| Anthropic | Claude Sonnet 4.6 | ~$0.0300 |
| Google | Gemini 2.5 Flash | ~$0.0014 |

### Reasoning (per meeting, ~2000 input + ~500 output tokens)

| Provider | Model | Cost/meeting |
|----------|-------|-------------|
| OpenAI | GPT-4o-mini | ~$0.0008 |
| Anthropic | Claude Haiku 4.5 | ~$0.0013 |
| Google | Gemini 2.5 Flash | ~$0.0008 |

### Monthly cost estimate (per user, 20 meetings/month, avg 30 min)

| Component | Cost |
|-----------|------|
| Transcription | $1.80 |
| Summarization | $0.03 |
| Reasoning | $0.02-0.14 |
| Organization tool API | $0 |
| Transcript ingestion | $0 |
| **Total API cost per user/month** | **~$1.85-1.97** |

### Hosting (small SaaS, 100 users)

| Component | Cost/month |
|-----------|-----------|
| Hosting (Railway/Fly.io) | $10-20 |
| Database (Supabase/Neon) | $0-25 |
| Domain + SSL | $1-2 |
| API costs | $185-197 |
| **Total** | **~$197-244/month** |

### Monetization

At $10/user/month with ~$1.85-1.97/user/month API cost: ~80-82% gross margin.
Break-even at ~20 users. At 100 users: ~$803-815/month profit.
At 1000 users: ~$8,030-8,150/month profit.
EOF
echo "Written"
---

## 17. Snotra for Other AI Harnesses

### 17.1 What this is

Snotra is designed as a **library + API first, product second**. Any AI harness
that can call a CLI, import a Python module, make HTTP requests, or use MCP
(Model Context Protocol) can use Snotra.

### 17.2 Integration patterns by harness

| Harness | Integration method | How it works |
|---------|-------------------|-------------|
| Pi (current) | CLI + Python SDK + skill | Pi calls snotra-* scripts, imports reasoning_adapter, uses the skill |
| Claude Code | MCP server + CLI | Connects to Snotra's MCP server or shells out to CLI |
| Cursor | MCP server + CLI | Connects to Snotra's MCP server or shells out to CLI |
| Codex | CLI + Python SDK | Shells out to CLI or imports the Python package |
| OpenCode | MCP server + CLI | Connects to Snotra's MCP server or shells out to CLI |
| Any HTTP client | REST API | POST /api/snotra/process, GET /api/snotra/meeting/{id} |
| Any Python app | Python SDK | from snotra import pipeline, project, route |
| Any shell script | CLI | snotra process transcript.txt --date 2026-10-31 |

### 17.3 MCP server (universal integration)

The MCP server is the universal integration point. Any MCP-compatible harness can
connect to Snotra's MCP server and use its tools: snotra_process, snotra_transcribe,
snotra_project, snotra_route, snotra_agenda, snotra_rules, snotra_ingest, snotra_status.

### 17.4 Key principle: one core, many faces

Snotra's core (pipeline, adapters, rules, routing) is pure Python. The faces (CLI,
MCP, REST API, Python SDK) are thin wrappers. A new harness integration only
requires a new face, not a new core. No duplicate implementations.

**2026-11-03 (correction, appended):** the operator's name was redacted — it is personal data and belongs in the home, not in a public repository (RULES/04, RULES/06).
