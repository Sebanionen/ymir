---
section: memory-secrets
---
| Vault | **The home push door** (`bin/vault/push.sh`) | Commit and push the private home **by named path**, never `git add -A`: it stages only the paths you give it, so a scratch file written seconds earlier cannot be swept in — the fault that once cost a history rewrite. `--dry-run` prints the exact `git status` for those paths and changes nothing; a no-op answers `nothing to push` and exits 0; and a tracked file deleted among the named paths is **refused**, because a document is retired by MOVING it to `hodd/reference/`, never by deleting it (Rule 11). One commit per push, then `origin main` | [The home push door](docs/features/the-home-push-door.md) |
