# The road between the machines — and the ears that were empty

**Date:** 2026-11-04 · **Component:** gate · Plan 178, the token-free half (T2 and T3)

## The fault the plan did not know it had

Plan 178 §6 recorded the relay as built: `bin/notify/telegram-machines.sh relay` "sends through this bot and
carves a Rune". Measured tonight, the carve had **never** happened, not once:

```bash
$ bash bin/notify/telegram-machines.sh relay heimdall "test"
$ echo $?
1
```

Nothing printed, and nothing in the ledger. The line was

```bash
bash "$ROOT/bin/records/runes-append.sh" --actor "$me_name" --event telegram.relay --message "..." || true
```

and `runes-append.sh` takes its actor and event **positionally**. Handed `--actor`, it reads the literal
string as the actor and the machine name as the event, then refuses — `unrecognized arguments: --actor
--event` — and the `|| true` on the end swallowed the refusal. So the relay's audit hop was a flag that did
not exist, guarded by a `|| true` that made its absence look like success. The same line also printed
nothing at all when a machine had no token, because every refusal it could make was redirected into
`/dev/null`.

That is the class of fault this house keeps paying for: **a green that hides a borrow**. A door that fails
silently is worse than a door that is not there, because the plan records it as done.

## What was built

**1. One Runes entry per hop, through the ledger's own door.** `relay` now carves one chained entry naming the
sender's house, fleet and machine, the receiving machine, and the fact that no token travelled:

```
relay hop · machine=<sender> · house=<house> · fleet=<fleet> · to=<receiver> · token-in-payload=none · message-id=<n>
```

House and fleet are read from the home's `hodd/identity/seats.yaml` — never a table kept in the script. If the
ledger refuses, the door says `NOT CARVED` out loud instead of pretending; the hop is not allowed to be
quietly unrecorded.

**2. Refusals that say why, in the order a person needs them.** Every one of them prints to stderr, exits 1,
and ends with *nothing was sent and no Rune was carved*:

| what is missing | the refusal |
|---|---|
| the peer is not in the registry | names the registry and the two fields to add |
| the peer has no `telegram.chat` | `its rooms are not this door's to guess` |
| **the sending machine has no token** | names the vault ref, says the hop is carried by *this* machine's own bot, points at `hodd-set.sh` |
| the Bot API refuses | repeats Telegram's own description |

The proof that matters is the third row: with a registry that *does* carry a peer and a room, and a
`token_ref` pointing nowhere, the refusal names the **token** — so a broken relay can never be blamed on the
registry again (`bin/gates/tests/test_new_doors.sh`, row 21). Measured: ledger 1022 → 1022 lines and no roster row written across that refusal.

**3. The roster — adopted, not duplicated.** The Bot API cannot enumerate ordinary members of a chat; not for
one bot, not for any bot, ever. While this errand ran, main gained **PR #499**: `bin/notify/telegram-roster.sh`
(`record · list · show · chats · sync-admins`) — one file per chat, idempotent by message id, the administrators
Telegram *will* give merged in, and every row carrying where it came from (`observed` / `api` / `operator`).

I had built a second door for the same question before I saw it. That is the exact fault this house keeps
paying for — two mechanisms, neither wired — so it was **withdrawn and the roster adopted**: `relay` now files the
hop into the roster, keyed by the sending machine's own bot id from the registry. A machine with no `bot_id` gets
`not recorded` with the reason, because a roster row is keyed by a real id and nothing is invented to fill one

**4. `hermes-telegram.sh seat <machine>` — the ear, from the vault.** The new verb reads
`telegram.token_ref` from the registry, emits the token from the vault, writes it into Hermes' own env file
(`$HERMES_HOME/.env`, mode 0600, one line, atomic replace), and enables the platform through Hermes' own
door (`hermes config set platforms.telegram.enabled true`) so no secret ever enters a command's argv. Added:
`unseat`. Every refusal happens **before any write** — a machine other than this host's, a registry with no
`token_ref`, and above all **the token is absent**:

```
hermes-telegram: no token for nidavellir: secrets/…(.age) is absent from the vault (or will not decrypt) — nothing was written
help: create the bot in @BotFather, then bin/vault/hodd-set.sh TELEGRAM_BOT_TOKEN <token> secrets/…
```

`status` gained the two rows that make the honesty visible: whether the token resolves in the vault, and
whether the env file carries it — so "the ears exist and are empty" can now be read as a state, not a guess.

**5. The token never enters a process listing either.** Every Bot API call goes through a helper that writes
the URL into a mode-0600 `curl --config` file and deletes it, so the token is absent from `ps` as well as
from stdout, logs and the repo.

## The two roads, named (the plan's T2.2)
They are not the same road, and the door's own help now says so:

- **relay — machine to machine.** This machine's bot speaks into the peer's chat, stamped with the sender's
  machine name. It is an order or a handover. One Rune per hop; the spoken table records the speaker; no
  token travels inside it.
- **shared room — conversation.** One operator group both bots are members of; each answers its own agent's
  turns and reads the other as a participant. Telegram will never list that room's members, so the spoken
  table is its only honest record.

## What is still his, and what is genuinely unproven

- **The seating.** A bot cannot create a bot: `@BotFather` → the bot → the token into
  `hodd/secrets/telegram-<machine>.env.age` through `bin/vault/hodd-set.sh`. This seat's token now exists in
  the vault and its bot answers (`getMe` returns the bot's own name and id — the id is public metadata and is
  recorded in the home's registry; the token is nowhere). The **Hermes sealing itself is one command and he
  has not said the word**: `bin/seat/hermes-telegram.sh seat nidavellir`, then `hermes gateway restart`. The
  write path was proved end to end against a throwaway `HERMES_HOME` (token line written, platform enabled,
  temp home shredded afterwards).
- **A real hop.** Neither machine's registry row carries a `telegram.chat` yet — no chat id exists until the
  bot is paired — so `relay` cannot send from here and correctly refuses. The Runes entry was carved for a
  **simulated** hop through the ledger's own door, and the line says `(simulated)` and `message-id=none`
  rather than claiming a send. It is **kept**: the ledger is append-only, and it is a true record of what
  was proved.

## The tests, and the red row they inherited

`bin/gates/tests/test_new_doors.sh` went from 13 green + 1 red to **21 green, 0 red**. Seven new rows: the
two roads named in the door's own help, the three relay refusals, the Hermes refusals (a foreign machine; no
token writes nothing), and the roster door standing. The five rows I first wrote for my own spoken table went
with it when the roster was adopted.

The red row was not mine and was not a flaky test: `seat-surface: check passes` failed because the
machine-local `.hermes.md` had never been rendered in this fresh worktree. It was fixed by **running the
renderer** (`bin/seat/seat-surface.sh`) — not by weakening the assertion — and the rendered seat file came
out byte-identical, so no seat moved.

One dead reference was removed on the way: `telegram-machines.sh` documented a `count` verb it did not
implement, and its `me` verb called `bin/notify/telegram-members.sh`, which this tree does not ship. Both now
answer directly against the Bot API, so the fleet door no longer points at a file that may be absent.

## Files

`bin/notify/telegram-machines.sh` · `bin/seat/hermes-telegram.sh` ·
`bin/gates/tests/test_new_doors.sh` · `docs/features/telegram-on-every-machine.md` (new) ·
`docs/features/_catalogue/entries/00-018-interface-telegram-the-road-between-machines.md` (new)
