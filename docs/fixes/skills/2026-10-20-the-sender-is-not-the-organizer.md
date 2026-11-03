## skills · unversioned · 2026-10-20 — the sender is not the organizer

### What

The follow-up email signed "Kind regards, a participant" because it used
`meeting.organizer` — who ran the meeting — as the signature. The Allfather sends the
follow-up: **the operator**. The record now carries `meeting.sender`, rendered in
the signature (falling back to organizer), and the schema allows it.

The pilot record was regenerated: participants and action owners use the full name
`the operator`, and the per-person brief is `briefs/<the operator>.md`.

### Verified

- Re-ran the pipeline on the 158-minute export: 6 decisions, 16 actions, 0 warnings.
- `followup-email.md` ends `Kind regards, the operator`.
- Four briefs, one per participant, with the corrected slug.

### Not verified

- No test asserts the signature yet; add `sender` to the render test.

**2026-11-03 (correction, appended):** the operator's name and address were redacted from this note. They are personal data: they belong in the home, and a public fix note may say *the operator* and nothing more (RULES/04, RULES/06 — the correction is recorded, not the leak).
