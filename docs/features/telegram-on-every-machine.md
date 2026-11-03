# Telegram on every machine — the bot per seat, the road between them, and the ears

**What it is.** Every machine in the fleet carries its **own** Telegram bot, in its own name — this seat's bot
and heimdall's are different bots with different tokens, and a message in a chat always says which machine
spoke. Between those bots run two different roads: a **relay** for machine-to-machine orders, and a **shared
room** for conversation. On top of that, each machine's Hermes agent gets an **ear**: the same bot, seated into
Hermes' own gateway, so the machine's own agent answers it.

**What you need.** A bot per machine, made in `@BotFather`, and its token stored in the home's vault —
never in a file, a log, a plan or a chat. The fleet's registry (`hodd/identity/machines.yaml` in your home)
holds each machine's bot id, the chat it speaks into, and a **reference** to the vault file holding the token.
Nothing else: the registry never carries a token value.

**The registry, one row per machine.**

```
nidavellir   bot id · chat id (once paired) · token_ref: secrets/telegram-nidavellir.env
heimdall     bot id · chat id (once paired) · token_ref: secrets/telegram-heimdall.env
```

Store the token with `bin/vault/hodd-set.sh TELEGRAM_BOT_TOKEN <token> secrets/telegram-<machine>.env` — that
door encrypts it and keeps a backup. A machine with no entry, or an entry with no chat, is refused by name.

**Which door answers what.**

- `bin/notify/telegram-machines.sh list` — the fleet: machine, bot id, chat, and the vault reference. Never a
  token value.
- `bin/notify/telegram-machines.sh me <machine>` — which bot actually answers for that machine.
- `bin/notify/telegram-machines.sh count <machine> --chat <id|@name>` — the number Telegram will count for a
  chat, and no names, because it will not give you names.
- `bin/notify/telegram-machines.sh relay <machine> "<text>"` — speak into another machine's chat through
  **this** machine's own bot. One Runes entry is carved per hop, naming the sender's house, fleet and machine,
  the receiving machine, and the fact that no token travelled in it. Then the receiving chat's spoken record
  gains the speaker.
- `bin/notify/telegram-roster.sh record|list|show|chats|sync-admins` — who has spoken in a chat, one file
  per chat, each row saying where it came from. A roster row is a record, never a grant.
- `bin/seat/hermes-telegram.sh seat <machine>` — seat the machine's channel into Hermes' gateway from the
  vault; `unseat` takes it out; `check` proves it is attached; `status` shows the gateway, the platform, and
  whether the token is in the vault and in Hermes' env file.

**The two roads, and they are different roads.** *Relay* is machine to machine: an order or a handover, spoken
in the sender's machine name, carved in Runes, and never carrying a token. *Shared room* is conversation: one
operator group both bots sit in, where each answers its own agent's turns and reads the other as a
participant. Use the relay when a machine must be told something; use the room when people and agents are
talking in one place.

**Limits, stated plainly.**

The Bot API **cannot list the members of a chat**. Not for one bot, not for any bot, ever: `getChat` names the
room, `getChatMemberCount` gives a number, and `getChatMember` answers about one id you already know. So the
only honest member list is **who has spoken** — `telegram-roster.sh list --chat <id>` — and a name missing from
it means *has not spoken*, never *is not in the room*. The roster lives in your home, one file per chat, never in
the repo.

The relay cannot send until the receiving machine's `chat` is known, and that only exists once the bot has
been paired (you send it a message). Until then `relay` refuses loudly rather than guessing a room.

One token per machine, and never borrowed: the hop into another machine's chat is carried by the **sender's**
own bot. The peer's token never sends in this machine's name.

**If it does not work.**

- *`no registry entry for <machine>`.* The registry has no row for it. Add `machines.<name>.telegram.{bot_id,
  chat, token_ref}` to the home's `machines.yaml`.
- *`has no telegram.chat`.* The peer's room is not known yet, and this door does not guess rooms. Pair the bot
  and put the chat id in the registry.
- *`the sending machine <name> has no token`.* The vault file named by `token_ref` is absent or will not
  decrypt. Store it with `bin/vault/hodd-set.sh`; the refusal is about the token, never the registry.
- *`no token for <machine> … nothing was written`.* Hermes was **not** seated, deliberately: an ear with no bot
  is a named gap, not a silent success. Create the bot, store the token, run `seat` again.
- *`this Hermes is <machine>'s ear; <other>'s ear is seated ON <other>`.* Each machine's Hermes is its own
  ear. Run `seat` on that machine.
- *`hermes-telegram: no platform attached`.* The token is seated but the gateway has not re-read its platforms:
  `hermes gateway restart`, then `check` again.
- *The relay says `NOT CARVED`.* The hop was sent but the ledger refused to record it. Treat that as a fault,
  not a warning: an unrecorded hop is exactly what this door exists to prevent.
