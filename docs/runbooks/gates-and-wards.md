# Runbook — gates and wards: what refuses, and why

A gate is a check that runs where a mistake would otherwise reach a merge. A **ward** is a gate over the tree
itself — a rule turned into arithmetic. A gate that cannot say why is an obstacle, so every ward names the fault and
the remedy.

## Run them

```bash
bash bin/gates/guards.sh                 # the ONE list: every tree ward, PASS/FAIL, with the finding
bash bin/gates/guards.sh --list          # the names
bash bin/gates/ci-verify.sh              # the wider surface CI runs (registers, tests, extensions, packaging)
bash bin/gates/guards/<ward>.sh check    # one ward, on its own, with its full message
```

A ward prints a TOON block and exits non-zero on a finding. Some are run by git hooks (`branch-guard`,
`fixes-guard`), so a bad push is refused before it leaves.

## What the wards watch

```
wards[12]{ward,refuses}
  "runtime-guard","a door that contradicts its own docstring"
  "runtime-pinned-guard","a unit that executes a working tree"
  "defaults-guard","a guessed home, a second resolver, a tracked absolute symlink"
  "inventory-guard","a stale register (bin/README.md, the backend index)"
  "path-ledger-guard","a path that moved without a migration"
  "subsystem-docs-guard","a governed path edited with no owning document"
  "cron-guard","a schedule row that names a door which does not exist"
  "features-guard","a user-facing feature with no page"
  "vault-guard","a commit that copies confidential content out"
  "confidential-guard","a commit outside the vault while a confidential session runs"
  "dead-code-guard","a runtime module nothing reaches"
  "docs-claims-guard","a document that claims what the code does not do"
```

## Adding a ward

1. Write `bin/gates/guards/<name>.sh` that prints a TOON finding and exits 1 on failure, 0 on a clean pass, 0 on a
   *named* skip (a seat where the thing cannot exist).
2. Add it to the **one list** in `bin/gates/guards.sh`. A ward not in that list runs nowhere.
3. Add a fix note under `docs/fixes/<component>/` — the guard reads the range a push adds.

## When a ward fails

- **Read its message first.** Each ends with `help:` and the remedy.
- **Run the same ward on `main`.** A red `main` disguises itself as a red branch: the fault may be inherited, and
  then it is the branch's business only to say so.
- **Registers are derived.** `bin/gates/inventory.sh` and `bin/gates/capabilities.sh` write their files; never
  hand-edit a register to make a ward pass.
- **A ward that flickers is a bug in the ward.** Judge the commit, not the working tree, and state any tolerance
  in the file rather than hiding it.
