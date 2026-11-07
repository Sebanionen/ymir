# The place — where a company's shape is declared

A **place** is one company's working surface: a board, the lists things are filed into, the labels that mean
something, the cadence of its meetings, the roles, and how long its sound may live. It lives in one file:

```
hodd/identity/places/<company>/<place>/place.yaml
```

**Why a file and not code:** Synteon's meeting decided its board's shape (graded decisions, layered boards,
the agenda as driver, reusable templates). Inmost Invest or Whynot Productions may want something else
entirely. A door that carries one company's shape applies it to every company — so the shape is data, and
the doors read it. **No company, board or list name appears in `systems/snotra/*.py`.**

## The contract

```yaml
version: 1
place: synteon/documentation
company: synteon
surface: trello            # trello | gimle | jira — a door that does not speak it REFUSES
board: Documentation       # resolved by NAME through trello-map.yaml, never a typed id
inherits: house-default

authority:                 # every field either cites the decision it comes from, or is a house default
  decisions: [DEC-20261022-01, -03, -05, -07, -08, -11, -14]
  meeting: M-20261022-sync-reygan-craig

lists:                     # where each kind of thing is filed (real list names, quoted not corrected)
  decision: "Decided / Resolved"
  action:   "Backlist Actions/Tasks"
  question: "Open Questions"
  agenda:   "Next Meeting Agenda"

labels:                    # grade → colour; created on the board if missing
  "Grade A": red
  "Grade B": orange
  "Grade C": green
  "Question": sky

meeting_card:              # one card per meeting on the company's meetings board
  board: "Synteon — Meetings"
  list:  "Meetings"

roles:
  chair: "Reygan Assareh"  # sends the agenda 1–2 days ahead (DEC-04); holds the register
  operator: "Lars-<the operator> <the operator>"

cadence:
  agenda_lead_days: 2
  signoff_business_days: 2
  monday_at: "09:00"
  record_within_minutes: 15

retention:
  audio_days: 24           # Rule 30: audio is ephemeral, the text is the record
  compression: "opus-16k-mono"
  cold_shelf: "external-drive"

never:                     # laws, not preferences — the doors quote these
  - "a computer microphone is never the record (Rule 33)"
  - "no email is sent without the operator's approval"
  - "a card a human moved is never moved back by a projection"
```

## The three that exist

| place | surface | board | decision list | action list | question list | agenda list |
|---|---|---|---|---|---|---|
| `synteon/documentation` | trello | Documentation | Decided / Resolved | Backlist Actions/Tasks | Open Questions | Next Meeting Agenda |
| `whynotproductions/projects` | trello | Control Tower | Decided | Project Todos | Open Questions | Weekly Updates |
| `ymir/projects` | trello | **Ymir** | Decisions | Doing | Open Questions | Agenda |
| `wayof/projects` | **gimle** | — | — | — | — | — |

## The house's own board (`ymir/projects`)

Ymir is not a customer, so its authority is not a DEC register — it is the **plan ledger and `RULES/`**, cited
in the profile. Its board was created by a door, not a hand:

```
$ snotra-board.sh ensure ymir/projects
board{name:Ymir,id:6adb7bae165a8594de1103ac,created:true,org:6ad238393bae14df5e25c980}
list{name:Decisions,created:true} · Doing · Open Questions · Agenda
label{name:Plan,blue} Rule,purple Fix,orange Guard,red Skill,green Blocking,black
map{refreshed:true}
verify{board:Ymir,lists:4,missing:[],ok:true}
```

Its first card is **“How this board works — read me first”** (Agenda, pinned top) carrying the house emblem as
its cover — the bronze world-tree — and the laws of the projection written on its back. `record-key:
ymir/board:INTRO` makes it idempotent like every other card.

**A declared board is executable.** `snotra-board.sh check <place>` asks whether the board, its lists and its
labels exist; `ensure` creates only what is missing, finds an unmapped board by name inside the organisation
before creating anything (the duplicate "Control Tower" of 2026-10-22 is why), and refreshes the map. The smoke
now checks **every** place's board, and it found two real drifts on the first run: Documentation was missing
the `Blocking` label, and Control Tower was missing every grade label its profile names.

## The proof that the shape is not in the code

Same door, two places, **no code change**:

```
$ snotra-project.sh plan /tmp/proof-wnp            # a Whynot meeting
would-create decision DEC-TEST-01 → Decided
would-create action   ACT-TEST-01 → Project Todos
would-create question OQ-TEST-01  → Open Questions
would-create meeting  MEETING     → Weekly Updates
```

And the refusal, which is the point of declaring a surface at all:

```
$ snotra-project.sh plan /tmp/proof-wayof          # a Way of meeting
snotra-project: the place wayof/projects declares surface 'gimle'; this projector speaks trello only —
refusing rather than filing into the wrong engine         (exit 1)
```

**A place on another surface is served by nothing until its adapter exists** — that is honest, and it is why
a Gimlé or Jira board is never polluted with Trello-shaped cards.

## Adding a company

1. `hodd/identity/companies.yaml` — who they are, their realm, their paths.
2. `hodd/identity/places/<company>/<place>/place.yaml` — the contract above. Cite decisions where they
   exist; `authority.decisions: []` means "every field is a house default", and that is allowed but must be
   stated.
3. `systems/snotra/services/cron/trello-map.sh` — refresh the map so the board and list names resolve.
4. `systems/snotra/services/cron/snotra-project.sh plan <a meeting>` — read it before writing anything.
5. `systems/snotra/smoke.sh` — the last check asserts every place declares a `surface` and an `authority`.

## What a place may not do

- **Invent a board.** A board that is not in the map is an error, not a creation.
- **Rename a list silently.** The profile quotes the real name (the Documentation board's `Backlist` is the
  board's own spelling) — a door that "fixes" a name files cards nowhere.
- **Cross a restricted place.** `never:` is quoted by the doors; a crossing needs a decision, not a config.

**2026-11-03 (correction, appended):** the operator's name was redacted — it is personal data and belongs in the home, not in a public repository (RULES/04, RULES/06).
