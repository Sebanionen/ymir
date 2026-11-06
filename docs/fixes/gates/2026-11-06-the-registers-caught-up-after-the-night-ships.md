## gates · unversioned · 2026-11-06 — the registers caught up after the night's integration

Pulling `main` to `22038794` (the night's integration, PR #536) left **three wards red on main
itself** — `inventory-guard`, `registers-guard`, `language-guard` — and the house's new
`main_baseline[]` said so before this branch existed: *"main is red too — this is not your branch."*

Two are one fault: `bin/README.md` and `.agents/assets/agents/capabilities.md` are **generated** and
were stale against the code the integration added. The third follows from the second — `language-guard`
found `'â' (LATIN) x460` **inside `capabilities.md`**, i.e. the character came from the stale
register's own rows, not from anything written that day.

**One regeneration healed all three:** `bin/gates/registers.sh generate`, then this note. Measured
after: `inventory-guard` *"every register is current"* · `registers-guard` *"inventory current ·
capabilities current"* · `language-guard` *"none — two tongues: English for the work, Old Norse for
the names."*

### Why this is worth a note rather than a silent commit

A generated register that is stale does not merely describe the tree wrongly — it can **accuse the
tree of a fault it does not have**. The `â` was real, but it lived in the register. A hand that
trusted the language ward without opening the file would have gone looking for a French or Portuguese
document that never existed, while the actual fault was "nobody ran the generator".

The rule this adds: **when a ward accuses a generated file, regenerate first and re-ask.** If the
fault survives, it is the source's; if it vanishes, it was the register's — and the ledger should say
which.

## CHANGE LOG

- 2026-11-06 · both registers regenerated after the integration; measured green on all three wards,
  with the reason the third was a consequence of the second.
