# The Telegram roster — who speaks, remembered

**What it is.** A record of who has spoken in a Telegram chat. It exists because of a hard limit: Telegram will not
list a group's ordinary members for any bot, and the bridge hands an agent the message text without the sender. So
the only complete member list a bot can build is **a roster built from who speaks** — and this is that roster.

**What you need.** Nothing but Ymir. The store lives in the private home
(`<hoard>/data/telegram-rosters/<chat-id>.yaml`), one file per chat, because a name is private data and a roster
that mixed two rooms would file a person in the wrong place.

**The commands.**

```
bin/notify/telegram-roster.sh record --chat <id> --user <id> --name "Name" [--username handle] [--message <id>]
bin/notify/telegram-roster.sh list   --chat <id>
bin/notify/telegram-roster.sh show   --chat <id> --user <id>
bin/notify/telegram-roster.sh chats
bin/notify/telegram-roster.sh sync-admins --chat <id> --admins-json '<getChatAdministrators result>'
```

`record` is idempotent by message id: the same message recorded twice changes nothing, so a replayed update cannot
inflate a count. `sync-admins` merges the administrators Telegram *will* give — so an admin who never speaks still
appears, marked as taken from the API rather than observed.

**Limits, stated plainly.** The roster knows only people it has been told about: those who spoke, the
administrators, and anyone the operator names. It is not, and will never be, "everyone in the chat" — that list
does not exist. Each row says where it came from (`observed`, `api`, `operator`), so nobody mistakes a guess for a
measurement. And **a roster row is never a grant**: knowing a name opens no door; the gate, the grant and the
Allfather's word do that.

**If it does not work.**

- *`refused: --chat is required`* — by design. A roster that guessed its room would file a name in the wrong place.
- *`refused: no roster row for <id>`* — nobody has recorded that person in that chat yet.
- *`refused: sync-admins needs --admins-json`* — pass the raw `getChatAdministrators` result; get it with
  `bin/notify/telegram-members.sh admins --chat <id>`.
- *`unavailable: PyYAML is required`* — install PyYAML; the store is YAML so a human can read it.
