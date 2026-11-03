---
section: core-install-run-operate
---
| Interface | **The Telegram roster — who speaks** (`bin/notify/telegram-roster.sh` · `telegram-roster.py`) | Telegram will not list a group's ordinary members for any bot, and the bridge hands over no sender — so the only complete member list a bot can build is a roster built from who speaks. `record` (idempotent by message id) · `list` · `show` · `chats` · `sync-admins` (the administrators Telegram will give, so an admin who never spoke still appears). One file per chat in the hoard, every row marked `observed` · `api` · `operator`, and a row is never a grant. 10 assertions in `bin/notify/tests/` | [The Telegram roster](docs/features/telegram-roster.md) |
