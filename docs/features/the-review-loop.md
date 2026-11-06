# The review loop — a PR that arrives is judged, and the judge can ask

**What it is.** Three doors that were designed and never joined, now joined. The house already had a review
spine — `bin/agents/eindri-review-spawn.sh` seats **Forseti the Judge** after an errand finishes — and a
judge that may read but never write. What it did not have was a **trigger** (nothing watched the repository,
so a PR opened by another hand was never seen) and a **mouth** (a read-only judge could not ask anyone
anything). The loop is those two pieces:

- **`bin/forge/review-watch.sh`** — lists the open PRs of the named repos, and for each PR not already judged
  at *this head*, raises **one question** into the lock owner's own queue, naming the PR, its head sha, its
  CI and its mergeability. A second pass in the same minute raises nothing (the flood brake, per `(PR, head)`).
- **`bin/seat/lock-ask.sh`** — the read-only agent's mouth. It asks the **lock owner** — the one live primary
  on the machine — "may I take this task", and the owner answers. The ask lands in the owner's wake queue
  (the arm drains it into the session between turns) and the answer lands in the asker's own inbox.
- **`bin/forge/review-seat.sh`** — the reviewer's SEAT: one herdr workspace named `review`, one **pi** agent
  in it, cwd a **clone** of the repo (never a smith's worktree), its charter the judge's role file plus the law
  it judges by, its model resolved for that seat. `ask <pr>` puts one PR in front of it.
- **`bin/forge/review-verdict.sh`** — the judge's ONE act of writing. The charter keeps `edit: deny`,
  `write: deny`, so the verdict is written through a door that checks the **head sha** and the verdict shape,
  and `ship.sh` reads it.
- **`bin/forge/ship.sh`** — the reviewer's merge, and only for a project that declares
  `delivery: reviewer-merges`. Six conditions, the first failing one named: the switch, an open and
  mergeable PR, green CI, a verdict that is not a refusal, a verdict naming the SAME head, and no
  `state/.seal-hold`. Then: merge, ONE Runes entry, and the word to him — MERGED, or a FAIL line.
- **`bin/agents/eindri-review-spawn.sh --pr <url>`** — the same judge through the einherjar road, for a machine
  with no herdr seat: a PR with no errand record, marked once per **head sha**.

**What you need.** `gh` logged in on the seat that runs the watch, a live primary holding the lock (the ask is
refused when there is none), and the home's state directory (resolved through `bin/vault/hoard-lib.sh`). The
judge's model is **resolved for that seat** by `bin/model/agent-model.sh` — never a model id in the code.

**The commands**

```sh
bin/forge/review-watch.sh                     # one pass: ask about every unjudged open PR
bin/forge/review-watch.sh --repo owner/repo   # a different repo (repeatable)
bin/forge/review-watch.sh --dry-run           # what it would ask, and nothing else
bin/forge/review-watch.sh --judge 552         # the owner's answer: pi in herdr reviews PR #552

bin/forge/review-seat.sh ensure               # raise the reviewer's seat (one herdr workspace, pi)
bin/forge/review-seat.sh status               # is it there, and what is it doing
bin/forge/review-seat.sh ask 552 --wait        # one PR in front of the seated judge
bin/forge/review-verdict.sh write 552 --head <sha> --verdict PASS --reason "…"
bin/forge/ship.sh --check 552                 # judge the six merge conditions, merge nothing
bin/forge/ship.sh 552                         # merge, write the Runes entry, mail him

bin/seat/lock-ask.sh who                      # the lock, the arm, and whether they agree
bin/seat/lock-ask.sh ask "may I judge PR 552" --task pr-552 --as forseti
bin/seat/lock-ask.sh inbox forseti            # the answers waiting for that agent
bin/seat/lock-ask.sh answer <ask-id> "yes, judge it; do not merge"   # the OWNER only
bin/seat/lock-ask.sh list [--all]             # open asks, or every ask
```

**Limits — what this deliberately will not do.**

- **An ask is not a grant.** The owner's answer is the owner's word, never the Allfather's. A merge still
  needs `RULES/08` and his hand (or a project's `delivery:` switch).
- **The watch never merges, pushes, comments on GitHub, or decides.** A watch that decided would be a gate
  with no judge in it.
- **One answer per ask.** A second answer is refused by name, never written over the first.
- **Only the owner answers.** `answer` proves the caller descends from the live lock owner's process tree; a
  stranger with the file path cannot speak as the owner.
- **No live owner, no ask.** A dead lock, or a lock and an arm that disagree, is a refusal that names the
  road — never "nothing to do".
- **The judge may not write** — except its verdict, through `review-verdict.sh`, which checks the head sha.
  If the work needs a hand, the judge asks the lock owner, and the owner does it or seats someone who can.
- **A merge needs a project that says so.** `ship.sh` refuses `operator-merges` by name; the switch is one
  row in `hodd/identity/projects.yaml`.

**If it does not work.**

- `review-watch: REFUSED — this seat has NO working GitHub identity` — run `gh auth status`; the watch will
  not report an empty repository as "nothing to do".
- `lock-ask: REFUSED — the lock owner (pid X) and the arm (session Y) DISAGREE` — the arm lease is stale;
  `bin/pi/syn-watch.sh` re-arms it. A wake written to a queue nobody drains is a message in a bottle.
- `agent-model: REFUSED — … is NOT in this seat's catalogue` — the model the fleet declared is not one this
  machine can serve. Correct the row for this machine (`config/agents.<host>.yaml`) or name a listed model.

## CHANGE LOG

- **2026-11-06** — written with the doors it describes (plan 206): the review loop joined to the
  spine, the read-only agent's mouth, the resolver that replaced five hardcoded model ids, and the
  operator-only mail door.
