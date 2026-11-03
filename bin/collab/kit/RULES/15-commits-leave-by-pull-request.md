# 15 — Every commit leaves by a pull request, or it lands in main

**Added 2026-11-02** at the Allfather's word: *"all commits must come up as PRs or into main."*

## The rule

```
law[4]{rule,why}:
  "**a branch without a pull request is unfinished work**","a commit that nobody can see is a commit nobody can review, and a review is the only thing between a change and a surprise"
  "**a pull request names what it changes and what proves it**","the reviewer reads the claim and the evidence in one place, not a diff and a guess"
  "**only the Allfather merges**","the gate is human by design; an agent that merges has replaced the gate with its own judgement"
  "**production runs a sealed commit**","a deploy from an unmerged branch means the thing being reviewed is not the thing being run"
```

## What this corrects

**A deploy from a working tree that had no pull request.** For two days this service ran code from a branch that was never put up for
review. It worked, and that is exactly the problem: the running system and the reviewed system were allowed to be different, and nothing
would have said so.

```
correction[2]{what,now}:
  "a deploy from an unsealed branch","the commit that is deployed is named in `docs/operations/DEPLOYED.md`, and it must be reachable from `main` or from an open pull request"
  "a commit that sat on a branch alone","`gh pr list` is checked before a session ends; an unpushed or unproposed branch is reported, not left quietly"
```

## How it is checked

```bash
gh pr list --state open          # every branch that is not main should appear here
git log --oneline origin/master..HEAD   # and every commit here should be in one of those pull requests
```

**A green doctor is not evidence of this rule** — the wards check the code, and only a person checks that the code is proposed.
