# The ship door is the PR, not the push — `pr-ship-guard`

**Date:** 2026-11-06 · **Plan:** 203 §14 · **Rule:** `RULES/08-delivery-gate.md`

## What was wrong

Plan 203 §6 said a smith may not push. The Allfather found the hole in one question: *"It needs to
push the branch, otherwise how will the heart be able to get the code and make PR and merge?"* A
PR cannot be opened from a branch that exists only on a laptop, so a rule that forbids the push
forbids the handoff. The gate was never "pushing" — it was **shipping**. §14 restated it: a smith
pushes its branch (`eins/<id>` or `smith/<id>`), and may never open a PR or merge.

Restating a rule in prose changes nothing on its own. §14.2 named the three doors, and every one of
them was still paper: `pr-ship-guard` did not exist in `bin/gates/guards/`, there was no `gh` shim,
and nothing anywhere judged the author of a pull request.

## What was built

`bin/gates/guards/pr-ship-guard.sh` — the ward that closes the door that actually ships.

- It judges **every open pull request in this repository by author login**, against the smith
  registry: `$YMIR_SMITH_IDENTITIES`, or `$YMIR_HOME/hodd/identity/smiths.txt` (one login per line).
- A PR authored by a registry identity is **refused**, naming the PR, its head, its URL and the
  remedy: *a smith pushes a branch and writes a packet; the reviewer ships.*
- It **never judges the branch or the push** — that is the correction §14 makes. `branch-guard`
  keeps the only push refusal that survives: a push that lands on `main`.
- It **never judges blind**: no `gh`, no auth, no network, unreadable JSON, or no registry — each
  one is a clean skip that prints its reason, per RULES/25. A door that fails open silently is how
  the house has been burned before.
- It has a network-free mode, `--author <login>`, so a hook or a test can judge one identity without
  a round trip, and `--pr <n>` to judge a single PR.

Wired into `bin/gates/guards.sh` so the pre-push hook and both CI hosts run it — the one list, as
that file insists. Measured cost on this seat with a live network: **1.08 s** for one open PR.

Supporting work: `hodd/identity/smiths.txt.example` (the registry's shape and its law),
`.agents/assets/agents/subsystem-docs.md` gained the `bin/gates/**` row it never had — so every
future guard answers `where.sh` instead of reporting "no row" — and
`bin/gates/tests/test_pr_ship_guard.sh` proves the four cases.

## What it does not do yet

- **The `gh` shim.** §14.2 also calls for a PATH shim that refuses `gh pr create` / `gh pr merge`
  from a smith's environment while allowing reads. Not built here: it belongs to the spawn path
  (`bin/agents/einherjar-spawn.sh`), and it needs an environment marker that does not exist yet —
  the spawn does not export a smith identity. Named so it is not mistaken for done.
- **The packet's sha check.** §14.1's refusal of a fetched head sha that differs from the packet's
  is the reviewer's, and lives on the heart. The schema is being stood up there.

## How it was proved

```
bin/gates/tests/test_pr_ship_guard.sh     # 7 passed, 0 failed
  ok   a smith's login is refused (rc=1)
  ok   the refusal names the reviewer's door
  ok   the refusal names the identity it refused
  ok   another hand's login passes
  ok   the hoard registry is read (comments and blanks ignored)
  ok   no registry is not a failure
  ok   the skip names its reason
YMIR_SMITH_IDENTITIES=somefakebot bin/gates/guards/pr-ship-guard.sh check
  pr-ship-guard[1]{gate,result,open_prs,repo}:  "ship door","ok","1","zerwiz/ymir"
```

## CHANGE LOG

- **2026-11-06** — first cut: the ward, its test, the registry example, the `bin/gates/**` row in the
  subsystem map, and its seat in `guards.sh`. Refusals proved by test; the live path proved against
  `zerwiz/ymir` (one open PR, no smith author).
