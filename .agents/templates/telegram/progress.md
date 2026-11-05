# progress — work is running and will take minutes

```
🔄 pulling main
🔄 regenerating the registers
✅ guards: 25 pass
🔄 writing the fix note
```

- **One line per phase**, the current one first.
- **Edit the same message**, never send a new one per phase: `editMessageText` on the id you already sent.
- **No buttons while running.** A button that does nothing is worse than none.
- When it finishes, the progress message is replaced by `done.md` or `failure.md`.
