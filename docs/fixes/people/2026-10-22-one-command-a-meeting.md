## people · 2026-10-22 — the doors worked; the address book was empty

**His question:** *"audit how easy it is for us to send emails to our people … and set up google meet … can we do
some simpler?"*

```
audited[4]{thing,state,measured}:
  "the calendar write door","`bin/time/snotra/calendar-invite.sh create --title --start --end [--attendees] [--meet]`","`calendar_write: ready` — the grant refreshes and Google sends the invitation itself when an attendee is on the event"
  "the mail door","`bin/time/snotra/mail-send.sh draft|send --to --subject --body FILE` — a DRAFT by default, `send <id>` to release it","`gmail: ready`"
  "the address book","`hodd/identity/collaborators.yaml`","**three of four people had NO email** — Andre only. The capability was ready and the book was empty"
  "the interface","ISO timestamps, a comma-separated attendee list, a body FILE","a developer's interface for something a person says in a sentence"
```

**So: one command instead of three.** `bin/people/meet.sh`:

```sh
bin/people/meet.sh --with craig --at "friday 10:00" --for 45 --title "WayOf — phase two" [--note "…"]
bin/people/meet.sh --with craig --at "fri 10:00" --dry-run      # show it, create nothing
```

It resolves the address from the registry (`craig` finds `craig-martin` — nobody types a slug), reads
the time the way a person says it (`fri 10:00`, `tomorrow 14:00`, `2026-10-30 10:00`), creates the event
with a **Meet link**, and — only if `--note` is given — prepares a **draft** email, never a send.

**And the missing half, made visible:** `bin/people/who.sh missing` lists exactly who cannot be reached —
*"reygan, isabella, craig"* — and `who.sh set-email <id> <address>` fills one. Craig's address was
recovered from his own record of this morning's meeting (<operator-mailbox>) and written once.

**Still missing, and it is not code:** Reygan's and Isabella's addresses. Until they are in the registry,
no invitation and no mail can reach them, and the door says so in one line rather than failing obscurely.

**Verified:** `meet.sh --dry-run` for Craig resolves the address and the exact ISO window
(`2026-10-23T10:00:00 → 10:45:00`); for Isabella it names the one thing missing and the command that fixes
it. No live event was created — that is the Allfather's word, not a test.
