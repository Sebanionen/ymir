## install · 2026-11-03 — the house identity on every platform, for every user

### Why
The Allfather: *"set this up on the [host redacted] also. and make sure all other users on windows etc also
gets this when installing and updating ymir. follow the rules."*

RULES/05: the core is portable and each platform layer delegates to it — so the seating must live in
the **core install and in Gróa**, never in a per-OS copy.

### Mend
- `bin/engine/ymir-install.sh` runs `valknut-load.sh **--all**` (Pi · OpenCode · **Hermes**); each
  harness that is absent prints a clean skip, never a failure (RULES/25: probe, never assume).
- `bin/agents/groa-update.sh` already ran `--all --global`, so every **update** re-seats the harnesses
  and the seat surface (which writes `AGENTS.seat.md`, `.hermes.md`, `SOUL.md` and the `ymir` packet).
- **Windows**: `bin/host/bootstrap-windows.ps1` hands the install to `bin/engine/ymir-install.sh`
  *inside* WSL — the same core, so the same seating; no second implementation.
- **macOS / Linux**: the same install script directly.

### Proven on the [host redacted] seat (the sibling seat)
- `seat-surface.sh` → *brokk on the [host redacted] seat* for the seat file, and **the machine agent** in `~/.hermes/SOUL.md` as
  the machine's own agent (distinct from brokk, Ymir's counsellor — a machine agent is never doubled
  as the seat primary).
- Machine adapter gained the `ymir` packet; `hermes mcp test ymir` → **✓ Connected · 15 tools**;
  Hermes carries **13** packets (well · bolthorn · skuld · snotra · a2abridge · engram · firecrawl ·
  hnoss · trello · gmail · drive · docs · ymir).

### Proven here (this host)
- `seat-surface.sh --check` → seat file names the seat primary · names the operator · SOUL carries the identity ·
  `.hermes.md` written · every harness reads the seat primary on this host.
- `ymir-mcp.py --selftest` → 15 doors; `hermes mcp test ymir` → connected, 15 tools.
