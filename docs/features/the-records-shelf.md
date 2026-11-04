# The records shelf — plans, notes, headers, grades, placement, and the weaver

## What it is

The doors that keep the home's written record honest. Six of them, in the order you
will reach for them: the **plan ledger** (the next number, never reused), the
**append-only note** (a dated section onto a document that already exists), the
**declared header** (what a document claims it is, and when it was proved), the
**Norse grade** (how fresh it is, from measurable signals only), the **placement
oracle** (which shelf a file belongs on, before you file it), and the **weaver**
(which regenerates the generated lists and checks that every index still names its
own files).

All six answer the same law: **the record is appended to, never rewritten, and
never filed by guess.** A correction is a new entry citing the old one; an old
document *moves* to `hodd/reference/`, it is never deleted (Rule 11).

## What you need

- Ymir installed, with a home (`$YMIR_HOME`) — every door resolves it through
  `bin/vault/hodd.sh path`, never by guessing a path.
- `python3` and `pyyaml` for the placement oracle.
- For the plan ledger: a ledger shelf at
  `$YMIR_HOME/svartalfaheim/<realm>/projects/<project>/plans/`, with a `README.md`
  index in it. Ymir's own lives under `svartalfaheim/<realm>/projects/<project>/plans/`.

## Do it

### 1. The plan ledger — `bin/records/plan.sh`

Which number comes next, and what the ledger already holds:

```bash
bin/records/plan.sh next
bin/records/plan.sh list | head -5
```

`next` prints one bare number; `list` prints the ledger's own index rows, newest
last:

```
179
#68 <title of plan 68>
#69 <title of plan 69>
```

Open a plan. This creates the file **and** its index row in one motion, so a plan
never exists without being findable:

```bash
bin/records/plan.sh new my-slug --title "What this plan is for"
bin/records/plan.sh new my-slug --title "…" --realm work --project ymir
```

It prints `created <path>`. The number is taken **after the highest in the index**
and is never reused, so a deleted plan leaves its number dead rather than handing it
to the next idea.

### 2. The append-only note — `bin/records/note.sh`

A dated section, appended whole, onto a document that already exists:

```bash
bin/records/note.sh hodd/docs/INDEX.md "## Correction (2026-11-04)" "The shelf moved; the old row cites this one."
```

It prints `appended to <doc>`, and a `---` rule separates the new section from what
was there. It **cannot** create a document — a note is a correction, not a new page.
If the path does not exist you are told, and nothing is written.

### 3. The declared header — `bin/records/header.sh`

Every home document may declare what it is, so nothing has to be inferred from its
file mtime:

```
kind · status · verified · verified_by · supersedes · superseded_by
```

```bash
bin/records/header.sh check hodd/docs/INDEX.md
bin/records/header.sh check hodd/docs          # a shelf
```

```
no header: hodd/docs/INDEX.md
header: 1 document(s) without a header
```

To give one a minimal header (it never overwrites a header that is already there):

```bash
bin/records/header.sh apply hodd/docs/INDEX.md
```

`apply` prefixes `kind: note`, `status: live`, `verified: declared`,
`verified_by: <today>`, and `supersedes/superseded_by: none` — a starting claim you
are expected to correct, not a truth the machine invented.

### 4. The Norse grade — `bin/records/grade.sh`

Dellingr's craft: how fresh is this document? The grade comes from measurable
signals only — the last change, whether the document declares a successor, and
nothing else.

| grade | meaning |
|---|---|
| `nýr` | fresh — inside the `--eldri` window |
| `eldri` | aging — past `--eldri` days (default 90) |
| `forn` | old — past `--forn` days (default 365) |
| `safn` | archive — the document declares a `superseded_by` |

```bash
bin/records/grade.sh hodd/docs/INDEX.md
bin/records/grade.sh hodd/docs --eldri 30 --forn 200
```

```
nýr      0d  hodd/docs/INDEX.md
```

A grade decides **where something belongs**, never whether it survives: an old
document moves to `hodd/reference/`; nothing is deleted for being old.

### 5. Where a file goes — `bin/records/layout.py`

Ask before you file, so nothing is placed by guess.

```bash
python3 bin/records/layout.py classify hodd/docs/runbooks/thing.md
python3 bin/records/layout.py find-home /tmp/some-runbook.md --note "a recovery runbook"
```

```
hodd/docs/runbooks/thing.md
  legal: True
  shelf: hodd/docs/runbooks/
  because: a home document that belongs on hodd/docs/runbooks/
```

```
/tmp/some-runbook.md
  destination: hodd/docs/runbooks/some-runbook.md
  because: a name/subject match on hodd/docs/runbooks/
```

A path inside the home that sits on no legal shelf is refused, loudly, and told
where the shelves are:

```
  legal: False
  because: it is inside the home but on no legal shelf — file it under hodd/docs · hodd/life/<domain> · hodd/plans · hodd/data · hodd/identity · hodd/memory · hodd/reference
```

Move a file in (it is a `git mv`, so the home's history shows a rename, not a
delete-and-add), bring material in from outside, and look at the shape of the home:

```bash
python3 bin/records/layout.py place hodd/docs/runbooks/thing.md --why "it is a recovery runbook"
python3 bin/records/layout.py import ~/Downloads/report.md --dry-run
python3 bin/records/layout.py import ~/Downloads/report.md --area reference
python3 bin/records/layout.py structure
python3 bin/records/layout.py index hodd/docs
```

`classify` and `find-home` are read-only — safe to ask any time. `place` and
`import` are the write actions: they refuse a path the layout law cannot justify,
and `--dry-run` shows the destination without moving anything.

