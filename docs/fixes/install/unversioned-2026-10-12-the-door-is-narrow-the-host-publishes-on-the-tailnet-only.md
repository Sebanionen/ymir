## install · unversioned · 2026-10-12 — the door is narrow: the host publishes on the tailnet only

### What

Answering the Allfather's question — *"do we have any security on this now?"* — the honest
answer was no, and the sharpest part of it was the **binding**: the engine and Element were
published on `0.0.0.0`, so **the LAN was a door**, not only the fleet's tailnet.

Two changes, and one measured trap:

1. **The gate law** (plan 75 Part 13): no Ymir service faces the public internet without an
   identity gate in front; behind the gate it binds narrowly. The ensure now publishes the
   host port on the **tailnet interface only** (`tailscale ip -4`), falling back to
   `127.0.0.1` — never `0.0.0.0`.
2. **The trap, measured**: narrowing the *in-container* `address` to the tailnet IP makes the
   service **unreachable**, because that address does not exist inside the container. The
   in-container address stays `0.0.0.0`; the **published port** is what narrows.

### Verified

- `ss -ltn` now shows `<tailnet-ip>:8008` and `<tailnet-ip>:8090` — the tailnet, and no
  `0.0.0.0`.
- tailnet → **200**; LAN address → **000 (refused)**.
- **The fleet still speaks**: heimdall's Eitri posted *"…after the LAN was shut, the tailnet
  still carries us."* — the security change did not break the fleet, which is the point.

### Files

- `bin/room/gladsheim-ensure.sh`
