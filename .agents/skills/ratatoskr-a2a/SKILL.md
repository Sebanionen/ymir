---
name: ratatoskr
description: >-
  Ratatoskr — Ymir's A2A/MCP mesh. Load when agents collaborate, when wiring or
  debugging the a2abridge/A2A directory, when using the wayofteams control-plane
  MCP, when registering an Eindri over A2A, or when a task is dispatched between
  machines. Covers the engine, the Ymir front door, and both MCPs together.
allowed-tools: read,write,bash,glob,grep
---

# ratatoskr-a2a — A2A/MCP mesh — a2abridge + wayofteams; registration

The squirrel runs the World Tree. Agents collaborate over **A2A 1.0** (JSON-RPC +
SSE, Agent Cards) via the **`a2abridge`** engine, and coordinate through the
**Way of Teams** control plane — **both MCP servers at once**.

## The pieces

```
parts[4]{thing,path,role}:
  "engine","~/.a2abridge/bin/a2abridge","directory (discovery) · bridge (announce) · service · cert · doctor"
  "front door","bin/bridge/ratatoskr.sh","status|doctor|directory|service|cert — Ymir's wrapper"
  "wiring","bin/bridge/a2a-mcp.sh","installs both MCP servers into pi + opencode"
  "registration","a2abridge bridge -name -model -skills -directory -advertise-host -id -state-dir","an agent announces by running bridge"
```

## Two MCPs, together

- **`a2abridge`** — the mesh: `a2a_list_agents`, `a2a_send_message`, `a2a_inbox`,
  `a2a_complete_task`. Peer-to-peer; standalone.
- **`wayofteams`** — control plane: tickets, plans, standups, memory, knowledge.

Complementary, not competing. Neither depends on the other. Glue: a Teams
**ticket → `a2a_send_message`** to the peer; on **`a2a_complete_task`** the result
goes back to Teams. Same `A2A_NAME` in both planes.

## Use it

```bash
bin/bridge/ratatoskr.sh status          # engine + directory + served agents
bin/bridge/ratatoskr.sh doctor          # health-check
bin/bridge/a2a-mcp.sh install           # (re)wire the MCP servers into pi + opencode
```

**Production rules:** stable `-id`, `-advertise-host` = the machine's **Tailscale
IP** (never 127.0.0.1), state in `.a2a/<agent>`, the directory as a **service**,
heartbeat + deregister, and `cert` (ed25519) before federation. Cards are
UNSIGNED until then. Realm boundaries hold.

Plan + registration spec: `$YMIR_HOME/svartalfaheim/whynotproductions/workspace/ymir/plans/25-ratatoskr-a2a.md` and `$YMIR_HOME/hodd/docs/a2a-runs.md`.

## Joining the mesh and talking (skill-driven, no code)

A seated Eindri joins and talks **by loading this skill** — the pi adaptor
(`a2a-send` / `a2a-discover`) and the `a2abridge` MCP provide the tools; this
skill says how to use them.

**Every pi agent already carries the tools** (pi loads `Way-Of/pi-a2a-adaptor` +
the `a2abridge` MCP). So inside a session:

- `a2a-agents` / `a2a-discover` — list peers registered with the directory.
- `a2a-send <peer> "<text>"` — task a peer; the reply comes back as a task.
- `a2a-broadcast "<text>"` — FYI to the mesh.

**To be reachable**, the agent's bridge must announce to the directory
(`~/.pi/agent/mcp-adapter.json` → `a2abridge`, `A2A_DIRECTORY`). If a peer does not
appear in `a2a-agents`, the bridge announced to the wrong directory — the fix is
in the **skill/config**, not new code: point the bridge at
`http://127.0.0.1:7777` with `-advertise-host <tailnet-ip>` and `-name <agent>`.

**Outside a session** (Brokk, scripts): `bin/bridge/a2a-talk.sh agents` and
`bin/bridge/a2a-talk.sh send <peer> "<text>"`.

Rule: the mesh is used through the **skill's tools**, not bespoke code — if a
capability is missing, extend this skill.

## Delivering a message = injection into the chat

An A2A task that only reaches the bridge is **never read**. The missing function
is **injection**: the inbound text must be placed into the seated agent's chat.

- **Talk to (deliver to) an Eindri:** `herdr agent prompt <agent-or-pane> "<text>"`
  — the agent reads it as a new turn and answers in its pane.
- **Capture the reply:** `herdr agent read <agent-or-pane>` (or pane read) and
  attach it to the A2A task result.
- **The rule:** A2A carries the task; **herdr injection makes the target agent
  read it.** Without injection, an Eindri will not read the a2a.

So the two halves are inseparable:
```
a2a-deliver[2]{half,mechanism}:
  "transport","A2A message/send -> the bridge (JSON-RPC, SSE)"
  "delivery","inject into the agent's chat via `herdr agent prompt`; read the reply back"
```

Any agent that can *send* over A2A must also *deliver* by injection on receipt.
Extend this skill (not code) when the delivery path changes.

## Peer addressing — names are NOT URLs

The A2A tools take an **agent URL** (`a2a_call(agent_url, ...)`). A peer *name*
like `hermes-zerwiz` is **not** a URL and fails with `Invalid URL`.

**Always resolve first:** call `a2a-agents` (or `a2a-discover`) → find the peer →
use its **`url`** field. Then `a2a_call(agent_url="<url>", text="…")`.

