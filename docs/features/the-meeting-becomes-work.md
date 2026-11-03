# The meeting becomes work — the harvest, the board, the letters

**What it is.** Four doors that turn a meeting you already had into work that moves: the meeting's **own
audio** is harvested out of the bot's store, the record is **projected onto the boards** of the place the
meeting belongs to, a **letter per participant** carries their own tasks, and the sound is **shrunk after
its words are safe**.

**The full reference is the Snotra shelf: [`docs/snotra/`](../snotra/README.md)** — the pipeline, every door,
the place contract, the record schema, the letters and the sound. This page is the how-to; that shelf is the
specification.

**Why it exists.** On 2026-10-23 the house discovered three faults at once: the meeting folder held the
*laptop microphone* (never the meeting), the bot's own recording sat 155 MB away in a store no door
reached, and 8 191 transcription calls had returned `ok: true` with **no words** — so the folder had no
transcript and nobody was told. Meanwhile a projection wrote only the actions onto a board of its own
choosing, and a letter went out saying "no decisions were taken".

## What you need

- A meeting **with a record**: `record.json` in the meeting folder (the engine writes it).
- A **place profile**: `hodd/identity/places/<company>/<place>/place.yaml` — this is where that company's
  board, list names, labels and cadence live. Synteon's is `synteon/documentation`; Whynot Productions'
  is `whynotproductions/projects`; Way of Teams' declares `surface: gimle`.
- The **board map**: `hodd/identity/trello-map.yaml` (refreshed by `systems/snotra/services/cron/trello-map.sh`).
- The meeting bot's store reachable on this seat (the Vexa stack), and a Trello grant for the card doors.

## The commands

```bash
M=~/Documents/ymirhome/svartalfaheim/synteon/meetings/2026-10-22-sync-reygan-craig

systems/snotra/services/ear/snotra-harvest.sh status   "$M"   # what the bot holds for this meeting
systems/snotra/services/ear/snotra-harvest.sh fetch    "$M"   # pull the audio, verify it byte-for-byte
systems/snotra/services/ear/snotra-harvest.sh verify   "$M"   # re-check it against the store's declaration
systems/snotra/services/ear/snotra-harvest.sh speakers "$M"   # split the capture log by speakerIndex → one WAV each
systems/snotra/services/ear/snotra-harvest.sh signal   "$M"   # audit the STT log; empty text at ok:true is a FAILURE

systems/snotra/services/cron/snotra-project.sh plan     "$M"   # what would be filed, where — no writes
systems/snotra/services/cron/snotra-project.sh apply    "$M"   # create/update, idempotent, verified after write
systems/snotra/services/cron/snotra-project.sh verify   "$M"   # read the boards back and diff against the record

systems/snotra/services/letters/snotra-letter.sh  render   "$M"   # letters/<person>.md + .html — nothing sent
systems/snotra/services/letters/snotra-letter.sh  draft    "$M"   # one Gmail draft per participant
systems/snotra/services/letters/snotra-letter.sh  status   "$M"
# sending needs the operator: snotra-approve.sh approve <draft-id>, then:
systems/snotra/services/letters/snotra-letter.sh  send     "$M" --approved

systems/snotra/services/approve/snotra-promote.sh list  "$M"      # every candidate: proposed · approved · rejected · held
systems/snotra/services/approve/snotra-promote.sh check "$M"      # the engine's validator, before anything is written
systems/snotra/services/approve/snotra-promote.sh set   "$M" DEC-20261022-01 accept --by "Lars-<the operator> <the operator>" --why "confirmed"
systems/snotra/services/approve/snotra-promote.sh log   "$M"      # promotions.jsonl — append-only, who and when

systems/snotra/services/cron/snotra-agenda.sh  plan  "$M"      # the next meeting's points, from the record
systems/snotra/services/cron/snotra-agenda.sh  apply "$M"      # the dated agenda card, in the place's agenda list
systems/snotra/services/cron/snotra-agenda.sh  verify "$M"

systems/snotra/services/ear/snotra-audio-ladder.sh plan  "$M"                 # what would shrink, and by how much
systems/snotra/services/ear/snotra-audio-ladder.sh apply "$M" [--offload DIR] # verify → compress → strip → report

systems/snotra/smoke.sh                                          # the gate: 6 checks, 3 verdicts
```

## Where the shape lives — and why the scripts name no company

The scripts carry **mechanisms**; a **place** carries its shape. Grep proves it: no company, board or
list name appears in `snotra-project.py`, `snotra-letter.py` or `trello_client.py`. Two places, one door:

