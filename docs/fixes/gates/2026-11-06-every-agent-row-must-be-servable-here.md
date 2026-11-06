# Every agent row must name a model THIS machine can serve

**Date:** 2026-11-06 · **Plan:** 203 §18 (the ninth gap) · **Law:** `RULES/07-config.md`, `RULES/25`

## What was wrong

`config/agents.yaml` named `llama-swap/qwen3.6-35b-a3b@q4_k_xl-mtp` for **eleven** agent rows, and
`bin/model/catalog.sh --has` says that id is not in this machine's catalogue. Every agent falling
through to its default died at model resolution — invisibly, because a house-split refusal failed first
and took the blame. The same fault was live on the heart at the same hour, with a different right
answer: its catalogue holds `llamacpp-heimdall/qwen3.6-35b-a3b@iq3_s`, which this machine does not.

So the durable lesson is not an id. **The id is per seat; the fault was shared.** An agent row may name
a model that exists in a catalogue somewhere else, and nothing in the tree noticed.

## What was built

`bin/gates/guards/model-rows-guard.sh` — every `model:` value in `$YMIR_HOME/config/agents.yaml`
(resolved through `bin/vault/hoard-lib.sh`, never guessed), judged against **this** machine's catalogue.

- **One call, not one per row** — the catalogue is read once and compared as a set, so 10 rows cost one
  `pi --list-models`, not ten.
- It reads both shapes the file uses — `{ model: id }` and `{ model: "id", primary: true }` — and it
  refuses a value that is not `provider/model` at all, because a harness cannot resolve a bare name.
- It **never judges the choice**, only servability. A ward with opinions about taste is a ward that
  gets switched off.
- It **skips cleanly and says why** (RULES/25): no home, no agent file, no catalogue door, or a rail
  that returned nothing — never a silent pass.

Wired into `bin/gates/guards.sh`, so the pre-push hook and both CI hosts run it.

## How it was proved

```
# this machine, after the eleven rows were fixed
$ bin/gates/guards/model-rows-guard.sh check
model-rows-guard[1]{gate,result,rows}:
  "model rows","ok","10"                      → exit 0

# a throwaway home naming a model nobody serves
$ YMIR_HOME=$T bin/gates/guards/model-rows-guard.sh check
model-rows-guard[1]{agent,model,finding}:
  "brokk","no-such-provider/no-such-model","not in this machine's catalogue — bin/model/catalog.sh --has says no"
                                              → exit 1

# no home at all
$ YMIR_HOME=/tmp/does-not-exist bin/gates/guards/model-rows-guard.sh check
  "model rows","SKIP","no …/config/agents.yaml — this machine declares no agent rows"   → exit 0
```

And the guard was written after it caught its own first draft: the id arrived with a trailing space
and every row read as unservable — a ward that fails on whitespace teaches nothing, so the trim is in
the code and the green run above is the proof it works.

## Owed

Nothing on this ward. §18's remaining gaps are the ones that need a credential: the smith identity, the
scoped token, the review shelf, back-pressure and independence.

## CHANGE LOG

- **2026-11-06** — first cut: the ward, the one-call catalogue comparison, the three shapes it refuses,
  and the clean skips. Wired into the one list.
