Reygan,

Following up on your strategic feedback and the record corrections. We've been
working on the next phase of Snotra and wanted to share where we're heading.

I've attached a comprehensive business launch document (Snotra — Business Launch
Document) that covers the full product, competitive positioning, business model,
technical architecture, production readiness, and open questions.

## Key points

1. Snotra as a standalone module — extracting from Ymir into a reusable
   library (Python package + optional web UI) with online model APIs (OpenAI,
   Anthropic, Google, Azure) instead of local infrastructure.

2. Hygiene-out, not funnel-in — no new issues without a receipt against
   existing ones. Board truth metrics (stale, ownerless, duplicates, decisions
   without follow-up, PM hours saved) are the differentiator.

3. Forge-first scope — Jira/Confluence/JSM first, per your recommendation.
   Trello and others are secondary adapters.

4. Never auto-close — transcript evidence + human confirmation required.

5. Identity matching — speaker-to-user mapping table per customer.

6. AI models — Snotra needs three AI models: transcription (speech to text),
   summarization (transcript to structured minutes), and reasoning (extraction,
   classification, dedup, suggested steps, identity matching). Extraction and
   mining have a deterministic baseline (no AI). The reasoning model is optional
   and improves quality but is never the authority. Users configure their own API
   keys through env vars, config file, or web UI. All keys stored encrypted at
   rest.

7. Model connection — users select provider, enter API key, test connection,
   select model. Supports fallback if primary provider is down.

8. Costs — ~$1.85-1.97/user/month in API costs (transcription + summarization
   + reasoning). ~80-82% gross margin at $10/user/month. Break-even at ~20 users.

9. Production readiness — 8-10 weeks estimated. Testing, error handling,
   security, docs, CI/CD, monitoring, packaging, Atlassian review.

## Snotra as a module/add-on for other applications

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

## What Snotra does that we haven't covered yet

- Live tail / real-time transcription
- Audio ladder / retention (Opus compression, 24-day retention)
- Letter system (per-person emails, follow-up emails, agenda drafts)
- Store contract enforcement (append-only, no overwrite)
- Provenance enforcement (record-key on every card)
- Sign-off flow (grade-based confirmation)
- Friday Synch and Monthly Grooming automation

Build order: provenance (1 day) → store contract (1 day) → audio ladder (1 day) →
letter system (2-3 days) → live tail (2-3 days). Total: 7-9 days.

## Snotra for other AI harnesses

Snotra is designed as a library + API first. Any AI harness (Claude Code, Cursor,
Codex, OpenCode, Pi) can use it via MCP server, CLI, Python SDK, or REST API.
One core, many faces — no duplicate implementations.

## Open questions for you

1. Does the "hygiene-out" positioning resonate with how you'd describe it to
   the Synteon team?
2. Are there specific board truth metrics you'd want to see that we haven't
   listed?
3. For the identity matching — would you prefer a manual mapping table or
   automatic speaker-to-user resolution?
4. Forge-first or standalone-first? You recommended Forge. We're following that.
5. Does the module/add-on model make sense for Synteon's roadmap?

Looking forward to your thoughts.

— <the operator>

**2026-11-03 (correction, appended):** the operator's name was redacted — it is personal data and belongs in the home, not in a public repository (RULES/04, RULES/06).
