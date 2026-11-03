## snotra · 2026-10-23 — the approval gate was not in the tree, and the raw verb did not exist

### Files
- `bin/time/snotra/snotra-approve.sh` (was **untracked** in the main checkout — now in the tree)
- `bin/time/snotra/mail-send.sh` (`raw <draft-id>` — the bytes an approval hashes)
- `bin/time/snotra/snotra-letter.py` (`send --person` / `--to`; a failed send is reported, not counted)

### What was wrong
- **The approval door existed only as an untracked file.** `snotra-letter.sh send` depends on
  `snotra-approve.sh`, and `git cat-file -e origin/main:…` proved it was **not on main**: a fresh clone could
  not have sent a letter through the gate at all, and the guard that stopped the 2026-10-23 incident lived on
  one machine only.
- **`snotra-approve.sh` hashes `mail-send.sh raw <id>` — and `raw` did not exist.** So "approved" could not be
  proven: the gate would have failed closed (correctly) on every letter.
- **`send` had no way to send one letter.** A test was therefore all-or-nothing: three letters or none.

### What now stands
- `mail-send.sh raw <draft-id>` — the draft's exact RFC822 bytes, base64url-decoded, read from Gmail
  (`format=raw`) and passed through a **file**, not argv: with five attachments the draft is ~400 KB and
  "argument list too long" is a failure a mail door must not have.
- `snotra-approve.sh` is now tracked, so the hash-bound approval travels with the repo.
- `snotra-letter.sh send <dir> --approved --to <email>` (or `--person "<name>"`) sends exactly one letter.

### Measured — the first letter sent through the gate
```
approved  r-5050758689714317056   sha fcd5507d…
check     approved
sent      <the operator> → <the operator's address>   (the operator's own address, on his word)
status    Lars-<the operator>: sent · Reygan: draft · Craig: draft
```
One letter left the house; the other two stayed drafts, which is the point of `--to`.

**2026-11-03 (correction, appended):** the operator's name and address were redacted from this note. They are personal data: they belong in the home, and a public fix note may say *the operator* and nothing more (RULES/04, RULES/06 — the correction is recorded, not the leak).
