# The record — the only source, the folder, and what honesty is written down

Everything else in Snotra is rendered from one file: `<meeting>/record.json`. If a fact is not in it, no card,
agenda line or letter may contain it.

## The shape

```jsonc
{
  "meeting": {
    "meeting_id": "M-20261022-sync-reygan-craig",
    "title": "Sync — Reygan, Craig",
    "started_at": "2026-10-22T23:18:00+03:00",
    "ended_at":   "2026-10-23T02:07:00+03:00",
    "company": "synteon",              // → which place profile decides the shape
    "place": "documentation",
    "chair": "Reygan Assareh",         // who sends the agenda and holds the register
    "conference_url": "https://meet.google.com/fyc-zooa-abr",   // the join key to the bot's store
    "calendar_event_id": "…",
    "classification": "confidential",
    "coverage": {                      // MANDATORY — a record that cannot name its source is refused
      "audio_source": "the meeting's OWN stream, recorded by the bot as a participant",
      "is_meeting_stream": true,
      "recorded_from": "…", "recorded_to": "…",
      "missing_before": "none",
      "diarisation": "by track (speakerIndex: 3 tracks)"
    }
  },
  "participants": [{ "name": "…", "email": "…", "role": "…", "present": true }],
  "aliases": { "Isabella Jakobsson": ["Isabella", "Isa", "ESA"] },
  "decisions": [{ "decision_id": "DEC-20261022-01", "statement": "…", "grade": "B",
                  "status": "proposed", "decided_by": null, "approver_pending": true,
                  "reversibility": "costly",
                  "evidence": { "timestamp": "00:04:36", "quote": "…" } }],
  "actions":   [{ "action_id": "ACT-…", "deliverable": "…", "owner": "…", "due_at": "2026-10-24",
                  "definition_of_done": "…", "status": "accepted",
                  "evidence": { "timestamp": "…", "quote": "…" } }],
  "questions": [{ "question_id": "OQ-…", "question": "…", "status": "open",
                  "evidence": { "timestamp": "…", "quote": "…" } }],
  "sources": { "audio_bot": {…}, "transcript": {…} }
}
```

**Every decision, action and question carries evidence** — a timestamp and a verbatim quote. That is what
makes the record arguable rather than authoritative-by-assertion.

## The decision state machine

```
proposed ──accept──► approved      (decided_by = the person; approver_pending = false)
    │
    ├──reject──────► rejected      (decided_by = the person, with --why)
    └──hold────────► held          (a person looked and did not decide yet, with --why)
```

The validator (`.agents/skills/snotra-meeting-outcomes/scripts/meeting-outcomes.py validate`) enforces it:

- a **`proposed`** decision **may** have no approver — `decided_by: null` with `approver_pending: true` is the
  honest state of a register nobody has confirmed;
- a decision that claims to stand — **`approved`, `decided`, `rejected`** — **must** name exactly one person;
- a `proposed` decision that says `approver_pending: false` and names nobody is an error.

> **Why this matters.** On 2026-10-23 the record failed its own validator with 14 errors for telling the truth
> about an unattributed meeting. Honesty must not look like a fault, or the house learns to lie to its own
> gate.

## Promotion — who signed what

`snotra-promote.sh set <dir> <ID> accept --by "Name"` appends one line to `promotions.jsonl`:

```json
{"at":"2026-10-23T16:41:00Z","id":"DEC-20261022-04","kind":"decision","from":"proposed",
 "to":"approved","by":"Lars-<the operator> <the operator>","why":"confirmed at the sync","record":"record.json"}
```

**Append-only.** A second promotion of the same id is a *new* line (`from → to`), so the history of a decision
survives its correction. A machine may propose; only a person may promote, and `--by` is required.

## The folder standard

```
<meeting>/
  record.json  harvest.json  letters.json  promotions.jsonl        the source and its state
  minutes.md  decisions.md  actions.md  questions.md               the rendered set (engine output)
  dependency-map.md  agenda-next.md  followup-email.md  email.md/.html
  record.pdf  cards.json  signoff.md  transcript.md
  briefs/<person>.md        one brief per participant (the engine's)
  letters/<person>.{txt,html,md}   the letter that actually goes out (snotra-letter)
  evidence/                 what the ear wrote, names untouched
    bot/                    the transcript we made from the meeting's own stream + transcribe.json
    hand-built/             withdrawn improvisations (a second letter, a test report) — kept, never deleted
  README.md  PROVENANCE.md  what this meeting is · who made each file and from what
  trello.json  dispatch.json  signoffs.json  planner.json  classification.yaml  timestamp/  access.jsonl
```

`systems/snotra/services/record/snotra-layout.sh check` refuses anything else at the top level. `apply` moves a stray into
`evidence/hand-built/` and writes a line into `PROVENANCE.md`. **Nothing is deleted (Rule 11).**

## Coverage — the honesty block

A record **must** say what it heard. The three allowed answers:

| source | `is_meeting_stream` | example |
|---|---|---|
| the bot, as a participant (per-participant tracks) | **true** | the 22 Oct sync — 682 chunks, 2 h 50 min, 3 speaker tracks |
| the call's output through a monitor/loopback | **true** | complete for the far side; near/far separable as two channels |
| speaker turns on the meeting's audio (`-tdrz`) | **true** | turns, not names — a human names them |
| **a room microphone** | **false — refused** | Rule 33: a microphone hears a room, not a meeting |

A record whose source is not the meeting says so in `coverage`, in the minutes, and **in every letter**, so the
participants can correct it. The 22 Oct record carries both states: the room-mic capture as
`superseded_audio_source`, and the bot's own stream as the source.

## What the record is not

- **not the transcript** — the transcript is evidence; the record is the reading of it, with quotes;
- **not the board** — cards are a projection;
- **not append-only** — it is machine state that a promotion moves; the *history* lives in
  `promotions.jsonl`, the Runes ledger and git.

**2026-11-03 (correction, appended):** the operator's name was redacted — it is personal data and belongs in the home, not in a public repository (RULES/04, RULES/06).
