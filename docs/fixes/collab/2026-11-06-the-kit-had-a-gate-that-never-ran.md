# The kit had a gate that never ran

**Date:** 2026-11-06 · **Component:** collab · **Found in a host repository**

## What was wrong

The collaboration kit shipped a `pre-push` hook whose **fix-note check sat after an `exit 0`**. Bash never reaches it, so
every repository standardised by this kit has carried a fix-note gate that has never once refused anything — a law with a
gate that runs nowhere, in the shape this house keeps naming.

It was found the other way round: a host repository (GrowthAgent) was measured for *why a behaviour change had landed with
no note*, and the hook there was read line by line. The same file, the same fault, the same origin. A standard that is wrong
is worse than no standard, because it is copied.

## What was done

- **`bin/collab/kit/.githooks/pre-push`** — rewritten so that **every** refusal is decided before the single `exit 0` at the
  end: the protected-branch check, the pull-request guard, the fix note, the referee guard, the module-test guard, then the
  doctor and the tests. The comment at the top of the file now states the order as a rule, so the next hand cannot re-create
  the fault by appending a check.
- **`bin/collab/kit/scripts/gates/referee-guard.sh`** — new. A change under `scripts/gates/`, `scripts/wards/` or
  `.githooks/` is refused unless the range carries a note under `docs/fixes/` **and** the message says which (ward, gate,
  hook, guard). A gate quietly weakened looks exactly like a gate that passes.
- **`bin/collab/kit/scripts/gates/new-module-test.sh`** — new. A new `backend/`, `src/lib/` or `scripts/` module that no test
  names, and that is not declared in `.module-test.allow`, is refused at the push. The evidence: an 80-line interpreter
  landed in a host with no test at all, and every ward passed, because reachability is not behaviour.
- **`bin/collab/kit/.agents/skills/smidr-the-workbench/`** — new. The craft taught to a guest hand: the six steps of a slice,
  the five things never changed quietly, and what each refusal means. A contributor's faults were process, not craft — a plan
  number already taken, a branch cut before the rules, a branch left with no pull request — and that is teachable.
- **`bin/collab/standardise.sh`** — `--check` now probes for **dead gates**: a hook line that runs a check after its first
  `exit 0` is reported by name, with the fix. A kit that can silently ship the fault it just repaired is not repaired.

## How it was verified

- `bash -n` on the hook, the two guards and `standardise.sh`: clean.
- The referee guard against **real history in a host**, not a fixture: the commit that touched
  `scripts/wards/features-shelf.ts` (`00ce4f9`) is **refused** with the file named and the remedy stated; a range that
  carries both a note and the word in its message is allowed.
- `standardise.sh --check` run against the host reports its dead gate before the fix and not after (the host's hook is the
  same file the kit shipped).

## Owed

- The host repository (GrowthAgent) still carries the **old** hook; it needs the repaired file from the kit, in that
  repository's own pull request, by that repository's own law.
- A `docs/features/` page for the kit's new pieces — written in the same range as this note.

## Appended — whose tree am I in

The Allfather: *"add to ymir so he can easy know if hes working on his own code or some projects that the users are working."*

**Built:** `bin/seat/whose-tree.sh` — one door that answers it from declared truth, never from guesswork: the git remote, the
project registry (`realm`, `posture`), the kit manifest, and the host's own `.agents/identity.json` for **who works here**
(`hands`). `--quiet` returns one word — `house` · `project: <id>` · `guest: <owner>/<repo>` — for a digest or a prompt.

**What is still missing in Ymir for this to be easy, named rather than implied:**

1. **a tree registry** — `projects.yaml` has no local path and no remote-owner mapping, so matching a tree to a project is an
   awk block; a `paths:` list per project would make it declared truth;
2. **a thicker kit manifest** — `.collab-kit.json` records the version, the date and a file count, not the host's owner and
   repo, so a guest tree cannot recognise itself without git;
3. **a session-start line** — the digest does not say which tree you are standing in or whose it is; the seat render should
   print `whose-tree.sh --quiet`;
4. **a guest law** — the rendered `AGENTS.md` is house-shaped; a guest tree should receive the kit's short law instead;
5. **a schema for `.agents/identity.json`** — today a `"github": null` row reads as a person, which is how the count came out
   three when it was two.

**Verified:** run against this machine's own code (`house`), and against a real project
(`project: growth-agent`, `realm whynotproductions`, `hands zerwiz,Sebanionen`).

## CHANGE LOG

- **2026-11-06** — Written: the kit's dead fix-note gate found in a host, the two new guards, the workbench skill, the dead-gate probe, and `bin/seat/whose-tree.sh` with the five gaps named.
