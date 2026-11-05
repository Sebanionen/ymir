# Telegram message templates — six shapes, and the rules behind them

Read online on 2026-11-05 (Telegram Bot API limits and formatting pages; the GramIO, pi-telegram and Komodo alerter UX
notes) and reduced to what this house needs. Every template is **checked by a test**, so a shape that drifts fails.

```
uses[6]{template,when,what_it_must_do}:
  "alert.md","something is wrong and someone must act","severity · what · where · since — then buttons that silence, probe or open the log"
  "decision.md","a member of the house must choose","the question in one line, the options as buttons, the default named"
  "progress.md","work is running and will take minutes","one line per phase; the SAME message edited in place, never a stream of new messages"
  "report.md","a result with detail","five lines in the chat, the long thing attached, the buttons on the summary"
  "failure.md","a command or errand failed","what failed, the error quoted exactly, the one next step"
  "done.md","an errand finished","what was forged, what still stands unmade, what is owed from him"
```

## The rules these templates obey

- **A label is a verb and a noun.** "Approve", "Open log" — two words, never a clause. (The phone truncates a long label; the
  API does not stop you.)
- **2 to 4 buttons.** Four is a decision; more is a menu, and a menu belongs in an app.
- **The body explains, the button acts.** If a label needs explaining, the body is missing a line.
- **One idea per line.** A blank line between thoughts.
- **Over 4096 characters is not a message — attach it** and keep the caption under 1024.
- **Emit the wrapper, never type it:** `bin/notify/telegram-buttons.sh emit --button "label|prompt" --in-body`.
  A JSON payload with a `text` key instead of `label` arrives as a BLANK button and no error (measured 2026-11-05).

## Checked by

`bash bin/notify/tests/test_telegram_templates.sh` — every `*.md` here runs through `telegram-buttons.sh check` and
`telegram-format.py --check`; a template with a bad row, a long line or a missing prompt fails the test.
