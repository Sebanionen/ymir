# Hvergelmir — the well every stream runs into

**Figure:** Hvergelmir, the roaring cauldron in Niflheim from which every river in the world takes its water. A well at the
top of the world, fed by many streams, into which the world's noise falls and out of which only what is worth carrying runs.

**What it is.** A **proactive news agent**: a cron tick wakes a durable agent, sweeps a set of sources (feeds, Hacker News,
release notes, benchmark blogs), lets a **decision model** throw out what is off-topic or not worth the operator's attention,
folds repeat coverage into one story, ranks what remains, and renders the survivors as **cards** in a fixed catalogue. It does
not wait to be asked. It works, then waits, then works again.

**Where it comes from.** It is vendored from our own repository `zerwiz/pi-durable-news-agent`
(`https://github.com/zerwiz/pi-durable-news-agent`), **MIT, Copyright (c) 2026 IndyDevDan** — the licence is kept at
[`LICENSE`](./LICENSE), the upstream README at [`UPSTREAM.md`](./UPSTREAM.md). Vendored, not rewritten: the smithy audit's own
warning is that absorbing an upstream app is drift, so the app lives here whole and Ymir reaches it as a door.

```
what_runs[4]{part,what,where}:
  "the durable agent + the tick","a checkpointed agent that resumes and never pays twice for finished work","`apps/dna-server-cron`"
  "the API","the served surface the clients read","`apps/dna-server-api`"
  "the clients","a browser UI with a fixed card catalogue, a TUI, and a CLI","`apps/dna-client-browser` · `-tui` · `apps/dna-cli`"
  "the jev client","`systemOne(state, questions)` + the hype · facts · signal policy + a call ledger (MIT, framework-free)","`apps/shared/packages/jev` — THE part Ymir itself reuses"
```

## Why it wears this name

The naming law asks for the figure whose role matches the work, and for an application that is a **place**, not a person
(Hlidskjalf, Óðrerir, Sessrúmnir, Smíðja). Hvergelmir is the place where many streams meet and from which the rivers leave —
which is exactly the shape of this app: **many sources in, one pool, and only the carrying water out.** The sorting itself is
the well's own work: hype, facts and signal, taken straight from the decision model.

## Running it

```bash
cd apps/hvergelmir
just install                 # npm install for every workspace
cp .env.example .env         # then add the keys it asks for
just combos dev              # free and offline: faux model, fixture news, UI on :4851
```

**The keys are the operator's, by reference** (Rule 24): the app reads them from its own `.env`, and Ymir never stores a value
in the tree. The hosted decision backends (`api.typesafe.ai`, OpenRouter) are for a demo; **house data goes to the local
provider** — the `local` backend pointed at our rail (`/v1/systemone`) with a model that is already on the shelf.

## How Ymir uses it

- **The `jev` package is shared, not duplicated.** Ymir's own decision doors (intake triage, path ranking, review gating —
  plan 200 §13–§14) should vendor `apps/shared/packages/jev` and add the `local` provider rather than write a second client.
- **The cards are a language, not a screen.** The five card shapes (thread-pulse, signal-alert, release, quote, hype-watch) are
  the anatomy Ymir's near-loop page re-implements in React — Odrerir is React 19, this app is Vue 3.5, so the **design**
  merges and the **components** do not.
- **One clock per concern.** This app's cron tick is the *news* clock. The seat's arm is the *seat* clock. Two clocks on one
  schedule is the failure RULES/25 names.
- **Its output lands in one list.** A story worth acting on becomes an item the operator already reads, not a second inbox.

## The rule it carries into the tree

**A proactive agent earns its keep by what it discards.** The valuable half of this app is not the sweep; it is the decision
that throws most of it away, with a probability attached, and a checkpoint so a restart does not pay twice.

## CHANGE LOG

- **2026-11-05** — vendored from `zerwiz/pi-durable-news-agent` (MIT) at the Allfather's word — *"make it to a separate app to
  ymir also … name it by the naming law … put it in the apps folder"* — under the name **Hvergelmir**, with the upstream
  README kept as `UPSTREAM.md` and the licence kept in place.
