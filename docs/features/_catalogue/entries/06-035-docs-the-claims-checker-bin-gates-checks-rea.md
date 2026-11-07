---
section: planned-named-and-designed-not-yet-built
---
| Docs | **The claims checker** (`bin/gates/checks/readme-claims.sh`) | Reads the user-facing documents and refuses a claim the tree does not hold: every repo path a page names must exist, `@zerwiz/*` packages are checked against the registry with `--npm`, and `--ports` reports what actually listens. A line is waived in writing (`<!-- stale-ok: reason -->`) or by `docs/README-claims.waived`. Run by the `docs-claims-guard`, so a stale instruction cannot be pushed | [docs/features/the-claims-checker.md](docs/features/the-claims-checker.md) |
