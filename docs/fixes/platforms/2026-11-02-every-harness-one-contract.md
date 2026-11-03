# Every harness, one contract — the rule Pi's extension law did not have

**Date:** 2026-11-02 · **Component:** platforms / harness integration · **At the Allfather's word:** *"opencodes
packets need to have the same functionality as the extentions for pi … we need make more harnesses like claude and
codex and others in the future … installed in root for the harnesses and the agents.md that the tools are reading
needs to be updated on ymir installts and updates."*

## What was wrong

RULES/13 governs **the extension surface of one harness**. There was no law for **the harness surface of the
house**, so the tree grew Pi-shaped by default: Pi is named in 329 runtime files against 66 for OpenCode, 52 for
Claude, 48 for Cursor and 38 for Codex; twelve Pi extensions ship and no OpenCode plugin carries the same surface;
and the install writes into a checkout rather than into the user's own harness directories.

The audit behind this (`hodd/docs/audits/2026-11-02-harness-and-os-support-audit.md`) also measured the logging,
from each vendor's own documents: **five harnesses, three incompatible storage shapes** — Pi's JSONL tree, Claude's
and Codex's flat JSONL, OpenCode v2's and Cursor's SQLite — with shell hooks (Claude), JS hooks with a trust flow
(Codex), TypeScript extension events (Pi), and a plugin event API (OpenCode). Only Claude Code documents OTEL, so a
vendor's telemetry can never be the house's record.

## What changed

RULES/13 gains a dated appended section and six laws: one contract many harnesses; the transcript is normalised;
parity is named not assumed (`full · partial · absent` with a reason); **global install, not a checkout** — the
extensions and the instruction file each tool actually reads, written into the user's own home on install and
re-verified on update; no vendor-telemetry dependency; and a harness change updates the matrix in the same commit.

Plan 161 carries the repair in seven phases: descriptor per harness, one normalizer every reader parses, capability
parity (a Pi extension → an OpenCode plugin → a Claude hook → a Codex hook), the global install kept true by Gróa,
Hlidskjalf and the Sága digest naming the harness, Runes from the normalised stream, and a one-change checklist for
the next harness.

## Why detection was never the problem

`bin/backend/fm-harness.sh` already identifies nine harnesses — claude · codex · opencode · grok · kimi · muse · pi ·
pi-signed · cursor — by ancestry and hook markers. The gap starts one layer later, where a door asks "which session
file is this?" and only one answer is implemented.
