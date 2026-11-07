---
section: planned-named-and-designed-not-yet-built
---
| Security | **The vault's edit door** (`bin/vault/hodd-set.sh`) | Set or read ONE key inside the age-encrypted vault without ever touching the file by hand: `KEY VALUE` writes, `--get KEY` prints one value, `--list` prints names only. Four guards, each of which was missing on the day a hand-edit replaced 90 secrets with 3: the decrypted plaintext must be non-empty, the re-encryption is decrypted again and compared before it replaces anything, the old file is kept as a timestamped backup, and the write is atomic at 0600 with every plaintext temp shredded | [docs/features/the-vault-edit-door.md](docs/features/the-vault-edit-door.md) |
