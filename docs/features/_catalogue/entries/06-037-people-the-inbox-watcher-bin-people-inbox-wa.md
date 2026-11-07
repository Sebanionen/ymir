---
section: planned-named-and-designed-not-yet-built
---
| People | **The inbox watcher** (`bin/people/inbox-watch.sh` + `bin/people/inbox.sh`) | Reads the mailbox for replies from the people in the registry and announces each once — Runes, desktop, and the phone through the hound's severity ladder. `inbox.sh --from/--to/--unread` is the read door ("has that person answered yet?" as a command); the watcher runs at 08:20, 14:20 and 19:20 from `config/cron.yaml`, keeps announced ids in the vault state, and never sends, marks or deletes anything | [docs/features/the-inbox-watcher.md](docs/features/the-inbox-watcher.md) |
