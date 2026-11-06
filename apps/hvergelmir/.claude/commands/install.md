---
description: Install the Pi Durable News Agent: Node 24, just, workspaces, keys, bearer tokens, and the free test suites
---

# Install Pi Durable News Agent

## Purpose

Set up the Pi Durable News Agent monorepo for development on this machine. Checks the toolchain, installs every npm workspace, confirms the provider keys are set without showing them, writes the client and cron bearer tokens, and proves the build with the free unit and faux suites. This is an interactive, agentic process: ask the user when a choice is needed.

## Variables

SOURCE_REPO: the directory this command runs from (the repo root, where `justfile` and `package.json` live)
ENV_FILE: `SOURCE_REPO/.env` (template: `.env.example`)
NETWORK_FILE: `SOURCE_REPO/dna-network.yaml` (template: `dna-network.example.yaml`, gitignored, only needed for devices)
REQUIRED_KEYS: `OPENROUTER_API_KEY`
OPTIONAL_KEYS: `OPENAI_API_KEY` (card images when a source has none), `FIRECRAWL_API_KEY` (better deep research and hyper_fetch, and sweep search with `DNA_SEARCH_MODE=firecrawl`; free engines cover all of it without a key), `TYPESAFE_API_KEY` (direct jev)
TOKEN_KEYS: `DNA_CLIENT_TOKEN`, `DNA_CRON_TOKEN`

## Codebase Structure

```
package.json             # the npm workspace root (node_modules sits next to it)
shared-app-configuration # tsconfig.base.json and the formatter config every app shares
apps/                    # the applications
apps/dna-server-api      # the API, agents, tools, sweep task (port 4850), prompt_engineering/, config/
apps/dna-server-cron     # the 1 minute tick and crontab line
apps/dna-cli             # the dna command and device drivers
apps/dna-client-browser  # hub (port 4851) and Vue app
apps/dna-client-tui      # pi-tui client
apps/shared/packages     # dna-sdk, durable-agent, jev foundations
apps/shared/tests        # live device checks and the docs check
```

## Instructions

- Run every check via Bash. Do not assume anything is installed.
- Show a status line right after each check: `pass` or `FAIL` plus one short reason.
- Install what can be installed without asking (npm workspaces, tokens). Ask before anything that changes the user's machine outside this repo.
- Never read, print or echo the value of any key or token. Check presence only, for example with `grep -c '^OPENROUTER_API_KEY=.' .env`.
- Never start the API, the hub, cron or any long running process. The faux suite boots temporary servers inside its tests and stops them; that is fine.
- Stop and guide the user when Node 24 or `just` is missing, because nothing else works without them.
- Do not install the crontab. That is a separate, explicit step (`just combos local`, or `just cron install`).

## Workflow

### Step 1: Check Prerequisites

Gate on these:

1. `command -v node && node -v`: the major version must be 24 or newer. If missing or older, guide the user: install nvm (https://github.com/nvm-sh/nvm), then `nvm install 24 && nvm use 24`. Stop until it passes.
2. `command -v npm`: ships with Node.
3. `command -v just`: install with `brew install just` (macOS) or see https://github.com/casey/just. Stop until it passes.

Then check these and report, without stopping:

4. `command -v tmux`: only for the TUI smoke (`brew install tmux`).
5. Google Chrome: `test -d "/Applications/Google Chrome.app"` on macOS, or `command -v google-chrome`. Only for the Playwright UI suite (https://www.google.com/chrome).
6. `command -v ssh` and `command -v rsync`: only for remote devices (an always-on Mac mini, a Linux box or an exe.dev VM, `just net up <device>`).
7. `command -v crontab`: only for the every minute tick on this machine (`just combos local`).

### Step 2: Check Environment

1. If `.env` is missing, copy it: `cp .env.example .env`, and tell the user to add their keys.
2. For each key in REQUIRED_KEYS and OPTIONAL_KEYS, check presence with `grep -c '^<KEY>=.' .env`. Report `set` or `missing` only.
3. If `OPENROUTER_API_KEY` is missing, say the live API cannot run yet, the free faux mode still works, and where to get a key (https://openrouter.ai/keys). Ask the user whether to continue with faux only (default yes).
4. If `OPENAI_API_KEY` is missing, note that cards without a source image show no image (https://platform.openai.com/api-keys). Search is free by default (Bing News, then Google News, beside Hacker News; deep research adds Bing web and DuckDuckGo), so a missing `FIRECRAWL_API_KEY` needs no action (https://firecrawl.dev if they want it).

### Step 3: Install Dependencies

1. `just install` (runs `npm install --no-audit --no-fund` at the repo root, the workspace root).
2. `just api tokens`: writes `DNA_CLIENT_TOKEN` and `DNA_CRON_TOKEN` into `.env` when missing, short or equal. It prints key names only.
3. Confirm both tokens are present with `grep -c '^DNA_CLIENT_TOKEN=dna_' .env` and `grep -c '^DNA_CRON_TOKEN=dna_' .env`.

### Step 4: Verify Configuration

1. The prompts exist: `ls apps/dna-server-api/prompt_engineering/agents/news-desk apps/dna-server-api/prompt_engineering/agents/news-researcher apps/dna-server-api/prompt_engineering/agents/deep-research` shows `SYSTEM_PROMPT.md` and the `USER_PROMPT_*.md` files in each.
2. The jev commands exist: `ls apps/dna-server-api/prompt_engineering/jev` shows `relevance`, `worth-attention`, `importance`, `hfs`, `same-story` and `claim-support`.
3. The defaults exist: `ls apps/dna-server-api/config/sources.json apps/dna-server-api/config/keywords.json`.
4. Devices are optional. Without `dna-network.yaml` only `local` (this Mac) exists. If the user wants an always-on Mac mini, a Linux box or an exe.dev VM, `cp dna-network.example.yaml dna-network.yaml`, uncomment the matching example and ask them to fill in the ssh target.

### Step 5: Verify Readiness

1. `just test unit`: types, lint, format and unit tests (free, offline).
2. `just test faux`: the faux sweep, crash recovery, auth scopes, workflow, stream and executions suites (free, offline).
3. If Chrome is present, offer `just test ui` (builds the browser app, then runs Playwright against a faux API). Ask first, default yes.
4. If `OPENROUTER_API_KEY` is set, offer `just test jev-live` (real jev on three fixture items, a fraction of a cent). Ask first, default no.

### Step 6: Report

Print a status table with one row per check: prerequisites, keys (set or missing, never values), tokens, install, configuration, unit suite, faux suite, and the optional UI suite. Then the count of passing checks.

Next steps, as commands the user can paste:

```bash
just combos dev            # free and offline: faux API plus the UI at http://localhost:4851
just api run               # the live API on :4850 (needs OPENROUTER_API_KEY)
just cron tick             # one live sweep now
just browser start         # the built UI at http://localhost:4851
just tui attach            # the terminal client
just combos local          # always on, this Mac: API, UI and the every minute tick (stop: just net down local)
just net up mini           # bring a Mac mini (or any device in dna-network.yaml) online
just cli run doctor        # keys, API, scopes, cron and each search engine's health
```
