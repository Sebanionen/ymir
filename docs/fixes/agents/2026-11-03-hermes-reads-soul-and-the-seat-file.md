## agents · 2026-11-03 — Hermes reads SOUL.md, and the seat names itself from the config

### Why
The Allfather: *"why don't he know about ymir and the house voice. aren't ymir installing
it in the right way with groa … this should come on the updates and installations … read
online."* Read online (hermes-agent docs): Hermes loads **SOUL.md** as slot #1 of the system
prompt from `~/.hermes/SOUL.md` — never the working directory — and **`.hermes.md`** as the
highest-priority project instructions (walking to the git root); `AGENTS.md` loads as project
instructions. We had seated neither SOUL nor `.hermes.md`, so Hermes kept its own persona and
knew nothing of Ymir; the seat file at `~/.hermes/AGENTS.md` was inert (not a candidate).

### Mend
- **`~/.hermes/SOUL.md`** gains a **marked block** (`ymir-seat:begin … end`) written by
  `bin/seat/seat-surface.sh`: *you are <name>, the primary agent of the <host> seat in the
  Ymir fleet (<role>)* + the house voice + the tongues law + the named operator. Hermes' own
  persona text is preserved; the block is refreshed on every run.
- **`.hermes.md` at the repo root** (gitignored, machine-local — the public repo stays
  nameless, Rule 04) carries the seat + a pointer to `AGENTS.md` as the shared contract.
- **The names come from the user's config alone**: the seat from `hodd/identity/seats.yaml`
  (via seat-identity), the operator from `hodd/identity/operator.yaml`. The last invented
  fallback is removed — an unnamed operator is reported, never guessed.
- Both are written by `seat-surface.sh`, which **install and Gróa already call** — so the
  house identity arrives on every installation and every update.

### Proven
- `~/.hermes/SOUL.md` carries *Allfather Josef* and *sindri on nidavellir*; `.hermes.md` is
  written and gitignored (`git check-ignore` confirms).
- `hermes`' own loader reads `~/.hermes/SOUL.md` (prompt_builder) and `.hermes.md` (context
  candidates, priority 1) — verified in the installed package.
