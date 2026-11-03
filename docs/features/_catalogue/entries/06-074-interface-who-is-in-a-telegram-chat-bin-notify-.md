---
section: core-install-run-operate
---
| Interface | **Who is in a Telegram chat** (`bin/notify/telegram-members.sh`) | The bridge shows an agent only the words that arrive, never the roll of the room. This door asks Telegram directly: `me` · `chat` · `count` · `admins` · `who`. It states the limit rather than papering over it — a bot **cannot enumerate ordinary members**; it gets the chat, the count, the administrators and one known member at a time, and nothing more. The chat id must be given, never guessed. Reads only; the token is never printed | [Who is in a Telegram chat](docs/features/telegram-members.md) |
