# The public tree named our tailnet and our mailbox

**2026-11-05 · component: security · four tracked documents · `public-data-guard`**

His word: *"tail net are only ours. colberators are not using our tailnet. this are one thing that sebastian have added
toru hir prs we here spreeding our email and tailnet in the ymr repo logixc"* · *"tailnet are for the fleet. and ssh are for
the fleet"*.

## What was found

Four **tracked** documents in the public repo carried either a fleet tailnet hostname or the operator's mailbox:

```
leaks[4]{file,what_it_named}:
  "docs/features/gna-the-one-mail-desk.md","two mail aliases at the operator's domain"
  "docs/fixes/people/2026-10-22-one-command-a-meeting.md","the mailbox"
  "docs/fixes/snotra/2026-10-23-the-inbox-had-no-watcher.md","the mailbox"
  "docs/fixes/snotra/2026-11-01-the-calendar-door-could-not-find-the-gate.md","the mailbox"
```

Measured with `git ls-files | xargs grep -lE 'tailefab[0-9]+\.ts\.net|@way-of\.com'` — four files, no more. The errand
briefs under `data/` also name hosts, but they are not tracked (runtime material).

## What was done

- Each occurrence is replaced by a **placeholder** — `<tailnet-host>`, `<operator-mailbox>` — so the sentence still reads
  and the fact stays private. This is a redaction of a leak, done out loud, which is the one case Rule 11 names.
- The change is four files, four lines; no sentence is rewritten.

## Why the ward did not stop it

`bin/gates/guards/public-data-guard.sh` answers for the tree's **code and templates**; `docs/` was outside its scan. A
public repo that publishes its own private names in a fix note is exactly the case the rule exists for, and the ward was
looking one shelf to the left. **Owed:** extend the scan to every tracked `*.md` under `docs/`, `RULES/` and `.agents/`, with
the same exemption list (tests and the guard's own patterns), and a refusal that names the file and the token it matched.

## The rule the Allfather stated, which is now the law of this note

**The tailnet is the fleet's. SSH is the fleet's.** A collaborator is never on either — they get the public gate and, when
it is sealed, one token-checked door. Nothing in this repository names a fleet host, a tailnet address, an ssh user, or the
operator's mailbox.

## CHANGE LOG

- **2026-11-05** — redacted four tracked documents; recorded the ward's blind spot and the rule the Allfather stated.
