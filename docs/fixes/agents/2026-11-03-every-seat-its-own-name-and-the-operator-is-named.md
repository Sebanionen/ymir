## agents · 2026-11-03 — every seat its own name, and the operator is named

### Why
The Allfather's two words:

- *"every machine and user needs to have their own names for that agent … it comes a
  lot of conflicts when several of Brokk exists. That needs to be a ymir home config
  that gets into all tools' AGENTS.md globally in installs and updates if they are
  still named Brokk."*
- *"the Allfathers for the fleets must also be mentioned by names not just Allfather
  so I would be Allfather <name>. cuz everyone are just Allfathers right now."*

Measured: `~/.pi/agent/AGENTS.md` was a symlink to the **shared** repo contract, which
opens with the counsellor (Brokk) and the bare "Allfather" — so every seat answered to
Brokk and every operator answered to the same word. `seat-identity.sh --render` existed
but **nothing called it**; `AGENTS.seat.md` did not exist.

### Mend
- **`bin/seat/seat-surface.sh`** (new door): renders the seat file
  (`~/.pi/agent/AGENTS.seat.md` = seat header + the shared contract) and points every
  harness instruction file at it (Pi · Claude Code · Codex · Cursor · Gemini when
  present). A real AGENTS.md found in the way is **set aside, never overwritten**.
  `--check` verifies the seat makes the file name BOTH the seat's primary and the
  operator.
- **`bin/agents/seat-identity.sh --render`** now states, above the contract: *your name
  is X; the contract names Brokk — that is the counsellor's craft, not your name* — and
  *the operator of this fleet is Allfather <name>* (read from the HOME config
  `hodd/identity/operator.yaml`, never the public repo).
- **Wired at install and update**: `bin/engine/ymir-install.sh` (after `--ensure`) and
  `bin/agents/groa-update.sh` (after the seat check) run the door — so every seat, on
  every install and every update, reads its own name, and a surface still naming Brokk
  is re-rendered.
- **`Hhome config`**: `hodd/identity/operator.yaml` gains `allfather: {name, display,
  fleet}`; `hodd/data/operator.md` addresses **Allfather <name>** and says why a bare
  "Allfather" names nobody in a federated hall.
- The public `AGENTS.md` carries the **principle** only — an operator is named in a
  federation — never a personal name (Rule 04).

### Proven
- `seat-surface.sh --check` → *seat file names the seat primary ✓ · names the operator (Allfather
  <name>) ✓ · every harness reads the seat primary on this host*.
- The rendered file's head names the seat and the operator; the shared contract follows
  beneath it.
