# The home contract arrived, and the seeder became its one parser

**Date:** 2026-11-02 · **Component:** install · **Continues:** `2026-11-02-the-home-is-made-and-explained.md`

Another hand landed **RULES/42** and `.agents/home-contract.yaml` in the same sitting: *every file the runtime reads
from the home, and how it reaches the user* — 45 rows, each naming a path, a kind (`seeded · stub · defaulted ·
optional · generated`), the template that ships it, the door that writes it, whether the house can run without it,
and why it matters. Its ward calls **one parser** and refuses two truths.

`bin/engine/home-seed.sh` is that parser now:

- `--list` prints the rows, which is what `bin/gates/checks/home-contract-check.sh` reads;
- a plain run seeds every `seeded`/`stub`/`defaulted` row from its shipped template **when the file is absent**, and
  never touches an existing file — the operator's record outranks any default;
- `{realm}` in a path is resolved from the realm pin, the only substitution allowed;
- a row that promises a template the repo does not ship is printed as a finding, not skipped silently.

## Measured

```
bin/engine/home-seed.sh --list          → 45 rows
bin/gates/checks/home-contract-check.sh → "45 rows, 0 findings, clean"
scratch home, first run                 → 13 directories + 25 files from the templates
scratch home, second run                → "complete, every directory the house expects is already here"
```

## Why it belongs in this note

The Allfather's question was whether every template a home needs ships and arrives on install and update. The answer
is now structural: the templates ship in `.agents/templates`, the contract names each one, the seeder copies it once,
Gróa re-checks the shelves on update, and a ward proves the three agree. A feature that starts reading a new home
path adds a row, or the ward says so.
