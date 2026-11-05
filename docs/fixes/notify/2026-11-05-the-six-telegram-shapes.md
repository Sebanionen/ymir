# The six Telegram shapes, and the blank button that started it

**2026-11-05 · component: notify · `.agents/templates/telegram/` · `bin/notify/tests/test_telegram_templates.sh`**

His word: *"Make templates for ymir for telegram use cases. Find some online and use them"*, after two rounds of
*"I don't see all info on the buttons"* and *"your formatting for the buttons are still not letting me see what's written"*.

## The fault that made the templates necessary

`telegram-buttons.mjs` reads a JSON payload's **`label`**; every button sent that evening used **`text`**. The label was the
empty string, the bridge raised nothing, and the phone drew a blank button. The API never complained. A hand-typed wrapper
is a guess at a grammar.

## What was added

Six templates — `alert · decision · progress · report · failure · done` — each with a body shape, a **canonically emitted**
button row, and the rules: two-word labels, 2–4 buttons, one idea per line, attach anything over 4096 characters, edit a
progress message in place instead of streaming new ones.

Read online and reduced: the Bot API limits (4096 text · 1024 caption · 8 per row), the GramIO button-first UX notes, the
pi-telegram ui-style rules, and a production alerter's severity format.

## Made true by a test

`bin/notify/tests/test_telegram_templates.sh` runs **every** template through `telegram-buttons.sh check` and
`telegram-format.py --check` — 12 assertions, 0 failures. A template that drifts fails the test rather than the message.

`telegram-format.py` gained one exemption: a `[{label|prompt}…]` row is machine text and is never wrapped.

## CHANGE LOG

- **2026-11-05** — six templates, the test, and the formatter's payload exemption (Hœnir).
