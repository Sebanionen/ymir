---
section: planned-named-and-designed-not-yet-built
---
| Security | **The ward — Vörðr** | `bin/ward/security-audit.sh` reads every door this machine opens (ports, ufw by source, the effective sshd policy, public tunnels and whether they ask for a login, secret file modes, whether anything watches the host) and fails on a HIGH or CRITICAL; `verdr.sh` walks the house, writes the dated report into the home and speaks on a HIGH; `harden.sh` writes every mend with its revert line, applies the safe ones, and **refuses** the firewall change without the operator's word | [docs/features/the-ward.md](docs/features/the-ward.md) |
