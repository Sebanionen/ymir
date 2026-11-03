## agents · 2026-11-03 — Hermes joins the harnesses

### Why
The Allfather: *"hermes should also be one of the harnesses we support like pi, claude,
opencode etc … so hermes gets all the tools needed from ymir installed."* Hermes (Nous
Research) was adopted as a worker runtime but wore none of Ymir's tools: `hermes mcp
list` was empty, the house skills tree was untrusted, and its instruction surface was
the shared contract — so it answered as Brokk and saw no well, tickets, recordings,
memory or mesh.

### Mend
- **`bin/seat/hermes-seat.sh`** (new door): reads the ONE packet list
  (`~/.pi/agent/mcp-adapter.json`) and writes the same `mcp_servers` map into
  `~/.hermes/config.yaml` — merge-preserving (a live entry is never overwritten),
  idempotent, and trusts the house skills tree. `--check` names any missing packet.
- **`bin/seat/seat-surface.sh`** also points `~/.hermes/AGENTS.md` at the rendered seat
  file — Hermes reads this seat's own name and the named operator like the rest.
- The Galdr harness asset names Hermes first-class with the wiring.

### Proven
- `hermes mcp list` — **seven** packets enabled: well · bolthorn · skuld · snotra ·
  a2abridge · engram · chrome-devtools.
- `hermes-seat.sh --check` → *every packet is seated*; a second run writes 0 (idempotent).
- `seat-surface.sh --check` → the seat file names sindri · names the operator · every
  harness reads sindri on nidavellir (Hermes included).
