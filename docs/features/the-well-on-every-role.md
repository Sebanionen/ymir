# The well answers on every role — how to get memory on a phone as well as the servers

## Checking the memory itself

Run `bin/records/mimir.sh memory --json --check`. With a bridge online this reads
the serving engine's health, including for a borrowed well or a Windows engine
queried from another environment. JSON names the measurement `bridge`; offline
file checks name it `local-file`. Exit 1 means unhealthy or unavailable health.
An online transport with an empty database is still unhealthy. A failed bridge
health response is not silently replaced by a different local database.
`mimir.sh health` also reports the serving engine's episode count, its health
boolean and the reason, instead of treating a local log count as remote memory.

Windows and WSL loopback listeners can be different processes serving different
homes. Check the `store` returned by `memory --json` before trusting a recall.
Select the intended, already protected bridge with `MIMIRSBRUNN_URL`; a successful
connection alone does not establish that it is the right well.

Do not open a Windows-owned WAL database directly from WSL to diagnose the
serving engine. Use its HTTP health/recall doors. Never replace a store because
a client cannot read its file.

The house keeps one memory, the well, and it lives on the heart. A laptop or a server with the engine
installed serves that well itself. A phone cannot: the engine needs two native pieces with no build for
Android, so on a phone — a `hand` in this house's language — the well is **borrowed** from the heart
through a door, an ssh forward that makes the heart's memory appear on the phone's own `127.0.0.1`. Since
2026-10-28 the same command does whichever of the two your machine needs, and it tells you which one it
did.

## What you need

- A machine that is on the fleet, with its role recorded (`fleet.json`) — or a `hand` whose ssh can reach
  the heart.
- On a phone: an ssh key that reaches the heart without a password prompt, and the heart's well actually
  running (`bin/bridge/mimir-bridge.sh --start` on the heart).
- Nothing else. No engine on the phone, no second command.

## Do it

Raise the well:

```
bin/bridge/mimir-bridge.sh --start
```

On a box with the engine you will see a `store` and `status "started"`. On a phone you will see the door
being raised, and then:

```
well[1]{port,store,status}:
  4602,"door","borrowed from the heart"
```

Ask it what is answering:

```
bin/bridge/mimir-bridge.sh --status
```

`4602,"up (local)"` means this machine serves the well itself. `4602,"up (door)"` means you are borrowing
the heart's — both are working, and you should know which you have. `4602,"down"` means neither.

Lower it again with `--stop`; on a phone that closes the forward rather than leaving it standing.

Drink and water it as usual — `bin/records/mimir.sh recall "…"` and `bin/records/mimir.sh observe --tags …`.
Nothing about the answers changes, because it is the same well.

## Notes & limits

- The door is two ports: `4602` (the HTTP face the CLI speaks) and `8317` (the MCP face harnesses speak).
  Both are forwarded by `bin/records/well-door.sh up`.
- The heart's own well must be up. A door with nothing behind it is reported as such
  (`well-door.sh status` prints `forward up, but NOTHING behind it`), never as a green.
- The address of the heart is configuration, not a constant: `YMIR_HEART` (default `zerwizserver`) and
  `WELL_HEART_HOST` (default `127.0.0.1` behind it).
- A borrowed well is read **and** write: an observation made on the phone is written to the heart's store,
  since the door only ever speaks to the heart.

## If it does not work

`error: no local engine under python3.13, and the door to the heart did not answer` — the phone cannot run
the engine and the forward failed. Run `bin/records/well-door.sh status`: it says, per port, whether the
forward is up and what the heart reports behind it. If the heart has nothing listening, raise it there
first (`bin/bridge/mimir-bridge.sh --start` on the heart).

`well-door: could not forward 4602 (ssh zerwizserver)` — ssh itself failed: no route, no key, or a
passphrase prompt. Test it plainly with `ssh zerwizserver true`; the door runs ssh in batch mode, so a key
that needs a password will never open it.
