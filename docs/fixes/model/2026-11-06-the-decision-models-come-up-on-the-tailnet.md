# The decision models come up on the tailnet — and the bench corrects itself twice

**2026-11-06 · component: model · `bin/model/jev-doors.sh` · `bin/notify/intake-gate.sh`**

His words, across the sitting: *"we have local jev models. how can we connect them to our work?"* · *"Read online for how to
run the models best. And use the model testing skill."* · *"Put three of our own past messages and your verdicts into the
state, and re-measure."*

## What was built

```
doors[3]{door,what,proved}:
  "jev-doors.sh","the registry of decision doors — id, model, port, licence, role — with a live probe and one raw `ask`","`list` prints four doors, three UP, OpenJev deliberately not served (CC BY-NC)"
  "intake-gate.sh","one decision call that labels a message signal · facts · hype, with the six balanced few-shot examples in the state","8 of 8 on the measured set with Kev-4B; below 0.70 it labels itself advisory"
  "the units","`jev-decision` (Julia-1 :8099) · `jev-laya` (:8097) · `jev-kev-4b` (:8098) · `jevs-lev` (:8096), all GPU, `-c 8192`, `--cache-ram 1024`, bearer key from the vault","all four resident at 11.6 GiB; 24 / 28 / 59 / 129 ms per call"
```

## The two corrections, both recorded rather than tidied

1. **"Bigger is not better calibrated"** (plan 201 §6.2) — true only without examples. With six balanced examples, the 4B judge
   is 8/8 and the 144M model collapses to 2/8. §8 corrects §6.2 by appending.
2. **The context window, not the weights, was eating the card** — the GGUF's 262,144 window cost ~13 GiB of KV for a 144M
   model. `-c 8192` brought four doors into 11.6 GiB.

## What is owed

The fifty-message sheet the Allfather is marking; the threshold comes from his verdicts, not from 0.70. The two remaining
writes the model-testing skill asks for (`backends-benchmark.md` §10.5.x and `llamacpp/TESTING.md`) are owed, and the ledger
already holds eight rows from tonight.

## CHANGE LOG

- **2026-11-06** — the doors, the gate, the units, and the two corrections (Hœnir).
