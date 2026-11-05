# Telegram formatting — rich text kept, long prose shaped before it is sent

**2026-11-05 · component: notify · `bin/notify/telegram-format.py`**

## What he said

*"We need to update the telegram system for formatting better buttons and readable text. Everything i get here its just a
long word mishap."* · *"I wanna have rich text. But better formatted."* · *"I need to get alot of info in the messages. But as
I said. Good formatted."*

So: **rich text stays**, and the wall of prose stops being a wall.

## What was wrong, measured

- The bridge renders a paragraph as a paragraph. One long sentence arrives as one long line, because nothing reshaped it —
  the fault was ours, not the renderer's.
- `assistant.draftPreviews` was on, and every draft attempt in this group returned `HTTP 400 TEXTDRAFT_PEER_INVALID`
  (30 logged attempts in one sitting). Drafts are off now; rich rendering is on.

## The door

`bin/notify/telegram-format.py` — stdin → stdout, plus `--check` as a ward:

```
one idea per line        a paragraph of sentences becomes one sentence per line
long sentence            broken on clause marks, then on word boundaries, never mid-word
never touched            code fences, indented blocks, tables, headings, list items, telegram_button blocks
never done               reflowing the content, collapsing paragraphs, inventing words
--check                  exit 1 and name the line, its length and its text when a line is too long
```

## Proven

`bin/notify/tests/test_telegram_format.sh` → **6 ok / 0 fail**: sentence split, list untouched, fence untouched, blank line
kept, `--check` accepts a short line, `--check` refuses a 200-character line.

## Why a door and not a habit

A habit is per-session; a door is on every machine and can be checked. The same shape as every other fix tonight: naming the
fault is not the fix — a test that fails is.
