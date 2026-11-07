# A smith cannot ship, and a packet has somewhere to land

**Date:** 2026-11-06 · **Plan:** 205 §2.2 · §2.5 · §2.6 · **Law:** `RULES/08-delivery-gate.md`

## What was missing

Plan 203 built the two doors that *detect* — the packet door and the ship ward. Plan 205 names what was
still only prose: nothing **stopped** a smith opening a pull request (the `gh` shim did not exist), and a
packet had **nowhere to land** and **nobody waiting for it** (no shelf, no clock, no back-pressure).

## What this adds

**1 · `bin/forge/smith-gh` — the `gh` a smith sees.** It allows every read subcommand and refuses
`pr create`, `pr merge`, `pr close`, `pr reopen`, `repo delete`, `release create|delete`, naming the road:
*push the branch, write the packet, the reviewer ships.* It knows it is a smith by `$YMIR_SMITH`, or by
being inside a worker's worktree (`/.yggdrasil/` in the path) — and it cannot refuse the operator, who
works in the project root. `--install <dir>` writes `<dir>/gh` as a symlink, so a spawn can prepend a
directory rather than patch a PATH by hand.

**2 · The seat carries two more variables.** `einherjar-spawn.sh` passes `YMIR_SMITH=<id>` (the marker a
door can read without guessing) and puts `bin/forge/smith-bin` first on the seat's PATH, where `gh` is the
shim. Prepending is safe for the operator because the shim only refuses inside a worker's worktree.

**3 · `bin/forge/review-shelf.sh` — where a packet lands, and the waiting rule.**
`drop`, `list`, `tick`, `take`, `--install-timer`. The shelf is a directory of packets under
`state/review/`, and it is **one more source** for `bin/seat/pending.sh`, never a second list. The rule is
stated so it can be broken loudly: a smith waits **two ticks**, then **one** wake is raised per
(packet, head sha) — the same flood brake `pr-seal.sh` already uses — and after **three** ticks the packet
escalates, because a reviewer that is absent is a different problem from a reviewer that is slow.

## How it was proved

```
# the shim, inside a worker's worktree
$ cd /tmp/x/.yggdrasil/eins-test && ~/ymir/bin/forge/smith-gh pr create --title x
⛔ gh pr create is the reviewer's act, not a smith's.
   a smith pushes a branch and writes a packet; the reviewer ships.
     · push the branch:      git push origin eins/<id>
     · write the packet:     bin/forge/handoff-packet.py write <id> …
     · hand it over:         the packet names branch + head sha; …

# the shim, in the project root — the operator is untouched
$ cd ~/ymir && ./bin/forge/smith-gh --version
gh version 2.101.0 (2026-09-15)

# the shelf
$ review-shelf.sh drop <packet>   → "assistant-beat","…/review/assistant-beat.packet","waiting"
$ review-shelf.sh list            → ticks 0, verdict "waiting"
```

`guards.sh` is green on this branch, and `bin/gates/registers.sh generate` was run in the same change
because a new `bin/` door changes the register.

## Owed

- **The registry is still empty.** `pr-ship-guard` and the shim's marker both need an identity that is not
  the operator's login (plan 205 §2.1) — a GitHub App per seat. Until then the shim protects by worktree
  path, and the ward skips with its reason.
- **The timer is installed per seat, not by the repo.** `review-shelf.sh --install-timer` writes and enables
  `review-loop.timer` on the machine that runs it; a seat that never runs it says so.

## CHANGE LOG

- **2026-11-06** — first cut: the shim and its install, the seat's two variables, the shelf with its
  two-tick/three-tick rule, and the proofs above.
