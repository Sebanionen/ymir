# Telegram formatting — long answers, shaped so a phone can read them

## What it is

A door that shapes a reply before it is sent: one idea per line, short sentences, structure intact.

Rich text stays on. Drafts stay off.

## What you need

Nothing. `bin/notify/telegram-format.py` is plain Python 3.

## The commands

```bash
# shape a message
some-command | bin/notify/telegram-format.py

# aim under a length
bin/notify/telegram-format.py --max 80 < draft.md

# the ward: does any line run too long?
bin/notify/telegram-format.py --check < draft.md
```

## Limits

- It breaks lines; it never rewrites, summarises or reorders words.
- Code fences, tables, headings, list items and `telegram_button` blocks pass through untouched.
- `--check` judges only unprotected lines.

## If it does not work

`telegram-format: unknown argument` — read `--help`. A line still long after formatting means a single word longer than the
limit, which it will not split.
