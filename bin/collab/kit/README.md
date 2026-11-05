# The collaboration kit — the same discipline in every repository

**What it is.** Ten small pieces that make a repository reviewable by a stranger: a baton, fix notes, a review shelf, five gates, three
hooks, and the two tools that keep them honest. They are the ones this house actually uses — not a template somebody imagined.

**Why a kit instead of a paragraph in each repo.** Two products already carry slightly different versions of the same rules, because each
was written in the moment. A kit is how they stay the same, and how the next repository starts at the standard rather than at the
beginning.

```
contents[10]{piece,path,what_it_does}:
  "the baton","`handoff/{TEMPLATE.md,check.sh,check.py}` + `handoff/CURRENT.md`","where the work is, what is blocked, and who is blocked for — rewritten at every hand"
  "the fix notes","`scripts/fixes.sh` · `scripts/fixes-components.sh` · `docs/fixes/`","one file per fix, never a changelog; a note says what was wrong, why, and what was run"
  "the review shelf","`scripts/reviews.sh` · `docs/audit/`","a review is a file named for its pull request, listed, and named by the baton"
  "the secret scan","`scripts/gates/secret-scan.sh`","a credential is refused at the commit"
  "the private-data scan","`scripts/gates/private-data.sh`","a machine path or a real address is refused at the commit"
  "the fix-note gate","`scripts/gates/fixes-guard.sh`","a behaviour change with no note is refused at the push"
  "the review gate","`scripts/gates/reviews-shelf.sh`","a review that is misnamed, unlisted or unnamed by the baton is refused"
  "the pull-request gate","`scripts/gates/pr-guard.sh`","a branch that exists on the remote with no pull request is refused at the push"
  "the hooks","`.githooks/{pre-commit,commit-msg,pre-push}`","the three moments a mistake is cheapest to stop"
  "the worktree tool","`scripts/worktree.sh`","one agent, one `.yggdrasil/<id>/` checkout — two hands never share a directory"
  "the collaborator door","`docs/collaborator-door.md` · `scripts/collab-connect.sh`","how a hand that is not on our network connects: a public card, a short-lived JWT scoped to one skill, a grant, a Rune per call — and the five refusals a door must still make"
```

Plus the rules that govern them (`RULES/15`, `16`, `17`) and `docs/gates.md`, which explains what each refuses **and what it deliberately
does not**.

## Install it

```bash
bin/collab/standardise.sh --check  /path/to/repo     # what is missing or different; changes nothing
bin/collab/standardise.sh --apply  /path/to/repo     # copy what is missing, seat the hooks, write the manifest
```

**It never overwrites a rule that is already there**, and it says which files it left alone and why. A kit that silently replaces a
repository's own law is not a standardisation, it is a raid.

## What it does not do

- **It does not decide for a repository.** A rule that does not fit is not installed; the manifest says which version is present.
- **It does not touch the code.** No pipeline, no build, no dependency.
- **It does not enforce anything on GitHub.** Branch protection is unavailable on this plan (`403: Upgrade to GitHub Pro`), so the
  enforcement is the hooks — which means a clone without `core.hooksPath` set is unprotected, and the installer sets it.
