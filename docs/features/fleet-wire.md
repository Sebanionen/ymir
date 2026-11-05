# The fleet wire — how two Ymir seats talk to each other

## What it is

Three working roads between machines of **this** fleet: a live pane, a durable queue, and a room file. A collaborator
never uses them; a partner uses the A2A door instead.

## What you need

- ssh to the peer (keys only), and `herdr` running on the peer.
- The peer's seat name from `hodd/identity/seats.yaml`.

## The commands

```bash
# 1. the pane — a live agent hears it now (pane resolved live, never stored)
ssh <peer> 'herdr agent prompt <pane> "<line>"'
ssh <peer> 'herdr agent list'                 # find the pane; it changes every session

# 2. the queue — the peer may be mid-turn; the arm raises it
ssh <peer> "printf '%s\n' 'from=<seat> to=<seat> at=<iso> msg=<text>' >> <lease-state>/.wake-queue"
#   resolve <lease-state> from the far seat's .arm.lease `state=` — never from a remembered path

# 3. the room — the record outlives both seats
systems/skirnir/services/room.sh append --room the-fleet --speaker <name> --text "…"
```

## Limits

- A wake is durable until `bin/time/saga-wake-drain.sh ack`; the queue is at-least-once by design.
- A line written without a trailing newline used to be counted and never shown — the drain now reads `|| [ -n "$line" ]`.
- A pane id from an earlier session is a phantom: always resolve it live.
- One writer per file: room lines go to each speaker's own jsonl, plan talk to each seat's own inbox.

## If it does not work

`no agent is seated in that herdr` — the machine is up, the seat is not: seat it, do not guess a pane.
A wake that never appears: the queue path is wrong (read the far `.arm.lease`), or the line has no trailing newline and
the running drain is older than #512.

## CHANGE LOG

- **2026-11-05** — written (Hœnir) after the fleet wire was proved in both directions between heimdall and nidavellir.
