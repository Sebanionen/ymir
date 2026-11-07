# The decision models become rail presets, not services

**2026-11-06 · component: model · `~/.config/llama-rail/models.ini` · `bin/model/jev-doors.sh`**

His word: *"arent the jev models auto offlods as the other models?"* They should be, and four always-on user units were the
wrong shape: they held 11.6 GiB of a 16 GiB card and a 35B coder then failed to load (`cudaMalloc failed: out of memory,
11.4 GiB` — measured, not inferred).

## The change

- Four presets added to the rail — `kev-4b@q8_0` · `laya@q8_0` · `lev@q8_0` · `clef@q4_k_m` — each `ctx-size 8192` (the head
  reads ≤ max_head_tokens and the prompt is one batch; the advertised 262,144 window is pure KV waste) and `n-gpu-layers 999`.
- The four `jev-*` user units are **retired** (`disable --now`); the card returned to 320 MiB.
- `jev-doors.sh ask` sends the **model id in the body** to the rail's `/v1/systemone`, so the router swaps the model in on
  demand and releases it on idle — the same law as every 35B on this box.
- `~/.config/ymir/jev-doors.yaml` gains `serve: rail` and every `port: 8080`.

## Proven

`llama-server --models-preset ~/.config/llama-rail/models.ini` on a spare port lists **43 models** with five decision aliases;
one on-demand call (`"model":"kev-4b@q8_0"`) answered `signal 0.563 / facts 0.194 / hype 0.243`, loaded at 7,031 MiB.

## Still owed, and it is the operator's

The **running** rail is the old binary: `:8080/v1/systemone` returns 404 until `/usr/local/bin/llama-server` is replaced
(`sudo`). The presets and the door are ready; the swap makes them live. Exact lines and rollback:
`docs/fixes/model/2026-11-06-the-rail-swap-is-prepared-not-performed.md`.

## The rule this settles

**A decision model is a preset, not a service.** Residency belongs to the rail: load on demand, one resident, unload when idle.

## CHANGE LOG

- **2026-11-06** — presets, retired units, rail-mode door (Hœnir).
