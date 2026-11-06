# 2026-11-06 — the handoff is written for a business reader

**Component:** collab (Vingólf) · **Doors:** `bin/collab/templates/handoff-{README,TEMPLATE}.md`,
`bin/collab/templates/handoff-check.py` · **Plan:** none — asked for by the Allfather in the hall

## The word

*"we need to have handoffs in business language — not the house repos are for more people than ymir users.
we need to append this to ymir's logic for handoffs."*

## Why

The baton shelf was written for a hand inside the hall: it called itself a baton, addressed "the Allfather",
named seats and personae, and assumed the reader had plans, runes and a Ymir seat. The repositories it is
installed into are **not** the house's. Control Tower is Inmost Invest's product, read by the client who owns
it, by Reygan Assareh and by whoever joins next; a partner or an auditor may open `handoff/CURRENT.md` with no
Ymir and no glossary. A handoff that says "Brokk dispatched an Eindri" is not a handoff to them — it is a
sentence in a language they were never taught, about work they cannot see.

## What changed

- **`handoff-TEMPLATE.md`** carries a `**For:**` line — the person who reads it, by name and role — and the
  seven section headings are untouched (the check reads them; renaming a heading breaks every repository that
  already has a shelf). The guidance under each heading now says what a business reader must be able to see:
  the result and the command or screen that proves it, the money with its currency, the blocker and whose it
  is, plain names as the contract carries them.
- **`handoff-README.md`** gains an appended law (six rules) and a "say this, not that" table: what the house
  says inside, what a client reads instead. The word *baton* stays in the shelf's own documentation; the
  document a reader opens says **handoff**.
- **`handoff-check.py`** refuses two things it used to allow: a baton with no `**For:**` line, and the house
  personae (`Allfather`, `Brokk`, `Eindri`, `Galdr`, `Sága`, `Hlidskjalf`, `Mímir`, `Muninn`, `Huginn`,
  `Yggdrasil`, `Utgard`, `Bifrost`, `runes`, `the well`) — each reported with its line number, each waivable
  in writing **on the line it waives** with `allow-house-word: <why>`, the same shape as every other waiver in
  this house. `Ymir` itself is deliberately **not** on the list: naming the tool is honest, naming the hall is
  not.

## Proved

Three batons written from the new template and run through the new check with nothing but python3:

- a clean one → `complete, dated, fresh, and every path it names exists`, exit 0;
- one whose section 1 said *"Brokk dispatched an Eindri and the Allfather sealed the merge"* → three findings,
  each naming the line and the word, exit 1;
- the same sentence with `allow-house-word: the seat's own record` on that line → exit 0.

Not proved: an existing repository's baton re-checked under the new rules. Growth Agent and InvestReady carry
the older copies and the older check, so they keep passing until their shelf is refreshed — which is the
reason the change is additive rather than a rename.

## What was NOT done

- **The seven headings were not renamed.** The check matches them literally and three repositories already
  carry them; a rename is a migration, and it would break a client repository's passing gate on the day we did
  it.
- **No jam in the client's shelf.** Control Tower's copy was refreshed from these templates in the same
  errand, and its baton was rewritten in business language; its history in `handoff/log/` was left untouched.