| place | board | decision list | action list | question list |
|---|---|---|---|---|
| `synteon/documentation` | Documentation | Decided / Resolved | Backlist Actions/Tasks | Open Questions |
| `whynotproductions/projects` | Control Tower | Decided | Project Todos | Open Questions |

A place that asks for another engine is **refused, not cross-filed**:

```
$ systems/snotra/services/cron/snotra-project.sh plan <a wayof meeting>
snotra-project: the place wayof/projects declares surface 'gimle'; this projector speaks trello only —
refusing rather than filing into the wrong engine
```

## The register becomes law — and only a person may sign it

Every one of the 22 October decisions is `proposed` until somebody promotes it. `snotra-promote.sh set`
**requires `--by "<a person's name>"`** — "a machine may propose, only a person may promote" — validates
the record through the engine's own validator first, **appends** the promotion to `promotions.jsonl`
(from → to, by, why, when), writes the state, and **reads it back**. Setting the same state twice writes
nothing. `hold` is a recorded state too: a person looked and did not decide yet, with the reason.

The validator had to learn one thing for this to work: a decision that has not been promoted **may
honestly have no approver** (`status: proposed` + `approver_pending: true`), while any decision that
claims to stand — `approved`, `decided`, `rejected` — still must name exactly one person. Measured
2026-10-23: the record failed its own validator with 14 errors, because honesty about an unattributed
meeting looked like a fault.

## The agenda drives the meeting (DEC-04)

`snotra-agenda.sh` writes the dated card into the place's agenda list (*Next Meeting Agenda* for Synteon),
in the room's own order: what is still **proposed** → **actions due** by that date → **open questions,
last, always**. The date is `--date`, or the place's cadence (the Monday at `monday_at`). Every line cites
its `DEC-`/`ACT-`/`OQ-` id, and the card is idempotent by `record-key`.

## The laws these doors keep

- **The record is the only source.** A decision, action or question that is not in `record.json` cannot
  appear on a card or in a letter.
- **Cards are a projection, never a second truth.** Each card carries `record-key: <meeting>:<id>`; a
  second run updates, never duplicates; a card a human moved is reported as drift and **left where it is**
  (`--move` is the operator's call).
- **No microphone is a record (Rule 33).** The harvest takes the meeting's own stream.
- **No transcript, no shrinking (Rule 30).** The ladder verifies sha and duration before any raw file is
  removed, and never touches text.
- **No agent sends mail.** `send` refuses without `--approved` **and** a valid `snotra-approve.sh` record.
- **The audio does not enter the vault.** Raw sound stages in
  `~/.local/state/ymir/snotra-harvest/<meeting>/`; the vault receives text (`harvest.json`, the
  transcript, the letters).

## The numbers, measured on the first real meeting (2 h 50 min)

| item | before | after |
|---|---|---|
| the bot's audio | 161,665,525 B (154 MiB) | 19,779,897 B (19 MiB, Opus 16 kbps mono) |
| the capture log | 250 MiB (every frame, base64) | 1 MiB (timing + `speakerIndex` kept) |
| the transcript | did not exist | 21,446 words, 2,151 timestamped lines |
| cards | 3 (actions only) | 22 (14 decisions · 3 actions · 4 questions · the meeting) |
| the letters | one, and it said "no decisions" | three, one per participant, drafted |

## Limits

- **Speaker names are not assigned by the doors.** The split gives `speaker-00/01/02`; naming them is a
  review step (the record's `aliases` map plus a human), and until then the letters state that the
  attribution is unconfirmed.
- **One surface only.** Trello is implemented; Gimlé and Jira are refused, not pretended (plans 104/105).
- **The per-speaker WAVs are kept** until a per-speaker transcript exists — they are the only copy of the
  split audio.
- **A second seat needs its own scraper**: the bot's store is reached over its HTTP API, and that address
  is per deployment.

## If it does not work

- `harvest status` says *the bot store is unreachable* → set `VEXA_API_URL` (and `VEXA_USER_ID`).
- `harvest speakers` says *no storage credentials* → set `VEXA_S3_ACCESS_KEY`/`VEXA_S3_SECRET_KEY`, or
  `VEXA_COMPOSE_ENV` to the deployed compose `.env`.
- `project` says *no board matches* → run `systems/snotra/services/cron/trello-map.sh` to refresh the map.
- `project verify` reports **misfiled** → a human moved the card; the door will not move it back.
- `ladder` refuses → there is no verified transcript yet. That refusal is the safety, not a fault.

**2026-11-03 (correction, appended):** the operator's name was redacted — it is personal data and belongs in the home, not in a public repository (RULES/04, RULES/06).
