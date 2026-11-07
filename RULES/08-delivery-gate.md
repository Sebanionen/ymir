# Rule 08 — Delivery Gate & Worktree Engine

## 08.1 Every Change Leaves by Pull Request

**No direct pushes to `main` or any protected branch.** Every change — code,
config, docs, scripts — must:

1. Be done in a Yggdrasil worktree on a feature branch
2. Pass all local gates (lint, typecheck, tests)
3. Be pushed as a branch
4. Opened as a Pull Request via `gh pr create`
5. Reviewed in Glitnir (human review)
6. Approved by the Allfather
7. Merged via the PR interface — **never locally**

A local merge on a verbal "word" is a decision, not a delivery. It leaves
Glitnir with nothing to review. The gate is only fed by a PR.

**Exception:** None. If work is already on local `main`, ship it as a PR (a
branch at that commit) before doing anything else.

## 08.2 Yggdrasil Worktrees Use treehouse

**All worktree operations go through `treehouse`** (github.com/kunchenguid/treehouse).
Never use raw `git worktree` commands directly.

| Operation | Command |
|-----------|---------|
| Create worktree | `bin/forge/yggdrasil.sh create <branch>` |
| List worktrees | `bin/forge/yggdrasil.sh list` |
| Remove worktree | `bin/forge/yggdrasil.sh remove <branch>` |
| Sync worktree | `bin/forge/yggdrasil.sh sync <branch>` |

The `bin/forge/yggdrasil.sh` script is the Norse shell over the treehouse engine.
It handles:
- Branch creation from correct base
- Worktree path management under `.yggdrasil/<agent-id>/`
- Remote tracking setup
- Cleanup on completion

## 08.3 Utgard Sandboxes Use sandcastle

**All untrusted code, dynamic skills, and sub-agent tasks run inside Utgard**
via `sandcastle` (github.com/mattpocock/sandcastle, @ai-hero/sandcastle).
Never run untrusted code on the host.

| Operation | Command |
|-----------|---------|
| Spawn sandbox | `bin/forge/utgard.sh spawn <profile>` |
| Run in sandbox | `bin/forge/utgard.sh run <profile> <cmd>` |
| Destroy sandbox | `bin/forge/utgard.sh destroy <id>` |

Utgard enforces: CPU/RAM/timeout caps, no host root, no network by default.
A failed Utgard execution never touches main.

## 08.4 Enforcement

- **Pre-push hook** (installed by `bin/engine/ymir-install.sh`) rejects direct pushes
  to protected branches
- **CI gate** (`.no-mistakes.yaml` + `no-mistakes` skill) validates PRs before
  merge
- **Mjollnir pipeline** (`bin/forge/mjollnir.sh`) automates issue → worktree → PR

## 08.5 References

- `bin/forge/yggdrasil.sh` — treehouse wrapper
- `bin/forge/utgard.sh` — sandcastle wrapper
- `bin/forge/mjollnir.sh` — issue→PR pipeline
- `.no-mistakes.yaml` — clean-PR gate config
- `RULES/02-agents.md` — agents are canonical, harness dirs are symlinks
- `RULES/05-platforms.md` — core portable, per-OS layers updated together

---

*Append-only. A correction is a new entry citing the old one.*
---

## 2026-11-05 (appended) — the seat seals its OWN PR, and the word arrives through Gná

The Allfather's word, plan 190 §1:

> *"The arm holder ALWAYS NEED TO GET A NOTIFICATION IN THRU THE ARM on when a PR are done. And merge
> that PR directly. Otherwise main will move and merge will have conflicts"*

§08.1 above remains the law for every other change, and it remains the law for another hand's PR without
exception. What changes is one narrow case: **the seat's own PR, sealed by the seat's own agent, the moment
it is green** — because a PR left open is a branch drifting from a moving `main`, and every hour of delay
buys a rebase. The seal is not "skip review": review happens at open time, by the seat, before the base
moves, and the Glitnir surface still shows every PR; it simply no longer queues them.

