## model · 2026-11-06 — the first decision model on the rail: Julia-1 answers `/v1/systemone`

Component: `~/.config/llama-rail/models.ini` (one preset), `tools/jev/**` (new),
`~/.agents/skills/modeltesting/{backends-benchmark.md,llamacpp/TESTING.md,hosts/heimdall.md,ledger.jsonl}`.
Machine: the CUDA build b11719 in `~/CodeP/llama.cpp.jev/build-cuda` (outside every repo).

### Why

The Allfather's Jev family — six native **decision** GGUFs, 47 GB, at `~/Models/jev/` —
was on this box and served by nothing. `POST /v1/systemone` answered **404 for every
model id**, and the assumed cause ("no preset") was wrong.

### What was wrong — the route was absent from the binary, not the preset

`404 {"error":{"message":"File Not Found","type":"not_found_error"}}` is the generic
missing-route body. It answers 404 for a **registered chat model** too, which is the
tell: on a build with no `tools/server/server-decision.cpp` there is no route, and so
no `501 "not a decision model"` either. Three binaries were measured:

| binary | `/v1/systemone` | loads Julia-1 | loads Kev-4B |
|---|---|---|---|
| `/usr/local/bin/llama-server` 0.4.1-dev (73c941b, 2026-09-22) — the trunk | **404** | — | — |
| Arch `llama-cpp 0.6.0` | present | ❌ `unknown pre-tokenizer type: 'mmbert'` | ❌ `expected 428 tensors, got 426` |
| **b11719 (5eacac37)** CUDA sm_86 | ✅ | ✅ | ✅ |

### The fix

1. **One preset, no other preset touched** — `[julia-1@q8_0]` in the rail INI, on the
   `[*]` global (reasoning off, flash-attn, jinja, parallel 1), `ctx-size = 4096`
   because the head reads at most `decision.max_head_tokens` (256) and the prompt is
   evaluated in one batch. The weights are seated on the shelf convention
   (`llama-swap-models/julia-1-q8_0/model.gguf → ~/Models/jev/Julia-1/…`). Julia-1 is
   the smallest of the family (144M, Q8_0, 168 MB) and **Apache 2.0**.
2. **The client was vendored, not rewritten** — `tools/jev/` is upstream
   `@dna/jev` (github.com/zerwiz/pi-durable-news-agent @ `273b79bb`, MIT, `LICENSE`
   carried) copied whole, with **one added provider**: `local → POST /v1/systemone`,
   endpoint from `JEV_LOCAL_URL` (default loopback), key `JEV_LOCAL_API_KEY` and
   optional, default model the rail alias `julia-1@q8_0`. Its 18 offline tests pass
   unchanged. The `hype` · `facts` · `signal` vocabulary is verbatim.
3. **A build that carries both halves** — b11719 with CUDA, kept outside every repo.

### Proof — the door, and the counter-probe that justifies descriptions

```
state    "Customer message: I was charged twice for my order last week and nobody has replied."
question "Which team should handle this customer message?"   choice{billing,shipping,technical}
```

- options **with descriptions** → `choice: "billing"`, `p 0.9995`, `confidence 0.9992`, 76 input tokens
- options as **bare labels** → `choice: "shipping"`, `p 0.8944`, `confidence 0.8415`, 38 input tokens

Same model, same state, same question; only the criteria changed. A `choice` whose
options are `null` is not a cheaper request, it is a different and wrong one.

The router advertises the capability without loading the model:
`GET /v1/models` → `"output_modalities":["decisions"]`, `context_length` 8192, `source: "preset"`.

### Decisions per second — the loop question

Throwaway `llama-server` on `:9099`, direct model, `/props`-verified `n_ctx 4096`, card
baseline 55 MiB, resident 370 MiB, 5 warmups discarded, 5 runs × 100 timed decisions:

| options | decisions/s (median) | range | mean | p95 | input tokens |
|---|---|---|---|---|---|
| 3 | **84.0** | 77.1 – 88.0 | 11.9 ms | 13.4 – 15.5 ms | 76 |
| 12 | **67.4** | 65.1 – 72.8 | 14.8 ms | 15.5 – 20.6 ms | 155 |

Tripling the options costs 20% of throughput and 4 tokens per option. **Triage can
sit in a loop**: ~240k–300k items an hour on one card, serially.

### And the honest limit — 144M routes, it does not judge

The upstream `hfs` command was run on two fixtures: Julia-1 ranks the hyped item
correctly (`hype 68`) but scores a **changelog as 72 hype** — a false positive that
would flag every release note. `kev-4b@q8_0` (4.2B, 7,761 MiB) separates them cleanly
(`hype 75 / facts 7` versus `facts 81 / hype 13`) at **9.97 decisions/s (3 options) and
4.79 (12 options)**. So: **Julia-1 for bucket routing, Kev-4B for rubric judging.**

**OpenJev is CC BY-NC** — it is mentioned in the bench records and must **never** be
wired into anything commercial-facing. It was not seated, not benchmarked, and is not
in any preset.

### What remains

- **The trunk rail still runs 0.4.1-dev.** The preset is in the INI and
  `GET /v1/models?reload=1` lists it (39 presets), but `:8080/v1/systemone` answers 404
  until `llama-swap.service` executes the b11719 binary — a **root step**
  (`/tmp/jev-rail-install.sh`: install the binary beside its `.so`, one drop-in,
  `systemctl restart`). The trunk binary is left untouched, so the drop-in is the
  rollback edge. **Owed: one command from the Allfather's hand.**
- **`RULES/ai-models.md` §5 owes a third floor exception.** Rule 12's 60,000-token
  floor is a *chat window* rule; a decision model's whole prompt is one batch
  (4,096 here), so both ledger lines were written under `floor_exception:
  "capability-probe"` with that reasoning in the note. The law should name
  `decision-model` rather than borrow a probe's exception.
- `.pi/agent/models.json` was **deliberately not** given the alias: Julia-1 reports
  `output_modalities: ["decisions"]` only and cannot drive a chat turn. An alias in
  the chat catalog would be a promise the model cannot keep.

### Files

```
tools/jev/{README.md,LICENSE,package.json,tsconfig.json}
tools/jev/src/{index,types,helpers,client,mock,command,policy,ledger}.ts   (client.ts: +1 provider)
tools/jev/tests/{client,policy,command}.test.ts                            (18/18 pass)
tools/jev/prompt_engineering/jev/{hfs,relevance,importance,same-story,worth-attention,claim-support}/command.json
tools/jev/bench/decision-bench.ts
tools/jev/bench/results/2026-11-06-heimdall-{julia-1,kev-4b}.json
docs/fixes/model/2026-11-06-the-first-decision-model-on-the-rail.md        (this note)

~/.config/llama-rail/models.ini            + [julia-1@q8_0] (one preset; backup models.ini.bak-pre-jev-2026-11-06)
~/.agents/skills/modeltesting/backends-benchmark.md        §10.5.19
~/.agents/skills/modeltesting/llamacpp/TESTING.md          §19.11
~/.agents/skills/modeltesting/hosts/heimdall.md            2026-11-06 section
~/.agents/skills/modeltesting/ledger.jsonl                 heimdall/julia-1@q8_0, heimdall/kev-4b@q8_0
```

## CHANGE LOG

- **2026-11-06** — changelog section added at the merge so RULES/46 can read it.
