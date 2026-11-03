## snotra · 2026-10-23 — the answers come back: watcher, cron, register, and the shelves an install gets

### Files
- `bin/time/snotra/snotra-mail-watch.{sh,py}` (`status` · `check` · `record` · **`register`**)
- `bin/time/nornir-job-snotra-mail.sh` (new — the nightly sweep over every meeting that sent letters)
- `config/cron.yaml.example` — `@dev 07:10 bin/time/nornir-job-snotra-mail.sh`
- `.agents/migrations/0012-places-shelf.sh` (new — the places shelf + one declared example for an existing home)
- `.agents/skills/galdr-ymirsystem/assets/snotra-meeting-ear.md` (the governed asset, appended: the chain, every
  door, the place contract, and the install/update surface)
- `FEATURES.md`

### Why
The Allfather asked whether all of this arrives through Ymir's **updates and installations**, and said yes to the
cron line and the reply→register path. Both are now in the tree rather than in a session:

- **installation**: the doors ship inside `bin/` (the npm package's `files` includes it); migration
  `0012-places-shelf` gives an *existing* home the `hodd/identity/places/` shelf and one declared example
  (`example/projects`), because until now a fresh install could only ever answer *"no place profile"*;
- **updates**: the governed asset now names the whole chain (it listed none of the new doors — a governed-path
  omission under AGENTS.md's rule that a code change not reflected in its asset is incomplete);
- **the schedule**: `@dev 07:10 bin/time/nornir-job-snotra-mail.sh` — gated to the seat that holds the mailbox,
  because the 2026-09-28 fault was N seats running one machine's crontab N times.

### The reply → register path, measured on a proof record
```
register{decisions:2, answered_by_id:1, confirmed_by_id:1, unnamed_replies:1}
decision{DEC-…-01, grade:A, answer:confirm, person:Reygan Assareh, line:'DEC-…-01 confirmed from my side.'}
decision{DEC-…-02, grade:B, answer:none}
reply{kind:confirm, names_no_id:true, line:'Confirmed overall, thanks.'}     ← NOT counted per decision
--apply → refused without --by: "a machine may propose, only a person promotes"
--apply --by "Lars-<the operator> <the operator>" →
  promoted{DEC-…-01, from:proposed, to:approved, by:…}   promotions.jsonl: why = "reply … from Reygan: …"
```

**The law this proves:** a whole-register "confirmed, thanks" is never fourteen signatures. A decision is promoted
only when the reply names its id, and only by a person; the reply is recorded as the evidence in
`promotions.jsonl`, so the register carries *who said so and on what words*.

### Appendix (same day) — `snotra-dispatch.sh who "<person>"`

The Allfather: *"he should know if we have emailed Reygan, cuz we have — and what was in that email."* The answer sat
in four files and no door read them together. `snotra-dispatch.sh who "<person>"` now prints, per meeting they
attended: the letter's state (`sent at …` vs `draft … · not sent`), what was filed on the board, the count of replies,
the date the state file was last written, the letter's opening line, and the last reply with its kind — read-only, from
the vault, never the mailbox. A send is a send only when `letters.json` carries `sent.at`; an absent file is
**not recorded**, never *not sent* (Rule 37).

**2026-11-03 (correction, appended):** the operator's name was redacted — it is personal data and belongs in the home, not in a public repository (RULES/04, RULES/06).