### 6. The weaver — `bin/records/weave.sh`

Some documents are **woven**: `FEATURES.md`, `bin/README.md`, the capability
registers. They are generated from fragments and must never be hand-edited. Other
documents are **indexes**: hand-kept prose whose rows name every plan, every rule,
every feature page. A row is a hand's work; a missing row is a page no user finds.

```bash
bin/records/weave.sh --check
```

```
indexes: agree
```

When it does not agree, it names the gap and gives you two doors:

```bash
bin/records/weave.sh --fix          # APPEND the rows a plan or a rule is missing (never a rewrite)
bin/records/weave.sh --fix-count    # the rules index count only
bin/records/weave.sh                # weave what can be woven, then check every index
```

The feature catalogue has its own weaver, because `FEATURES.md` is edited by every
feature branch at once:

```bash
bin/records/weave-features.sh           # regenerate FEATURES.md from docs/features/_catalogue/
bin/records/weave-features.sh --check   # exit 1 when it is stale
bin/records/weave-features.sh --install # seat the merge driver for this clone
```

A new feature adds **its own fragment** under `docs/features/_catalogue/entries/`
(one file per row, so two branches never collide) and then runs the weaver.

### 7. The ward — `bin/gates/guards/features-guard.sh`

The ward that makes the shelf trustworthy: a page under `docs/features/` that the
catalogue does not name is a page nobody finds, so the wardrobe refuses it.

```bash
bash bin/gates/guards/features-guard.sh
```

```
features-guard[3]{finding,page,catalogue}:
  "none","","every feature page is catalogued, and the woven catalogue is current"
```

It also fails when the woven catalogue is stale or when the merge driver is not
seated — a gate that can be satisfied by a hand-edited file is not a gate.

## Notes & limits

- **Rule 14 is the law behind all of this:** a user-facing door without a page here
  is not finished, and the page must be in the catalogue. Building the door is half
  the work; the row and the page are the other half.
- `note.sh` appends and does not read back. If you need certainty that a long body
  landed, `grep` your heading afterwards — the house has been bitten by an append
  that reported success and wrote two blank lines.
- `header.sh apply` walks up to 400 documents under the path you give it. On a large
  shelf, name one directory at a time and read what it prints.
- `grade.sh` reads the file's mtime and its own declared header. A document copied
  or restored gets a fresh mtime and therefore a fresh grade — the grade is a
  measurement, never a memory.
- `layout.py` knows the shelves that exist today; a new shelf that the map does not
  carry is a change to `bin/records/layout.py`, not a rule you can talk your way
  around.
- `weave.sh --fix` only ever **appends** rows. It will not correct a wrong row, and
  it will not touch prose — a wrong row is corrected by hand, citing the old one.

## If it does not work

**`plan: no home (bin/vault/hodd.sh path answered nothing)`** — the home is not
resolvable from this shell. Run `bin/vault/hodd.sh path` on its own; it must print a
directory. If it does not, the environment is the fault, not the ledger.

**`plan: no ledger for work/ymir`** — the door looked under
`svartalfaheim/<realm>/projects/<project>/plans` and `…/workspace/<project>/plans`
and in neither place found a stack of numbered plans. Create the shelf with a
`README.md` index in it, or point at another project with `--project`.

**The weaver says a page is not catalogued** — add the fragment under
`docs/features/_catalogue/entries/` in the shape the neighbours use (`section:` in
the front matter, one markdown row in the body), then run
`bin/records/weave-features.sh`. Never edit `FEATURES.md` by hand; it is rewritten
from the fragments and your edit will vanish.

**The weaver says a plan or a rule has no row** — `bin/records/weave.sh --fix`
appends the missing rows. Read the appended rows afterwards: the title is taken from
the file's first heading, so a plan with a vague first line gets a vague row.

**`indexes: agree` but a document is still unfindable** — the weaver checks
completeness, not wording. A row that names the file in the wrong words is a row the
weaver cannot judge; open the index and fix the sentence by hand.

## Proven on this machine, 2026-11-04

Run from the worktree, in this order, with these answers:

```
bin/records/plan.sh next                 → the next free number (one bare integer)
bin/records/plan.sh list | head -5        → the newest ledger rows, `#<n> <title>`
bin/records/note.sh --help                → the four usage lines
bin/records/header.sh check hodd/docs     → the count of documents under that shelf with no header
bin/records/grade.sh hodd/docs/INDEX.md   → "nýr      0d  hodd/docs/INDEX.md"
layout.py classify hodd/docs/runbooks/thing.md → legal: True, shelf: hodd/docs/runbooks/
layout.py classify hodd/random/thing.md        → legal: False, and the shelf list
layout.py find-home /tmp/some-runbook.md       → destination: hodd/docs/runbooks/some-runbook.md
layout.py structure                            → bin/ (17 files) · data/ (117) · docs/ (342) …
layout.py index hodd/docs                      → no empty dirs
weave.sh --check                          → indexes: agree
weave.sh --fix-count                      → rules index: 40
weave-features.sh --check                 → FEATURES.md is current (157 entries)
features-guard.sh                         → "none" — every feature page is catalogued
```

`place`, `import`, `header.sh apply`, `note.sh <doc> …` and `plan.sh new` are the
write actions and were **not** exercised against the home in this run: they write
outside this worktree. Their read-side twins above were.

Most documents in a working home carry no header yet — that is a real debt the door
reports by count, not a defect in the door, and `apply` is how it is paid down one
shelf at a time.
