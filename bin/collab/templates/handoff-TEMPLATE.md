# Handoff — <from> → <to>

**Date:** <ISO date>
**Branch:** `<branch>` · **Commit:** `<sha>` · **PR:** <number or "none">
**Deployed:** <url and the build it runs, or "not deployed">
**For:** <the person who reads this, by name, and their role in the business>

> Write this for a **business reader**: the client who owns the product, the partner whose name is on the
> contract, the accountant, the new developer on their first day. Plain English, full names, no internal
> codenames. The reader does not have our tooling and does not work inside our hall.

## 1 · Where we are

Two or three sentences a non-engineer can follow. What the product is, who it is for, what state it is
in today, and the one thing a reader must understand before touching anything. Name the company and the
product in full; name anyone mentioned as they appear on the contract, not by an internal nickname.

## 2 · What is done

- the result, and how a person can see it for themselves — a screen, a report, a command and what it prints
- what it cost or what it saves, when that is the point (money with its currency, hours, tickets)

## 3 · What is next

- the next action, in order, with the ticket number that owns it, and what it unblocks for whom

## 4 · What is blocked, and on whom

- the decision, signature or credential, and the person who owns it — one name per line

## 5 · How to verify the current state

```sh
# the exact commands a stranger runs to see what this handoff claims
```

## 6 · Read first

- the three documents to read, in order, with one line each on why — and whether any of them is written
  for an engineer or for the client

## 7 · Traps

- what cost the last hand time: a stale cache, a port, a mutation, a line in a document that is no longer
  true — say what a person will see, not what failed internally
