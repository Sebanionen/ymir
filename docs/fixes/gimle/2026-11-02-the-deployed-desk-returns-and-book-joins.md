# The deployed desk returns to the repo, and Book joins the places

**Date:** 2026-11-02 · **Component:** gimle · **Found by:** measuring the heart instead of the repo

## What was wrong

`/home/zerwizserver/gimle/desk/desk.py` on the heart was **newer than the file in this repository** and
`/home/zerwizserver/gimle` is **not a git checkout at all**. The deployed copy carried three things the
repo did not have:

- `plane_reader.py` — the Board read face, which draws the cards assigned to a person straight from Plane;
- `places_for()` — the default-deny membership gate, so a person not named in `places.json` sees nothing
  and only the operator (named by `GIMLE_OPERATOR`) sees every place;
- the **From the board — assigned to you** section, and the removal of the Email and Social tiles.

So the only copy of the desk's newest logic lived on one box, with `.bak-` files beside it as its history.
Rule 01 asks for an artefact; git is the artefact. A deployment is not a version.

## What changed

1. `bin/gimle/desk.py` — the deployed file, brought into the repository as it stands (membership gate,
   board section, tiles), plus one addition below.
2. `bin/gimle/plane_reader.py` — added, so the desk's board reading is versioned beside the desk.
3. **Book is now a place on the desk.** `book.zerwiz.org` is Cal.com: one booking page per member, so a
   counterpart picks a free time without an account in the hall.

## Why Book belongs on the desk and not behind the gate

A booking link exists to be given to someone who is **not** inside. The public side — a member's own
booking page — must stay reachable without the gate. The administrative side (sign-in, event types,
settings) is what belongs behind Authelia. Putting the whole hostname behind forward-auth would mean the
only people who can book are the people who already have an account, which defeats the door.

## How it was checked

- `python3 -c "import ast; ast.parse(...)"` on both files — syntax clean.
- The deployed desk answers `200` on `127.0.0.1:8487` with a `Remote-User` header; Plane answers `200` on
  `127.0.0.1:8099`; `/manual.html` through the door answers `200` (the footer link is not dead).
- The tile is a link, so it cannot break the desk if Cal.com is down — the desk keeps rendering.

## What is still owed

- **The people map was hoarded out of the code.** The deployed reader carried six private e-mail addresses as
  Python literals — a public-repo violation the `public-guard` caught on the first attempt to commit it. It now
  reads `~/gimle/desk/etc/people.json` (`GIMLE_PEOPLE_FILE`), which lives on the heart with the token. That file
  must exist before the board section can map a person: a flat JSON object of `person: email`.
- **The Plane token is not missing, it is unhoarded.** It lives at
  `/home/zerwizserver/gimle/desk/etc/plane-token`. `ymir_secret_keys PLANE` reports nothing because the vault knows
  no such key; moving it into `hodd/secrets/platform.env` is a decision, not a cleanup.
- Cal.com holds **one** user (username `<the operator>`), 4 event types, 0 bookings, a Google calendar credential, a Google
  video credential, and no teams. Per-member booking places are the Allfather's call: each person gets a Cal.com
  user (or a team with round-robin) before their link is real.

**2026-11-03 (correction, appended):** the operator's name and address were redacted from this note. They are personal data: they belong in the home, and a public fix note may say *the operator* and nothing more (RULES/04, RULES/06 — the correction is recorded, not the leak).
