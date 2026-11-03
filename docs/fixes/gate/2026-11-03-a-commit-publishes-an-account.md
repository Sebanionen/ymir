# A commit publishes an ACCOUNT — the personal mailbox and the twelve hundred commits

**Date:** 2026-11-03 · **Component:** gate · **At the Allfather's word:** *"WHY THA FUCK DO WE HAVE PERSONAL DATA IN YMIRS REPO?"*

## What he found, measured

**Not in a file — in the commit metadata.** No tracked file in this repository carries his address (`git grep` is clean).
What carries it is the author line git writes into **every commit**, because this seat's `user.email` was his personal
mailbox:

```
measured[4]{fact,number,how_anyone_can_read_it}:
  "commits in the public repo authored with the personal mailbox","1,236","git log, the GitHub commit list, every PR, every fork, the API"
  "the same address on the home repo","present","the private repo is not public, but every seat that clones it sees it"
  "this seat's git identity before today","user.email = the personal mailbox","git config --get user.email"
  "what the house watched","files only","secret-guard and private-guard scan CONTENT — neither read the identity of a commit"
```

So the law was enforced on what a commit **carried** and never on **who it said made it** — the one field every agent
writes, in every repository, at every commit.

## What changed

- **The identity is the account, not a mailbox.** `git config --global user.email` is now the address GitHub mints for
  the account: `<id>+<login>@users.noreply.github.com` — derived by asking GitHub (`gh api user`), never guessed. Set on
  this seat, in this repository and in the home repository.
- **`bin/gates/guards/identity-guard.sh`** — refuses a push whose added commits carry an address that is neither a
  noreply account form nor a house identity (`brokk@ymir`, `an-eindri@ymir.local`, `*@zerwiz.org`). The refusal names
  the remedy (`--amend --reset-author`) and the lawful escape for a genuine exception
  (`YMIR_ALLOW_PERSONAL_EMAIL="why"`). It judges the **range a push adds**, never history: a gate that fails on all
  existing commits is a gate that gets switched off.
- **Seated where a commit leaves:** the pre-push chain (`fixes-guard.sh --install`) and `ci-verify.sh`, beside Rule 11's
  ward.
- **`bin/records/developers.sh` reads the ACCOUNT.** `whoami` prints the login, the name, the address commits *should*
  carry, what this checkout is set to, and a verdict (`agrees` / `DIFFERS`). The authors row now prints **logins**,
  masks a personal address (a masked address) and shows it only with `--emails`. The register identifies people; it does
  not republish their mailboxes.

## What this does not fix, and must not pretend to

**The 1,236 published commits are public and stay public.** They sit in every clone, every fork and every cached page.
Unmaking them is a **history rewrite** — `git filter-repo --mail-map`, a force-push to `main`, and GitHub support to
expire the unreferenced objects — and that is the Allfather's decision, not an agent's (plan 171). What this change does
is stop the leak, and make the next one impossible to do by accident.

## The faults this found in itself

- The register printed author **emails** for any repository it was pointed at — a door that republishes exactly the
  thing this note is about. Masked by default, addresses shown only on request.
- The house's own agent addresses (`brokk@ymir`) read as "personal" in the first cut of the mask; they are identities,
  and the ward now names them as allowed.

## Files

`bin/gates/guards/identity-guard.sh` · `bin/gates/guards/fixes-guard.sh` · `bin/gates/ci-verify.sh` ·
`bin/records/developers.sh`
