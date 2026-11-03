---
section: planned-named-and-designed-not-yet-built
---
| People | **Collaborators and clients** (`bin/people/collaborators.sh`) | One registry of the people you work with — clients, collaborators, advisers, partners — in the vault, with their addresses, the project, consent, and whether an NDA is in place. `list`/`show`/`add`/`set`/`check`/`email`. `check` validates every record and refuses an `nda: true` whose address is not in the NDA register; `email` refuses a former or non-consenting contact, refuses a missing address, and runs the private/NDA guard over the body **before** the mail door is called | [docs/features/collaborators.md](docs/features/collaborators.md) |
