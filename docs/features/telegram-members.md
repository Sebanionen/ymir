# Who is in a Telegram chat

**What it is.** A door that asks Telegram who is in a chat: the chat itself, how many are in it, and its
administrators by name and username. It exists because the bridge that carries this house's Telegram turns
shows an agent only the words that arrive — never the roll of who is in the room.

**What you need.** The bot's token (the door reads it from the harness's telegram profile, or from
`TELEGRAM_BOT_TOKEN`) and the **chat id** — the door cannot guess which room you mean, and says so rather than
picking one.

**The commands.**

```
bin/notify/telegram-members.sh me
bin/notify/telegram-members.sh chat   --chat <id|@username>
bin/notify/telegram-members.sh count  --chat <id|@username>
bin/notify/telegram-members.sh admins --chat <id|@username>
bin/notify/telegram-members.sh who    --chat <id|@username> --user <id>
```

**The limit, stated plainly — and it is Telegram's, not ours.** A bot **cannot enumerate ordinary members** of a
chat. The Bot API gives it:

- the chat's type, title and id (`getChat`),
- the number of members (`getChatMemberCount`),
- the administrators, with names and usernames (`getChatAdministrators`),
- one member at a time, if you already know their id (`getChatMember`).

There is no call that returns everyone. A door promising "all participants" would be lying. To know a group's
ordinary members, a house must **record who speaks**: each arriving message carries its sender, and that is how
a roster is built — which needs the bridge to hand the sender and the chat id to the agent, not just the text.

**Limits of this door.** It reads only; it never writes to Telegram, never posts, and never prints the token. A
private chat has no administrators, and Telegram refuses `admins` there — the door reports that refusal rather
than inventing an empty list.

**If it does not work.**

- *`unavailable: no TELEGRAM_BOT_TOKEN and no profile at …`* — no token found; set the env var or point
  `PI_TELEGRAM_CONFIG` at the harness profile.
- *`refused by Telegram (400): chat not found`* — the id is wrong, or the bot is not in that chat. Ask the
  bridge for the id it received the message on; the door will not guess.
- *`refused by Telegram (400): there are no administrators in the private chat`* — expected: a private chat has
  none.
- *`this verb needs --chat`* — by design. A door that picked a chat for you would be guessing at the one thing
  it must not guess.
