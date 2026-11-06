---
description: Load context for the Pi Durable News Agent monorepo (apps, foundation packages, prompts, search, devices)
---

# Purpose

Understand the Pi Durable News Agent: a proactive pi-durable agent that a cron tick wakes to sweep news, ranks every item as Hype, Facts and Signal with jev, and serves the cards to a browser, a TUI and a CLI from one API on this Mac, an always-on Mac mini or a VM.

## Workflow

1. Run `git ls-files` to see the tree: `apps/*` (dna-server-api, dna-server-cron, dna-client-browser, dna-client-tui, dna-cli), `apps/shared/packages/*` (dna-sdk, durable-agent, jev), `apps/dna-server-api/prompt_engineering/`, `apps/dna-server-api/config/`, `apps/shared/tests/`, `just/`.
2. Read `README.md`, `justfile`, `package.json` (the workspace root) and `.env.example`.
3. Read the foundation packages: `apps/shared/packages/durable-agent/src/index.ts`, `apps/shared/packages/jev/src/index.ts`, `apps/shared/packages/dna-sdk/src/index.ts`, plus their READMEs.
4. Read the API wiring: `apps/dna-server-api/src/main.ts`, `apps/dna-server-api/src/app.ts`, `apps/dna-server-api/src/runtime.ts`, `apps/shared/packages/dna-sdk/src/routes.ts`, `apps/shared/packages/dna-sdk/src/capabilities.ts`, `apps/dna-server-api/src/agents/index.ts`, `apps/dna-server-api/src/news/sweep.ts` and `apps/dna-server-api/src/news/sweep-task.ts`.
5. Read the search chain: `apps/dna-server-api/src/news/search/index.ts` and `apps/dna-server-api/src/news/search/web.ts` (Firecrawl with a key, then Bing News, Google News, Hacker News and the cache; Bing web and DuckDuckGo for deep search).
6. List `apps/dna-server-api/prompt_engineering/agents/*`, `apps/dna-server-api/prompt_engineering/jev/*` and `apps/dna-server-api/src/agents/tools/*` to see every agent prompt, jev command and tool. Skim `apps/dna-server-api/src/db/migrations/001_schema.sql` for the data model.
7. Skim the clients: `apps/dna-client-browser/fe/src/App.vue`, `apps/dna-client-browser/hub/src/main.ts`, `apps/dna-client-tui/src/app.ts`, `apps/dna-cli/src/main.ts`.
8. Read `dna-network.example.yaml`, `just/net/mod.just`, `just/combos/mod.just`, `apps/dna-cli/src/net/local.ts`, `apps/dna-cli/src/net/remote.ts` and `apps/shared/tests/live/e2e.mjs` for the device modes (local Mac, ssh Mac mini or Linux box, exe.dev VM) and the live checks.
9. Summarize your understanding of the project: purpose, stack, structure, key files, and entry points.
