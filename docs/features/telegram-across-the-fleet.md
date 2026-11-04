# Telegram across the fleet — a bot per machine, and the road between them

## What it is

Each machine in the fleet has **its own Telegram bot**. That is deliberate: when a
message arrives, the bot it arrived at tells you *which machine spoke*, so a
house of five machines never looks like one anonymous bot with a split
personality.

Three parts, one door:

- **A registry** in your home — `hodd/identity/machines.yaml` — that names every
  machine, its bot's numeric id, the chat it speaks into, and the **vault path**
  where the token lives. The registry never holds a token, only where one is.
- **The fleet door** — `bin/notify/telegram-machines.sh` — lists the machines, says
  which bot answers, asks a chat's count or administrators as that machine's bot, and
  relays a line from this machine into another machine's chat.
- **The ear** — `bin/seat/hermes-telegram.sh` — reports whether the machine agent's
  messaging gateway is up and whether Telegram is actually attached to it. That is
  the ear that *receives*; the fleet door is the mouth that *sends*.

## What you need

- A registry at `$YMIR_HOME/hodd/identity/machines.yaml`. The shape is documented in
  the stub the repo ships at `hodd/identity/machines.yaml.example`; without a
  registry the door is **loud**, never an empty list.
- Each machine's bot token in the vault, at the path its row names:

  ```bash
  bin/vault/hodd-set.sh TELEGRAM_BOT_TOKEN '<token from @BotFather>' secrets/telegram-<machine>.env
  ```

  The token is emitted only into the environment of a child process. **It never
  prints** (Rule 24).
- The `chat` id for a machine you want to relay *to* — it stays empty until you have
  started a conversation with that bot, which is what gives the bot a chat to speak
  into.
- Hermes installed, for the ear: `bin/engine/hermes-ensure.sh`.

## Do it

### Who is in the fleet

```bash
bin/notify/telegram-machines.sh list
bin/notify/telegram-machines.sh all
```

```
<this-host>   bot=<bot id>   chat=   token_ref=secrets/telegram-<this-host>.env
<other-host>  bot=<bot id>   chat=   token_ref=secrets/telegram-<other-host>.env
```

`list` is tab-separated and prints **names, never values**: the bot id (public), the
chat (empty until set), and the vault path the token is read from. `all` prints just
the machine names, one per line — useful in a script that loops the fleet.

### Which bot answers

```bash
bin/notify/telegram-machines.sh me <this-host>
```

If the token is seated, Telegram's `getMe` answers and you see the bot's own
identity — `@SomeBot id=…` — which is how you prove that the token in the vault is
the bot you think it is. If the token is not there, the door refuses and says which
vault path is empty:

```
telegram-machines: no TELEGRAM_BOT_TOKEN in <this-host>'s vault ref
```

That refusal is the whole point of the reference-by-path design: the door would
rather fail — in words, with a message — than fall back to some token it found
lying around, or exit silently.

### Ask something about a chat, as that machine's bot

```bash
bin/notify/telegram-machines.sh count  <this-host> --chat <id|@name>
bin/notify/telegram-machines.sh admins <this-host> --chat <id|@name>
```

Same token, same refusal, and the answer is the member door's: how many are in the
chat, or who administers it. `chat` and `who --user <id>` pass through the same
way. This door chooses **which machine's bot asks**; every member answer belongs to
[who is in a Telegram chat](telegram-members.md), and the roll of who has actually
spoken belongs to [the Telegram roster](telegram-roster.md).

### Relay a line to another machine

```bash
bin/notify/telegram-machines.sh relay <other-host> "the well is dark on this box"
```

The message goes out through **this machine's** bot, into the other machine's chat,
and is prefixed with the sender's own name — `[<this-host>] the well is dark on this
box` — so the reader always knows which machine spoke. On success it prints `sent`
and **carves a Rune** into the audit ledger:

```
actor=<this-host>  event=telegram.relay  message="relay <this-host> -> <other-host>"
```

The Rune is the record that a machine spoke to another machine. A relay that fails
prints Telegram's own refusal instead, and carves nothing.

### The ear — Hermes

```bash
bin/seat/hermes-telegram.sh status
bin/seat/hermes-telegram.sh check
bin/seat/hermes-telegram.sh instructions
```

```
hermes-telegram[3]{what,value,note}:
  "gateway","running","the messaging ear"
  "platforms","none","telegram appears here once gateway setup has the token"
  "token_ref","secrets/telegram-<this-host>.env","the vault path, never the token"
