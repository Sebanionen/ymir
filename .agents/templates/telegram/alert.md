# alert — something is wrong and someone must act

```
🔴 CRITICAL · the well bridge is down
since 18:04Z (4 min)
host: the heart · port 4602
tried: restart once, refused
```

```telegram_button
[{Silence|Mute this alert for one hour}{Open log|Show the last 40 lines behind this alert}]
```

- **Severity first**, one emoji, one word: 🔴 CRITICAL · 🟠 HIGH · 🟡 MEDIUM.
- **What, then since, then where.** Four lines, no paragraph.
- **Never two alerts for one fault** — the door dedupes by key; a duplicate is a muted channel.
