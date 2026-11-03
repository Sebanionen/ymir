## snotra · 2026-10-23 — the letters went out; nothing was reading the answers

### Files
- `bin/time/snotra/snotra-mail-watch.{sh,py}` (new — status · check · record, read-only)
- `bin/time/snotra/snotra-letter.py` (already sent the record-cited letter)
- `docs/snotra/the-letters.md`

### What was asked, and what was true
The Allfather: *"are we watching the emails that ymir and I have? so we know if they are answering? are any agent
taking care of my email inbox incoming?"* — and he pasted the paragraph he had received:

> *"Confirm or correct this record by 2026-10-26 (2 business days) … Silence is recorded as provisional
> acceptance, not as agreement."*

**Measured, in that order:**
- that paragraph is from the **first** test message (`08:02 PDT`); the corrected message sent at `08:51 PDT`
  contains **neither** the invented policy nor the wrong date — verified by reading the sent message through the
  Gmail API (`provisional acceptance` → absent; `2026-10-26` → absent; `2026-10-24` → present);
- **the grant can read** (the MCP gmail server cannot — it has no OAuth token — but the house's own vault refresh
  token returns `messages.list → 200` over 201 messages);
- **nothing was watching.** No cron, no door, no agent read the mailbox; `mail-send.sh` can only draft/send, and
  the Vexa mail tables (`mail_seen`, `mail_thread`, `mail_turn`, `mail_cursor`) are all **0 rows**: the schema
  exists, the pipeline never ran. A register that asks for confirmation into an unread mailbox never gets one.

### What now stands
`snotra-mail-watch.sh status|check|record <meeting-dir>` — read-only:
- it matches a thread by **the letter's own subject** and a sender by the **record's participants**; a stranger's
  mail is never attributed to a meeting, and our own sent copy is never counted as an answer (that false
  positive appeared on the first run and is fixed);
- it classifies a reply by the words the letter asked for — `confirm` · `correct` · `question` · `silent` — and
  lists any `DEC-/ACT-/OQ-/RSK-` ids the reply names, because "ok" to a fourteen-decision register is not
  fourteen confirmations;
- `record` appends to `replies.jsonl` and carves one rune. **It never promotes**: a reply is evidence, and
  `snotra-promote.sh set … --by "<name>"` is still the only way a decision becomes approved.

### Measured, immediately after the real send
```
sent   Reygan Assareh → <a personal address>   (approved b7eabab7…, 5 attachments)
sent   Craig Martin   → craig@way-of.com          (approved 798bd333…, 5 attachments)
watch  mail_watch{people:3, answered:0, silent:3}
```

### Owed
A cron entry (`snotra-mail-watch.sh record <dir>` after each letter, or a nightly `--all`), and a decision about
what a confirmation *means*: one reply confirming fourteen decisions is not fourteen signatures — so either the
letter asks for per-id confirmation, or the Allfather promotes on the strength of the reply. That is his call, not
the door's.
