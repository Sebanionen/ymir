## snotra · 2026-10-23 — `bin/assistant/ground.py`: the readers Skírnir was missing

### Files
- `bin/assistant/ground.py` (new — read-only readers, no model)

### Why
A partner was greeted with the owner's name, "what can you do" was refused, a Swedish request went unanswered, and
"have we emailed Reygan, and what was in it?" had no answer — while every fact sat in the house's own files.

### What it answers
```bash
python3 bin/assistant/ground.py who "@JupiterRoyal"     # → Reygan Assareh · @JupiterRoyal · <a personal address>
python3 bin/assistant/ground.py person "Reygan Assareh"  # per meeting: letter draft/sent, filed, replies, read date
python3 bin/assistant/ground.py decisions "agenda"       # the record items matching the words, with ids + status
python3 bin/assistant/ground.py calendar [1d|ISO..ISO]   # free|busy|unknown + the probe's freshness
```
It also carries `apply_for(question, asker, chat)` — the knowledge application: a file in
`hodd/identity/assistant/pending/` and a row in `asks.json`, so a request the house cannot answer becomes a
question for the Allfather instead of a refusal.

### The laws it keeps
read-only, never the mailbox, never the vault · a send is a send only when `letters.json` carries `sent.at` · an
absent file is **not recorded**, never *not sent* · a missing person is **not in the register**, never a borrowed
name · a calendar answer names its freshness · every answer carries `source` (the door) and `read` (the date), so
the surface can cite it (Rule 37).

### Measured tonight
```
who "@JupiterRoyal"     → Reygan Assareh (found: true, telegram JupiterRoyal, email <a personal address>)
person "Reygan Assareh" → M-20261022-sync-reygan-craig: letter draft · filed 3 · replies 0 · read 2026-10-23
calendar 1d             → verdict busy, source cache, as_of 2026-10-23T19:10Z
```

### NOT done, and said plainly
**It is not yet wired into `skirnir.py`.** The module is built and tested on its own; the one-line integration (at
the refusal site: try `ground.who` → `ground.person` → `ground.decisions` → `ground.availability`, and offer the
knowledge application when nothing answers) must land **with the assistant's own test suite green**, not in the last
minutes of a session that has a live partner conversation running. That is the next session's first task.

### Appendix — the projects overview (the Allfather's instruction, same night)

*"and feed Skírnir with overview data off all my projects from Whynot Productions and Way of."*

`ground.projects(<house|id>)` reads `hodd/identity/projects.yaml` (the master registry), resolves each project's
plan ledger by **id, repo name or path** (`ymir-platform` lives under `projects/ymir` — the id is not always the
folder), and counts the numbered plans in that ledger's index. It then generates
`hodd/identity/assistant/approved/projects-overview.md`:

- **23 projects** across Whynot Productions, Way of and the house's own; **2 with a plan ledger** (ymir-platform, 67
  plans, latest 121; command), the rest say **no ledger** — an absent file is not an empty one (Rule 37);
- generated, not hand-typed: `python3 bin/assistant/ground.py projects` regenerates it;
- the page states what he may say (house · path · posture · plan count) and what he may not (a project's
  *decisions* — those come from the ledger and the records reader, never from memory).
