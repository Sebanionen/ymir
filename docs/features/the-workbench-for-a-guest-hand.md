# The workbench — what a hand from another house is taught, and what refuses it

**What it is.** The part of the collaboration kit that teaches *behaviour*, not just files: a skill a contributor's agent
reads before its first branch, and two guards that notice the two faults a review kept catching too late.

## What you need

- A repository standardised by the kit: `bin/collab/standardise.sh --apply /path/to/repo`
- The hooks seated — the installer sets `core.hooksPath`; a clone without it is unprotected.

## What it now refuses that it did not before

The kit always refused a pushed secret, a machine path, a behaviour change with no fix note, and a branch with no pull
request. Two more refusals were added on 2026-11-06, both from real evidence rather than imagination:

- **a quiet change to the referee** — a host repository's gate, ward and hook folders are the referee, and changing one there must carry a
  `docs/fixes/` note *and* a word in the commit message saying which. Repairing a gate is legitimate and common; doing it in
  silence is what the guard refuses, because a gate quietly weakened looks exactly like a gate that passes.
- **a module with no test** — a new module in the host that no test names is refused, unless `.module-test.allow` says why in one line. Reachability is not behaviour.

## The skill

`bin/collab/kit/.agents/skills/smidr-the-workbench/` — *Smíðr*, the craft taught at the bench. Six steps of a slice (read, branch from the
latest base, one concern, the note with the change, a test beside a new module, the pull request in the same session), the
five things never changed quietly, and a table of what each refusal means with what to do — so a refusal is read as a
sentence, never worked around with `--no-verify`.

## The check that the kit itself is honest

`bin/collab/standardise.sh --check <repo>` now probes for **dead gates**: a hook line that runs a check after its first
`exit 0`. That fault lived in this kit until 2026-11-06, which is why the probe exists.

## If it does not work

| What you see | What to do |
|---|---|
| `DEAD GATES` in the check | the host's hook is older than the kit's: copy the kit's `pre-push` |
| `the referee is changed with no explanation` | add the fix note and name the ward or gate in the message |
| `a module arrived with no test` | write the test, or one line in `.module-test.allow` |
| no refusals at all, on any push | `git config core.hooksPath` must print `.githooks` |

## CHANGE LOG

- **2026-11-06** — Written in the same range as the guard that found the kit's dead fix-note gate.