```

`status` reads the gateway's own state file; `check` is the gate — it **exits 1**
when a token is ready but no platform is attached, so a cron or a test can tell the
difference between "the ear is up" and "the ear is up and deaf":

```
hermes-telegram: no platform attached (platforms=none) — run: hermes gateway setup
```

`instructions` prints the four steps and never the token:

```
1. create the bot in @BotFather and store the token: hodd/secrets/telegram-<host>.env
2. export TELEGRAM_BOT_TOKEN="$(bash …/bin/vault/hodd.sh emit secrets/telegram-<host>.env | sed -n s/^TELEGRAM_BOT_TOKEN=//p)"
3. hermes gateway setup      # choose Telegram, paste the token
4. …/bin/seat/hermes-telegram.sh check
```

## Notes & limits

- **A bot cannot enumerate a chat's ordinary members.** That is Telegram's limit, not
  this door's, and the whole of it is written down in
  [who is in a Telegram chat](telegram-members.md): a bot is given the chat, the
  **count**, the **administrators**, and **one known user** at a time. Everyone else
  exists only as an observation — a message that arrived — which is what
  [the Telegram roster](telegram-roster.md) records. So no door in this house claims
  to list a room's members; the member door says exactly what it can and refuses the
  rest, and this door says which machine's bot is asking.
- **One bot per machine, on purpose.** A shared bot across a fleet cannot say which
  machine spoke, and a token shared across machines is one leak away from being
  every machine's leak.
- `hermes gateway setup` is **interactive by design**: it asks, you paste. Ymir does
  not automate it, because automating a credential prompt is how a token ends up in
  a shell history or a log. The door points at the step and then *proves* the result
  with `check`.
- The ear and the fleet door are separate surfaces. `hermes-telegram.sh` reports the
  gateway's platforms; `telegram-machines.sh list` reports the registry. A machine
  can be in the registry with no gateway, and a gateway can be running with no
  platform attached — each door reports its own truth, and neither guesses at the
  other's.
- The registry is **private** (Rule 04) and lives only in your home. The repo ships
  the empty stub, never a populated file.

## If it does not work

**`telegram-machines: no registry at …/hodd/identity/machines.yaml`** — the fleet
has no registry on this machine. Create it from `hodd/identity/machines.yaml.example`
and fill in one row per machine. A missing registry is reported as an error, never as
"zero machines".

**`no TELEGRAM_BOT_TOKEN in <machine>'s vault ref`** — the row names a vault path
that holds no token. Store it with `bin/vault/hodd-set.sh TELEGRAM_BOT_TOKEN …` at
exactly the path the row names (`bin/notify/telegram-machines.sh list` prints it).
A token in some *other* vault file is a token this door will not find, by design.

**`telegram-machines: <to> needs telegram.chat and <this machine> needs its token`** —
a relay needs both ends: a chat id on the target row, and a token for the sender. A
bot cannot start a conversation with you; open the target bot in Telegram, say
anything, and its chat id becomes knowable.

**`check` exits 1 with `— run: hermes gateway setup`** — the gateway is up but no
platform is attached. Run the setup, choose Telegram, paste the token, then run
`bin/seat/hermes-telegram.sh check` again. It prints `telegram is attached ✓` only
when the gateway's own state file says so — not because you ran the setup.

**The relay prints `sent` but nothing arrives** — Telegram accepted the message for
a chat the bot can see. If your Telegram shows nothing, check the chat id belongs to
the conversation you think it does: a bot can only write into a chat it is already
part of, and a wrong id is accepted or refused by Telegram, never by us.

## Proven on this machine, 2026-11-04

```
telegram-machines.sh list           → one row per machine: name · bot=<id> · chat= · token_ref
                                      (a real fleet printed two rows, each chat empty)
telegram-machines.sh all            → the machine names, one per line
telegram-machines.sh me <this-host> → refused: no TELEGRAM_BOT_TOKEN in <this-host>'s vault ref
telegram-machines.sh count <host> --chat <id> → the same refusal, in words (never a silent exit)
telegram-machines.sh --help        → the four actions and THE LIMIT
hermes-telegram.sh status          → gateway running · platforms none · token_ref present
hermes-telegram.sh check           → exit 1, "no platform attached … run: hermes gateway setup"
hermes-telegram.sh instructions    → the four steps, token never printed
```

`relay` was **not** run in this pass: it sends a real message to a real chat, and
neither machine has a `chat` id yet, so the door would refuse before sending. That is
the honest state of this door today — the registry stands, the mouths are seated, and
no ear is attached until `hermes gateway setup` gets a token.
