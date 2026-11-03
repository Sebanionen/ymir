# Templates and logic only — the public tree loses the operator's name, the fleet's geography and the mailboxes

**Date:** 2026-11-03 · **Component:** gate · **At the Allfather's word:** *"YMIR CAN ONLY CARRY TEMPLASTE AND LOCIG:: NOT SECREATS OR PRIVATE DATA::"*

## What was measured, at his word, on a **public** repository

```
found[6]{class,where,state}:
  "the operator's personal name, twice, inside the ward that forbids personal data","bin/gates/guards/public-guard.sh's pattern list","the name was a literal alternative; its `$HOME` alternative sat inside a single-quoted string, so it never expanded and matched NOTHING. The ward was both a copy of the leak and, in one third, decoration"
  "the operator's name and mailbox in public fix notes","8 notes under docs/fixes/","bare name, an address on the company domain, a brief filename"
  "private topology, including fixtures","22 files: a real LAN address as a code default (bin/skuld/skuld-sync.sh), a real host in docs/installations/termux.md, a real tailnet id in .example files and tests","the rule refuses topology in a FIXTURE as loudly as in code"
  "a tool that republished addresses","bin/records/developers.sh printed every author's mailbox for any repository it was pointed at","the register identifies people; it was publishing them"
  "no ward read a commit's identity","pre-commit scanned content, pre-push scanned the tree, nothing read the author line","1,236 commits on the public remote carry the operator's personal mailbox"
  "the name list had no home","the words were in the guard, because there was nowhere else for them","it belongs in the home, read at run time"
```

## What changed

- **`bin/gates/guards/public-guard.py` (new)** judges four classes precisely — a secret shape, a declared operator
  word, TOPOLOGY (a private address is allowed only as a declared CIDR range or RFC 5737 space; a tailnet name only as
  the shape `<host>.tailnet.ts.net`) and a MAILBOX (only example domains, noreply forms, ssh identities, role
  mailboxes and house addresses). Generated third-party text (a lockfile's upstream deprecation strings) is exempt by
  name, because editing it breaks an install and the address is not ours. Binaries are skipped: a PNG is not a document.
- **`bin/gates/guards/public-data-guard.sh` (new)** is the ward in the one list (`guards.sh`), so CI runs the tree scan
  and `ci-verify` gains `public-data`.
- **The operator's words live in the home**: `$YMIR_HOME/hodd/security/operator-words.txt`, read at run time through
  `hoard-lib.sh`. With no list on a machine, the ward says so and judges the other three classes — a clean skip is a
  pass, a false green is not.
- **`bin/gates/checks/public-data-ward.test.sh` (new)** plants one case per class, requires the refusal, requires a
  clean template to pass, and requires **the ward itself to carry no declared word** — RULES/04's own clause.
- **The tree was cleaned**: the 8 fix notes redacted to `<the operator>` with the correction appended (RULES/06), 13
  files' seat names in topology positions replaced by the shape, fixtures moved to RFC 5737 space (`192.0.2.x`) and
  declared sentinels, one third-party domain in a fixture replaced by `example.com`, and one real LAN default in code
  replaced by documentation space.
- **`bin/records/developers.sh`** prints logins, masks a personal address, shows it only with `--emails`, and gains
  `whoami` — reading the ACCOUNT (`gh api user`) rather than a mailbox.
- **`bin/gates/guards/identity-guard.sh` (new)** refuses a push whose added commits carry an address that is neither a
  noreply account form nor a house identity; seated in the pre-push chain and in `ci-verify`.
- **RULES/04 appended**: the repository carries templates and logic; a commit's author line is data; a guard may not
  name the values it protects.

## What this does not fix

**The published history.** 1,236 commits on the public remote carry the operator's personal mailbox in their author
line, and no ward can unmake them. That is a history rewrite and the Allfather's decision — plan 171, phase 4. What
this change does is stop the leak, prove the ward refuses, and leave the past named rather than assumed.

## Files

`bin/gates/guards/public-guard.py` · `bin/gates/guards/public-data-guard.sh` · `bin/gates/guards/public-guard.sh` ·
`bin/gates/guards/identity-guard.sh` · `bin/gates/guards.sh` · `bin/gates/ci-verify.sh` ·
`bin/gates/checks/public-data-ward.test.sh` · `bin/records/developers.sh` · `RULES/04-hoard.md` · `docs/fixes/**` (13
redacted)
