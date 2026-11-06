# jev — vendored, not written

This directory is a **vendor copy** of two modules of `jev`, the HFS classifier from
[`zerwiz/pi-durable-news-agent`](https://github.com/zerwiz/pi-durable-news-agent)
(MIT, Copyright (c) 2026 IndyDevDan — `./LICENSE`, carried unchanged).

| | |
|---|---|
| upstream | `apps/shared/packages/jev/` |
| commit | `273b79bb8d3d8907cae9fbd6abd3da163ee2a343` |
| vendored | 2026-11-06 |
| taken | `src/types.ts` · `src/policy.ts` |
| left behind | `client.ts` · `command.ts` · `ledger.ts` · `mock.ts` · `index.ts` |

**Why only two.** `types.ts` and `policy.ts` are the **HFS vocabulary and its policy** —
the three categories, `rankHfs`, the label threshold, `suspectCombo`, `attentionScore`
and the confidence `gate`. That is what the near-loop cards need in order to speak a
vocabulary that already exists instead of inventing one.

The rest of the package is deliberately absent, and each for a reason:

- `client.ts` — POSTs to a hosted classifier API. A browser card must not carry a key,
  and no seat may reach a model by a door it did not name.
- `ledger.ts` — reads the filesystem (`node:fs`); this app runs in a browser.
- `command.ts` — the CLI door, which this app does not have.
- `mock.ts` — a test double. **No mock ships in the running hall.**

**Do not edit these files.** They are upstream's, and a local edit is a fork pretending
to be a vendor copy. If the vocabulary must change, change it upstream and re-vendor
with a new dated line in the table above. If a card needs behaviour these two modules do
not have, that behaviour belongs in `apps/odrerir/src/components/CardView.tsx`, not here.

## CHANGE LOG

- **2026-11-06** — changelog section added at the merge so RULES/46 can read it.
