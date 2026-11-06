# Rule 48 — a repository that is not ours

**The house's discipline travels into a client's repository; the house's voice and identity do not.**

Written 2026-11-06, at the operator's word: *"make a rule in ymir when we're working in repos for clients or
other projects that are not for ymir and gimle."* The day it was written we installed the collaboration kit into
Inmost Invest's Control Tower and found three things wrong — a hook that assumed npm, a handoff written for a
seat instead of for a client, and a gate that had never run — all three because the kit had only ever been used
inside our own walls.

## Which repositories this rule governs

**Read the owner; never infer it.** A repository is *ours* when `$YMIR_HOME/hodd/identity/projects.yaml` carries
it with our realm and our owner. Everything else — a client's product, a partner's codebase, an associate's
project, a repository we were invited into for one errand — is **not ours**, and this rule applies from the
first commit. Rule 41 already says a name is not a licence; this is what follows from it.

## The law

```
laws[7]{rule,why}:
  "their law wins","a rule already in the repository is reported, never replaced — installing our standard over their rule is a raid, and the next hand cannot tell a deliberate difference from drift"
  "write for their reader","every word we leave — handoff, fix note, pull request, commit message, README row — is business English: no Allfather, Brokk, Eindri or Galdr, no plan numbers, no runes, no seats, no wells; names as their contract carries them (Rule 21, and the handoff check refuses the personae outright)"
  "our discipline travels, our identity does not","the baton, the fix notes, the review shelf, the gates and the hooks make their repository reviewable by a stranger, so they travel whole; our plans, our vault, our memory, our ledgers and our agents' names stay home"
  "probe the stack, never assume it","a hook or a script we install asks the repository what it is (its own scripts, npm, mix) and prints a plain skip when there is nothing to run — a hook that refuses honest work is taught --no-verify and stops being a gate (Rule 25)"
  "prove it on one real change","an install we call done has been walked through by one real commit and one real pull request in that repository; an install nobody has exercised is a claim, not a gate"
  "their data stays theirs","nothing from a client's repository enters our home, our memory or our vault, and nothing from the vault enters theirs — credentials are by reference, and a database, a customer or an address is never copied out (Rules 15, 26)"
  "deliver by their door","we push a branch and open a pull request on their remote and stop; their owner seals the merge — the operator's own hand where he holds the pen, the client's where he does not (Rule 08)"
```

## What we leave behind

An install is a **manifest and a baton**, so their next hand can see what we did without asking us:

- `.collab-kit.json` — the kit version and the date it was installed, written by the installer;
- `handoff/CURRENT.md` — the state of the work in their language, with a `**For:**` line naming the person who
  reads it;
- the pull request — the only place our reasoning is visible to them in their own tooling.

## What is not yet gated, and is therefore a discipline

The language half is a gate: `handoff/check.py` refuses the house personae in a baton, with a written
`allow-house-word:` waiver on the line that needs one. The rest — their law winning, their data staying theirs,
a merge sealed by their owner — has no ward yet; it is held by review, and this rule is what the review cites.
A ward that reads `projects.yaml` and refuses an install into a repository the registry calls ours would be the
next step, and it is named here rather than implied.
