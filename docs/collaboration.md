# Collaboration — one door, one shelf, and the kit every repository carries

**The question this answers:** *we work in several repositories with several people and several agents — is there one way of doing it, and
can it be put into a new repository as a standard rather than rebuilt?*

**The answer: one door, `bin/collab/collab.sh`.** It already owned the baton shelf; the rest of the discipline is installed through the
same door, so there is no second system to keep in step. **The declared truth about who collaborates is not in code at all** — it is
`$YMIR_HOME/hodd/data/collaboration.yaml`, read by that door and by nothing else.

```
door[5]{command,what_it_does,changes}:
  "`collab.sh who`","the roll: every declared person, measured","nothing"
  "`collab.sh ladder`","the rungs: what each person owes, and which projects carry the shelf","nothing"
  "`collab.sh init <repo>`","**the baton shelf**: `handoff/{README,TEMPLATE,CURRENT,log,check}`","installs what is missing, never overwrites a baton"
  "`collab.sh standardise <repo> --check|--apply`","the baton **plus** the gates, the hooks, the fix notes, the review shelf, the worktree tool and the PR check","installs only what is absent; reports what differs"
  "`collab.sh letter` / `ship` / `publish`","a drafted letter, a sealed branch, a board card","as named"
```

## What the kit is

`bin/collab/kit/` — **fifteen files, versioned together**, because they only work as a set: five gates that refuse a credential, a machine
path, an unreviewed branch, a behaviour change with no note, and a review nobody can find · three hooks that call them · two tools that
keep the record honest (`fixes.sh`, `reviews.sh`) · one tool that keeps hands apart (`worktree.sh`) · and the rules that say why
(`RULES/15`, `16`, `17`).

```bash
bin/collab/collab.sh standardise /path/to/repo --check     # what is missing or different; changes nothing
bin/collab/collab.sh standardise /path/to/repo --apply      # install what is absent, seat the hooks, write .collab-kit.json
```

**It never overwrites a rule that is already present**, and it prints what differs so a repository's own law is visible rather than
silently replaced. That is deliberate: a standardisation that rewrites the local law is a raid, not a standard.

## Where each part of the standard lives, and why

```
placement[4]{thing,home,why}:
  "the kit (scripts, hooks, gates)","**this repository** (`bin/collab/kit/`)","it is deployable machinery, not private data — it belongs with the platform"
  "the door (`collab.sh`, `init.sh`, `standardise.sh`)","**this repository** (`bin/collab/`)","one entry point, versioned with the kit it installs"
  "who collaborates, on which surface, at which rung","**Ymir Home** (`hodd/data/collaboration.yaml`)","private: names, addresses, seats. Never in a public repository"
  "the baton and the fix notes of each project","**inside that project**","the project changes in the same commit as its own record"
```

**Rule 04 and the first law decide the split, not taste:** a name, an address or a seat is private and lives in the home; a script that
refuses a secret is machinery and lives here.

## What it does not do

- **Nothing on GitHub's side.** Branch protection is unavailable on this plan (`403: Upgrade to GitHub Pro`), so enforcement is the
  hooks. A clone that never ran `standardise --apply` has `core.hooksPath` unset and is unprotected — which is why the installer sets it.
- **No code, no build, no dependencies.** The kit is shell and three small Python helpers.
- **No decision for a repository.** A rule that does not fit is reported, not installed.

## The two repositories that carry it today

```
carried[2]{repo,state,note}:
  "`zerwiz/nordic-global-solutions-fundraising`","**15 of 16 present**, one file differs","`scripts/gates/private-data.sh` differs — the local copy skips the gate's own directory, which the kit's does not"
  "`zerwiz/investready`","**10 of 16 present**","six rules and docs are absent, because it was standardised before `RULES/15–17` existed; three files differ, each a local decision"
```

**The drift is the point of the check.** It is not a failure that a repository differs — it is a fact that should be visible, so that a
person can decide whether the difference is deliberate.