```
seal[6]{condition,rule,evidence}
  "whose PR","THE SEAT'S OWN — opened by this seat or an Eindri it dispatched. Another hand's PR is NEVER merged by us","the PR body carries `Arm: <seat host>`, or its head is `eindri/<id>` for an errand this seat dispatched (state/<id>.meta)"
  "what state","CI green and no conflicts","every check concluded SUCCESS/NEUTRAL/SKIPPED, and mergeable MERGEABLE with no DIRTY/BEHIND/BLOCKED state"
  "who merges","the seat's agent — Sindri on nidavellir, Hœnir on heimdall — never a worker, never a timer alone","bin/agents/pr-seal.sh seal <n> is run by the seat; the arm only wakes it"
  "when notified","through Gná's arm, as a WAKE line in state/.wake-queue, naming PR, head, checks and the exact merge command","bin/agents/pr-seal.sh watch, one wake per (PR, head sha)"
  "the record","ONE Runes entry per seal naming the PR, its head and its merge commit","bin/records/runes-append.sh — carved by the seal, not remembered afterwards"
  "the brake","state/.seal-hold present means the seat merges NOTHING and says why","checked immediately before the merge, and again at watch"
```

**No merge on red or conflicted, under any flag.** The seal re-checks all six conditions at the instant of
the merge — a watch that said green an hour ago is not evidence now — and a refusal names the condition that
failed and stops. It never retries blindly. A worker never merges its own PR: the sixth condition's author
is the seat, and a worker that runs `seal` is refused by the one-open-PR and ownership checks it cannot pass.

The arm is Gná's: `watch` raises the word, the seat acts on it. A PR of this seat that was green and is then
superseded raises a new wake at a new head sha, and a wake already carried is never re-raised for the same
head — the flood brake this house has already paid for.

The tool is `bin/agents/pr-seal.sh` (`watch` · `seal <n>`); the law it enforces is this section.

---

## Appended 2026-11-06 — the delivery switch: a project may declare that its reviewer merges

**The Allfather's word, and it settles a contradiction this rule has carried since plan 203 §10:**
*"why aren't the heart reviewing all prs that comes in on the ymir repo and merging them … we have 3 prs
open."* The reviewer merges — on `zerwiz/ymir`, every PR that comes in, not only the seat's own.

**This is a declaration, not a mood, and it lives in one row.** `hodd/identity/projects.yaml` carries a
`delivery:` key per project:

```
delivery[2]{value,meaning}
  "operator-merges","DEFAULT. A PR is delivered when the Allfather merges it, by his own hand. Unchanged."
  "reviewer-merges","the project's reviewer merges, on a green, non-conflicting head, with a merge record — and the Allfather can revert, re-open a review, or withdraw the switch in one line."
```

**The six conditions are not replaced; they are re-owned.** A `reviewer-merges` project keeps every refusal
above — no merge on a red gate, on a conflict, on a missing review record, on an unverified claim, on a head
that moved after the packet, or on the reviewer's own authored work — and adds two of its own:

```
reviewer_merges[4]{rule,why}
  "the reviewer judges in a FRESH context and runs the gates itself","a claim read from a packet is not evidence; the tests run where the merge will land"
  "ONE Runes entry per merge, naming reviewer, reviewed sha, ruleset id, gate output, merge commit and the moment","a main that moved must be explainable without asking anyone"
  "the reviewer's identity can merge and cannot force-push, delete a branch, or administer","a reviewer that can rewrite history is not a gate"
  "the Allfather is told of every merge — MERGED with the record, or ASK with the question","the authority he keeps is the account, the veto, and the rule"
```

**Which projects have said so, and how to unsay it:** the row in `hodd/identity/projects.yaml`. Today
`ymir` reads `reviewer-merges` at his word; every project that does not name the key stays `operator-merges`.
Changing the row back is the whole withdrawal, and it takes effect at the next judgement.

**What this does not permit.** A reviewer that merges its own authored work (it is a reviewer, not an
author); a reviewer acting on a packet it did not read; a watch or a timer that merges without a judgement
(`bin/forge/review-watch.sh` asks, it never merges); and any merge whose record cannot be written — a merge
with no record is refused, because the record is what makes `main` explainable.

The doors are `bin/agents/eindri-review-spawn.sh --pr <url>` (seat the judge once per head),
`bin/forge/review-watch.sh` (the trigger), `bin/seat/lock-ask.sh` (the read-only agent's mouth) and
`bin/notify/mail.sh` (the word reaching him).
