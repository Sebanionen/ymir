# A wake without a trailing newline was counted and never presented

**2026-11-05 · component: time (the wake drain) · `bin/time/saga-wake-drain.sh`**

## What happened

A fleet nudge was written into the wake queue as a single line **with no trailing newline**
(`printf '%s'`, not `printf '%s\n'`). The drain then reported:

```
wake queue: 1 pending
WAKE_ACK_REQUIRED: acknowledge handled wakes to drop them from the queue
```

— **one pending, and no `WAKE` line.** The message was delivered, counted, and never shown. Appending one `\n` by hand made
the same line print immediately, which is the whole diagnosis.

## The fault, exactly

```
count   awk 'END{print NR}'  → 1   (correct: the last line counts even unterminated)
present while IFS= read -r line    → 0 iterations (read returns non-zero at EOF without a newline)
```

So the drain already knew how to **count** an unterminated line — the 2026-10-24 note in the file says exactly that
(`wc -l` said 0 while the extension read the door as non-empty) — but the **presentation** loop was never given the same
treatment. A counted-and-unpresented wake stays pending forever and is cleared by nothing: a silent lost message, which is
the one thing a durable queue exists to prevent.

## The fix

Both loops (the FM queue and the main queue) now use the canonical idiom:

```bash
while IFS= read -r line || [ -n "$line" ]; do
```

`read` fails at EOF, `$line` still holds the final unterminated content, and the body runs once more. Two lines, no
behaviour change for well-formed queues.

## Proven

```
old code, a queue file of 69 bytes with no trailing newline → "1 pending", no WAKE line
new code, same file                                       → "1 pending" + "WAKE from=test to=heimdall …"
```

## What it teaches

The same lesson as the fleet's twelve: **a count is not a presentation, and a summary is not a delivery.** The drain was
honest about the queue being non-empty and silent about its contents — the exact shape that reads as green.

— Hœnir, counsellor seat of heimdall.
