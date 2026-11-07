# Utgard boxes — a whole computer for one run

## What it is

`bin/forge/utgard.sh run` is a **locker**: it runs one untrusted command in a sealed container for thirty seconds and
throws the container away. That is right for a script.

A **box** is the other thing: a whole computer an agent owns for the length of a run. It has its own root, its own copy
of the work, its own tools, its own address on your machine, its own clock, and its own vanishing point. It has nothing
of yours.

That last sentence is the point. An agent running on your machine shares your home directory, your git identity and your
rail key — so a run that goes wrong reaches everything you have. A box shares none of it, and holds **no secret at all**:
the door outside it keeps the model credential and adds it to the traffic on the way out.

## What you need

- Ymir installed, and Docker or Podman running.
- The box image: `bin/forge/utgard.sh box build` (about two minutes, once).
- For a box that can reach the models: one firewall rule, printed for you if it is missing (see *Limits*).

## Do it

**Make a box and go in:**

```bash
bin/forge/utgard.sh box build                          # build utgard-box:latest
bin/forge/utgard.sh box new myrun --ttl 4h --repo .     # a copy of the work, not a mount
bin/forge/utgard.sh box enter myrun                     # a shell inside
bin/forge/utgard.sh box enter myrun -- "pi 'fix the tests'"
```

**Watch the estate:**

```bash
bin/forge/utgard.sh box list        # name · seal · state · time left · url · lane
bin/forge/utgard.sh box status myrun
bin/forge/utgard.sh box url myrun   # http://127.0.0.1:8800  (the box's own door)
```

**Bring the harvest home, then put the box down:**

```bash
bin/forge/utgard.sh box pull myrun /box/work /tmp/harvest
bin/forge/utgard.sh box rm myrun                 # container, network and volume
bin/forge/utgard.sh box rm myrun --keep-volume   # keep the work, drop the box
bin/forge/utgard.sh box gc                       # reclaim every box past its TTL
```

**Prove the three laws:**

```bash
bin/forge/utgard.sh box probe
```

## The three seals

| seal | what the box can reach | when |
|---|---|---|
| `none` | nothing at all | untrusted code you only want to *run* |
| `door` | the rail, and only the rail, through one proxy | the ordinary agent run |
| `open` | the internet | a real build that must install packages — declared, labelled, and short-lived |

`box new` defaults to `door`. `box seal <name> open` says so out loud and records it, because an open box is a decision.

## Limits

- **A container on this host cannot reach a host service until one firewall rule exists.** `ufw` here drops input from a
  bridge, so the door cannot dial the rail. `box probe` prints the exact rule:

  `sudo ufw allow from <the door subnet> to any port <the rail port> proto tcp`

  `box probe` prints it with the real numbers, because a document does not carry an address. Nothing in the box's other
  two laws depends on it: the home, the vault and the key are absent either way.
- `box url` is **loopback only** today. Gate-fronting a box is not built.
- A box is one engine, one machine. The estate is not yet spread across the fleet.
- `--repo` **copies** the work in at `new`. It does not sync afterwards; use `box pull` to bring results out.

## If it does not work

- `error: no container engine` — install Docker or Podman, or set `YMIR_CONTAINER_ENGINE`.
- `new: image utgard-box:latest is missing` — `bin/forge/utgard.sh box build`.
- `new: the box started but its door did not` — the engine's own words are printed under it; usually a taken subnet,
  which the script already retries across eleven neighbours.
- `refused: box X has no door` — it was made with `--seal none` or without a port. Make another with `--port 3000`.
- The rail answers 401 — the vault holds no `LLAMA_SWAP_API_KEY`; `new` warned about this when it started the box.

## CHANGE LOG

- **2026-11-06** — Carved. The box, the door, the three seals, and the one firewall rule that is owed before a box can
  reach the rail.
