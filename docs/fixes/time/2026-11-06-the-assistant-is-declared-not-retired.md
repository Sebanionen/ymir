## time · unversioned · 2026-11-06 — the assistant is DECLARED, not retired

The deaf alarm about Skírnir was fixed hours ago by asking *whose mouth it is* before judging the
beat (`bin/time/housewatch.sh`, PR #549). But that fix's skip line said **"the assistant does not
run on this seat"** — and after two days of a ghost alarm, that sentence is one reading away from
*"the assistant is gone"*.

**The Allfather corrected the premise:** *"skirnir are not retired. just not connected."*

He is right, and the tree says so plainly: `systems/skirnir/domain.yaml` declares him as
`kind: system`, keeper `skirnir`, with doors for voice, knowledge, the gate and the rooms; the
folder carries his README, AGENTS.md and board. He is a system with no screen of his own — not an
absent service. What is missing is a **connection** on these seats: no systemd unit on the heart or
on nidavellir, and no `telegram.heartbeat` in the shared home.

### What changed

| where | change |
|---|---|
| `bin/time/housewatch.sh` | the skip now reads *"the assistant is DECLARED (systems/skirnir/, not retired) and not connected on this seat"* — naming the declaration, so no reader has to guess |
| the operator's `config/services.yaml` | a `skirnir` row, `state: "declared, not connected"`, with the reason and this date (private home, not this repo) |

### Why the wording is the fix, and not a nicety

An absent service and a present-but-unconnected one look identical from a heartbeat. The ledger
already paid for that ambiguity: a ghost alarm repeated 179,022 seconds, and the natural reading of
*"does not run on this seat"* was *retired* — which is how a living system gets quietly written off.

The rule this adds to the house: **a skip that concerns a thing that EXISTS must name its
declaration.** "Not running" is a state; "not there" is a deletion, and only one of them is ours to
announce.

## CHANGE LOG

- 2026-11-06 · the skip line names the declaration and the Allfather's correction; the operator's
  registry gains the row that says the same thing where services are declared.
