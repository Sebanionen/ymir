## snotra · 2026-10-23 — the letter obeys the record: the room's date, the room's words

### Files
- `bin/time/snotra/snotra-letter.py` — the ask and the note are **quoted from the record**
- `hodd/identity/places/synteon/documentation/place.yaml` — `roles.operator` (the signer, distinct from the chair)

### What was wrong — seen in the operator's own inbox
The Allfather read the test letter and said: *"is that email following the updates from the meeting we had. I see
things"* and then *"update the machinery … FOLLOW THE MEETINGS RULES"*. He was right on both counts:

| what the letter said | what the record says | fault |
|---|---|---|
| "confirm or correct this record by **2026-10-26** (2 business days)" | `ACT-20261022-03` is due **2026-10-24** | the date was **computed from a cadence** instead of read from the record |
| "Silence is recorded as provisional acceptance, not as agreement." | nothing of the kind exists; the record's own caveat is `RSK-20261022-02` — *"grade and approver are provisional until confirmed"* | **an invented policy** attributed to a room that never agreed to it |
| "Ask Reygan and Craig to confirm…" addressed to Reygan | it is **Lars-<the operator>'s** action, not hers | the recipient was told to ask herself |
| "— **Reygan Assareh**" as the signature | the letter leaves from the operator's mailbox | the chair was signing for the sender |

### What the machinery does now
- **the ask is quoted, never paraphrased**: the record's confirmation action (`ACT-…`, by its own definition —
  deliverable/definition-of-done containing *confirm* or *correct*), with its **owner named**, its **due date as
  written**, and its `definition_of_done` as the completion test;
- **the recipient's own part** is the action's `definition_of_done` — the record's words, not a new demand;
- **the note is the record's risk mitigation, verbatim**, with its `RSK-…` id — and if no risk speaks to
  confirmation, there is **no note at all** (a first attempt printed an unrelated risk; that was caught);
- **the signature is the operator** (`roles.operator`), and the chair is named separately as the holder of the
  register — two roles, two sentences, no confusion;
- wrap() no longer doubles spaces after a label or a quotation mark.

### Measured
```
subject   Sync — Reygan, Craig — your actions and the record · confirm by 2026-10-24
ask       "Ask Reygan and Craig to confirm or correct this record within two business days."
          — ACT-20261022-03, owned by <the operator> · Done when: Both have replied confirm or objection · By: 2026-10-24
note      RSK-20261022-02: grade and approver are provisional until confirmed.
signed    — <the operator>        (Reygan, as chair, holds the register.)
sent      to <the operator's address> only; the other two remain drafts
```

**The law this earns:** *a letter may not contain a sentence the record cannot cite.* Every non-header line in
a Snotra letter is now either the record's own words, its ids, or a neutral label — and a test letter is the
cheapest way to find the ones that are not.

**2026-11-03 (correction, appended):** the operator's name and address were redacted from this note. They are personal data: they belong in the home, and a public fix note may say *the operator* and nothing more (RULES/04, RULES/06 — the correction is recorded, not the leak).
