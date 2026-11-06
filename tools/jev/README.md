# jev — the decision client, vendored, with one local provider

Upstream: **`github.com/zerwiz/pi-durable-news-agent`** → `apps/shared/packages/jev`
(at `273b79bb8d3d8907cae9fbd6abd3da163ee2a343`), **MIT** — see `LICENSE`.

Jev is a *decision* client: it sends a `state` and typed `questions` (noul ·
choice · score) and gets back one typed answer per question. No tokens are
generated, so a decision is one forward pass.

**Nothing here was rewritten.** The package is copied whole — `types`,
`helpers`, `client`, `mock`, `command`, `policy`, `ledger` — plus the six
`prompt_engineering/jev/*/command.json` commands it loads. Two changes only:

1. **One provider added: `local`.** `JevProvider` gains `"local"`, whose endpoint
   is `POST /v1/systemone` on this seat's llama.cpp rail. The default model is the
   rail alias `julia-1@q8_0`. The endpoint resolves from `JEV_LOCAL_URL` (default
   `http://127.0.0.1:8080/v1/systemone`), so every seat names its own door rather
   than assuming one machine. Its key is `JEV_LOCAL_API_KEY`, and it is
   **optional** — a loopback rail may be open, a rail behind `--api-key` is not.
2. `tests/command.test.ts` points at the commands vendored here
   (`../prompt_engineering/jev`) instead of the app's own path.

`hfs` keeps the upstream vocabulary **verbatim**: `hype` · `facts` · `signal`, four
score levels each, `label_threshold: 50`, `tie_order: [signal, facts, hype]`.

## Use it

```bash
node --test tests/*.test.ts        # 18 offline tests, no key, mock only

# measure a rail that serves a native decision GGUF
export JEV_LOCAL_API_KEY="$(python3 -c "import json;print(json.load(open('$HOME/.pi/agent/auth.json'))['llama-swap']['key'])")"
node bench/decision-bench.ts --out /tmp/jev-proof.json
```

`bench/decision-bench.ts` prints the door proof (one `choice` question whose
options carry **descriptions** — bare labels mis-route) and decisions per second
at 3 and 12 options, then runs the real `hfs` command and ranks it.

## What it needs on the rail

A llama.cpp build with `/v1/systemone` (upstream `tools/server/server-decision.cpp`)
and a **native decision GGUF** — one whose metadata carries
`<arch>.decision.type` and `tokenizer.chat_template.systemone`. A language model
does not qualify, however well it classifies: the server answers `501` for it.