```
resolve[1]: a2a-agents -> [{"name":"hermes-zerwiz","url":"http://127.0.0.1:7777/"}, …]
send[1]:    a2a_call agent_url="http://127.0.0.1:7777/" text="…"
```

## Tool reference (as shipped in pi)

- **`a2a_call`** — args: `agent_url` (a URL string), `text`. Sends a task and
  returns the reply. **`agent_url` must be a URL** — a name fails `Invalid URL`.
- **`a2a-agents` / `a2a-discover`** — list peers as `{name, url, skills}`; use
  the `url` to address one.
- **`a2a-send-async`**, **`a2a-pending`**, **`a2a-conversations`** — long tasks.
- **`a2a-broadcast`**, **`a2a-chain`** — fan-out to the mesh.
- **Delivery on receipt** is injection (`herdr agent prompt <agent> "<text>"`);
  the reply is read back with `herdr agent read <agent>` and attached to the task.

Directory: `http://127.0.0.1:7777`. Config: `~/.pi/agent/mcp-adapter.json` → `a2abridge`.

## Federation — several Ymirs, one company (plan 58)

Plan 42 federates ONE operator's machines. Federating **several operators'** Ymirs
over A2A — a company project shared across different Ymir users — crosses the
realm law (Rule 05). It is therefore an **explicit grant**, never a merge:

```
federation[3]{piece,where,law}
  "the grants law","src/ymir_runtime/grants.py · hodd/identity/grants.yaml (kind `grants`)","a grant that crosses operators must carry a signature from EACH party's Heimdall; a missing signature is REFUSED, naming the Heimdall"
  "the typed card","packages/contracts AgentInterface {protocol · endpoint · signed}","the grant's `card` block is the SAME shape as the shared agent-card contract — one contract, never a second"
  "the scoped journal","bin/records/journal-append.sh --namespace <ns> · bin/records/journal-receive.sh","a company entry folds into journal/folded/<ns>/<host>.jsonl only; an entry with no namespace reads as the operator's own"
```

- **Signing rides each operator's Heimdall** (`a2abridge cert`, ed25519/JWS). Cards
  are UNSIGNED until `cert` has run; a card claiming `signed: true` without a
  signature is refused by the law.
- **Judge a registry:** `python3 -m ymir_runtime.grants check` (or
  `bin/gates/checks/ymir-config-check.sh validate <grants.yaml>`); `... signers` prints who
  must sign which grant.
- **Proven offline:** `tests/e2e/several-ymirs-foundation-proof.sh`.
- **Honest state:** the foundation — grants + namespace-scoped journal — stands;
  the **cross-operator well share** and the **Óðrerir company view** are NOT built
  yet and ride their own errands.

## Troubleshooting

- **`Invalid URL`** — you passed a peer *name*. Resolve with `a2a-agents`, then
  `a2a_call` the `url`.
- **`Task … exceeded max attempts (N)`** — the call was addressed correctly and
  the mesh created the task, but it never **completed**: the peer/bridge could
  not deliver to a live receiving agent, or delivery-by-injection is not wired.
  Check (a) the peer appears in `a2a-agents`, and (b) a receiving agent is
  running its bridge so it can read the injected task and answer.
- **No reply at all** — the transport carried it; the **return path** is missing
  (the peer's answer was not captured onto the task result).

Rule: a successful `a2a_call` needs **transport + a live peer + delivery
(injection) + return**. Missing any one shows up as a timeout/attempts error.

## Tools this skill drives (in `bin/`)

```
tools[4]{tool,does}:
  "bin/bridge/a2a-mcp.sh install","wire the a2abridge (+ wayofteams) MCP servers into pi + opencode"
  "bin/bridge/ratatoskr.sh status|doctor|directory|service|cert","engine + directory front door"
  "bin/bridge/a2a-talk.sh agents|send <peer> \"<text>\"","Brokk-side A2A talk"
  "bin/bridge/a2a-serve.py <pane> <name> <port>","per-Eindri A2A server: inject task -> read reply"
```

## The constellation road — between two independent fleets (2026-11-03, plan 172)

A2A is how two agents *talk*. It is not how two houses *trust*. When the peer is another
operator's Ymir — Sebastian's, say, with its own hoard, gate and law — the road is three objects and
one door:

```
road_door[4]{object,where,door}:
  "the card","published by its own house into a registry both read (or exchanged by hand)","`bin/bridge/constellation.sh publish|list|show`"
  "the grant","written in the RECEIVING house's own hoard: peer · skills[] · expiry · one signature per house. `pending` until both sign","`grant` → `countersign` → `activate` (or `revoke`)"
  "the token","EdDSA JWT: `aud` the peer, minutes, `scope` = the granted skills, `kid` the sender's key","`mint` … `verify --aud … --skill …`"
  "the ward","a grant may not name a skill the peer's card does not declare, and an expired active grant is a closed road","`bin/bridge/constellation.sh guard` (`bin/gates/guards/constellation-grant-guard.sh`)"
```

**MCP is not this road.** Gimlé's MCP read face is a tool surface *inside* a house: give it a place scope
and it is the guest half — a person of another house reading only the places that house shares — but it never
connects two fleets' agents. The road carries a request and its answer; the suite carries the record.

Two laws that bite here: **a collaborator is never a seat** (nothing may enrol a foreign hall in the fleet
registry, the seats map or an ensure script), and **reachability is not trust** (an address that answers, a
port reachable over the tailnet, an agent that knew the URL: none of these is a grant — RULES/24's appended
section). Every cross-house message is filed as a rune on both sides.
