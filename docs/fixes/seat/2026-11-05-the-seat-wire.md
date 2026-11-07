# The seat wire — one seat speaks into another's live pane

**Component:** `bin/seat`, `hodd/identity/seats.yaml` (home) · **Date:** 2026-11-05 · **Plan:** 189

## What was wrong

Two live Pi seats on two machines, on one tailnet, could not read each other. The A2A doors bound loopback (fixed
separately, plan 188 §15/§16), and when a seat did speak — Hœnir typed straight into Sindri's pane, and Sindri answered
in **Telegram** — the far seat saw nothing, because a pane is not a chat. Every cross-seat word cost a git round trip.

## What this adds

`bin/seat/seat-wire.sh` — five verbs, no daemon, no token, no grant:

```
seats | who <seat> | read <seat> [--lines N] | say <seat> "<line>" | wait <seat> [--timeout MS]
```

- the peer's **pane is resolved live** from `herdr agent list` over ssh — never a stored id, never a guess;
- the peer's **identity is the far seat's own answer** (`~/.pi/agent/extensions/.ymir-seat`), so a registry that drifts
  is reported, not obeyed;
- every line is delivered with the attribution prefix `[seat <name> via the wire, <UTC>]`;
- every `say` writes the room line **first** (`hodd/rooms/<room>/<seat>.jsonl`) and speaks second, so a refused delivery
  still leaves the record;
- the registry lives in the private home (`hodd/identity/seats.yaml` → `machine: {host, ssh_user}`), so **no address is
  committed here** (Rule 39 · Rule 04).

## Refusals (named, loud, no fallback)

peer unreachable · no agent seated in that herdr · **two or more agents — listed, never guessed** · speaking to one's own
seat · text carrying control sequences or over 4000 characters.

## Verified

- `seat-wire.sh who heimdall` from nidavellir → `heimdall · Hœnir · w39:p5 · <session id>`.
- `seat-wire.sh say heimdall "…"` → `say[1]{to,pane,road,recorded}: "heimdall","w39:p5","pane","the-fleet"`, and the far
  seat reported the line arriving **intact with its attribution prefix**.
- `seat-wire.sh seats` resolves both seats to their tailnet addresses (`ssh heimdall@<tailnet>`,
  `ssh zerwizomar@<tailnet>`) with reachability `up`. The addresses themselves are resolved at call time and never
  written into this public repository (Rule 04 · Rule 39); see the redaction note appended below.

## Left open (plan 189)

The MCP door (`bin/mcp/ymir-mcp.py` → `seat_wire`) and the install step, so every harness gets it from one door rather
than a remembered shell line; and the `watch` verb that turns the gna arm into a fleet arm.

## Appended 2026-11-05 — the push that never left, and the sixth verb

### The gate fault, named

The branch held the wire and could not be pushed. `bash bin/gates/guards.sh` named **two** wards, not the one the
visible summary suggested:

```
"defaults-guard.sh","FAIL","defaults-guard: 1 default(s), 0 unresolved, 0 absolute symlink(s)"
"registers-guard.sh","FAIL",""
```

Run directly, the first one named its own failing line:

```
defaults-guard[3]{finding,file,line,text}:
  "a home guessed","bin/seat/seat-wire.sh","27","HOME_DIR="${YMIR_HOME:-$HOME/Documents/ymirhome}""
```

So the ward did not misfire — the new file did. The wire carried its own default for the operator's home, which is the
one thing `bin/vault/hoard-lib.sh` owns (Rule 07: one documented default, one resolver). The fix is in the cause, not in
the evidence: the script now SOURCES the resolver and CALLS `ymir_home_root`, and refuses loudly if the home does not
resolve. The second ward was honest too — a new door in `bin/seat/` had never been in the capability register, so
`bin/gates/registers.sh generate` was run and its output committed in the same change, as that ward's own message asks.

### The verb the plan specified and nobody built

`nudge <seat> "<line>"` appends one attributed line to the **far seat's** durable wake queue. The queue is resolved from
its authority, never from a remembered layout: one round trip reads the far machine's own home (its `YMIR_HOME`, its
recorded choice, or its `.ymir-seat` roster), then `<home>/state/.arm.lease`, then takes that lease's `state=` field and
appends to `<state>/.wake-queue` through base64 — never through quoting. Liveness is proven **on the far side**: the
lease's `pid` must be alive *and* its `/proc/<pid>` starttime must equal the lease's, because a recycled pid is not an arm.

The road is named in the output, always: `nudge[1]{to,road,queue,lease,from}` with `road="queue"`. `~/.local/state/ymir`
is an orphan shelf no arm reads — measured tonight on heimdall, where a line written there at 01:09 was never raised and
the nudge at 01:32 left that file's mtime untouched. A missing lease, an unreadable one, one with no `state=`, or one
whose pid is dead is a refusal, never a guessed path and never a fallback to the pane.

### A third ward, and a redaction it earned

`public-data-guard` refused this note as it arrived, and it was right: the `Verified` section printed two private
tailnet addresses in a PUBLIC repository. They are replaced with `<tailnet>` here. The wire still resolves and shows
them at call time — which is where an address belongs (Rule 04 · Rule 39). Nothing else in the note was changed.
