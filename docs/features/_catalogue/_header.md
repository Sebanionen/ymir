# FEATURES — what Ymir does

The **master list of Ymir's features and functions.** One row per feature: what it
is, what it gives you, and how to use it.

**This file is WOVEN (Rule 06 · Þættir, plan 174).** It is generated from
`docs/features/_catalogue/` — the header and one fragment per section — and must
never be hand-edited. A feature lands → its row is added to the section fragment
it belongs to, then `bin/records/weave-features.sh` weaves the file. A feature
changes → its row is corrected by a NEW row or a note citing the old one; rows are
never silently rewritten away. A merge conflict on this file is answered by
re-weaving (the `merge=regenerate` driver), never by hand. The list grows for the life of the project —
*"we can do so much"; this is the ledger of it.*

**`how-to`** points at the plain-language page under [`docs/features/`](docs/features/)
when one exists. **A feature with no page is a feature no user can use** — a blank
`how-to` is a debt, not a default. Agents: when you ship a user-facing feature, add
its row here and write its page (see `AGENTS.md` → *Feature how-tos*).

---
