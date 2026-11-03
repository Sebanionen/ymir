# Telegram buttons — controls that actually render

**What it is.** A small door that writes Telegram's button markup correctly, and a checker that
catches the markup that looks right but does nothing. The bridge parses exactly two wrappers and
**silently ignores everything else**, so a reply whose controls are almost right arrives as a wall of
prose — with no error, no warning, and no way for the reader to tell that anything was meant to be
tappable.

**What you need.** Nothing beyond Ymir and Node (the grammar is one small script). The door works on
any machine, in any harness; it does not talk to Telegram itself.

**The commands.**

Write a footer row — buttons under the reply:

```
bin/notify/telegram-buttons.sh emit \
  --button "📜 Bearings|Give me my bearings for today." \
  --button "🗂 Open work|Show what is open and in flight."
```

Write an in-body row — buttons between paragraphs:

```
bin/notify/telegram-buttons.sh emit --in-body \
  --button "✅ Yes|Do it." --button "❌ No|Do not."
```

Check a draft reply before it is sent — it names every wrapper it finds and every fault, with the
line number:

```
bin/notify/telegram-buttons.sh check draft.md
bin/notify/telegram-buttons.sh check draft.md --json
```

The output of `emit` is the whole wrapper. Paste it into the reply at **column zero**; nothing else
needs doing.

**What the grammar is, in one paragraph.** A footer wrapper is `<!-- telegram_button [ … ] -->`; an
in-body wrapper is a column-zero fence opened with ```` ```telegram_button ````. The payload is
either JSON (`{"label":"…","prompt":"…"}`) or the shorter positional form `{label|prompt}`, where the
third field is a style (`primary`, `success`, `danger`) and the fourth disables the button
(`1`/`true`). A button may omit its label with `{|prompt}`; it may not omit its prompt while enabled.
A row holds at most eight; a reply holds at most six here, because that is the house's rule.

**Limits, stated plainly.** Eight buttons per row is Telegram's own limit; six per reply is ours, and
`--allow-many` exists for the deliberate exception. Labels are capped at 64 characters. `check`
refuses a reply with exactly one button only when asked (`--allow-single`), because a single control
usually means a decision that should have been prose or a proper choice. Nothing here sends anything:
`emit` writes text and `check` reads it.

**If it does not work.**

- *The reply has prose where buttons should be.* The wrapper was malformed, and the bridge dropped it
  without a word. Run `check` on the draft: it names the fault and the line.
- *`legacy colon form`.* `<!--telegram_button: label|prompt-->` — the colon form is the one that looks
  right and is completely ignored. Use `emit` and stop writing wrappers by hand.
- *`an enabled button needs a prompt`.* A button with a label and no prompt is tappable and does
  nothing. Give every enabled button the request it should send.
- *`the comment is indented`.* A wrapper must start at column zero; indented (inside a list, a quote or
  a code block) it stays literal text.
- *`nine buttons in one row`.* Use two rows, or let `emit` chunk them for you.
- *Nothing renders in the preview but the sent message looks fine.* Preview hides comments by design;
  the sent message is what matters, and only recognized wrappers activate.
