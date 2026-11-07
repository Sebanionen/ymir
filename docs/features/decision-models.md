# Decision models — asking a model for a verdict, not a paragraph

## What it is

A **decision model** answers a shaped question with a probability per option, in one forward pass: `choice`, `score`, or
`noul` (yes/no). It does not generate prose. That makes it cheap enough to sit inside a loop — intake triage, routing, review
gating — where a chat model would be waste.

Two doors:

```
bin/model/jev-doors.sh list|url|ask      # where the models answer, and one raw call
bin/notify/intake-gate.sh                # the first gate: signal · facts · hype
```

## What you need

- A decision GGUF on the shelf — this box holds Julia-1, Laya, Kev-4B, lev, Clef, OpenJev under `~/Models/jev/`.
- A `llama-server` build that **carries `/v1/systemone`** (llama.cpp PR #29818). The rail's own build predates it, so the
  decision doors run a separate newer engine.
- The vault key `LLAMA_SWAP_API_KEY` — the same bearer the rail uses.

## The commands

```bash
# what is up, on which port, with which licence
bin/model/jev-doors.sh list

# the base URL for one door
bin/model/jev-doors.sh url jev-kev-4b        # -> https://<your-host>:8098/v1/systemone

# one verdict: is this message signal, facts or hype?
echo "the well bridge is down on :4602 — restart it" | bin/notify/intake-gate.sh
```

## Limits — measured on this box, not guessed

- **Examples beat criteria.** With six balanced examples in the state, Kev-4B was right on 8 of 8 real messages; with
  hand-written criteria and no examples, 1 of 3. Julia-1 (144M) scores 2 of 8 on the same set.
- **Balance the examples.** Two extra `facts` examples flipped the model to over-predict `facts` (4 of 8).
- **Below 0.70 is advisory.** The gate says so itself; nothing acts on a verdict below the cut-off.
- **Licence matters.** OpenJev is CC BY-NC and must never serve a commercial call; Clef is the Apache 27B.
- **Latency here:** 24 ms (Julia-1) · 28 ms (Laya) · 59 ms (Kev-4B) · 129 ms (lev) per call, GPU, `-c 8192`.
- **Context owns the card.** The model metadata asks for 262,144 and the server honours it — 13 GiB of cache for a 144M
  model. `-c 8192` is what makes four doors fit in 16 GiB.

## If it does not work

`501 This model is not a decision model` — the GGUF lacks the `.decision.*` metadata; only native decision models work.
`404` — the server build has no `/v1/systemone`; check the engine, not the model.
`401` — the bearer key is missing or wrong.
Wrong verdicts at high confidence — check the examples in the state before blaming the model.

## CHANGE LOG

- **2026-11-06** — written (Hœnir) after four measurement rounds: doors on the tailnet, latency per door, and the few-shot
  finding that changed the defaults.
