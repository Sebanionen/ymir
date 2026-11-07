## gates · unversioned · 2026-11-06 — the ward reads the overlay too, because a model id is a local fact

`model-rows-guard` (the 28th ward, merged hours earlier) reads `$YMIR_HOME/config/agents.yaml` and
asks this machine's catalogue whether each row is servable. It went **red on the heart** the moment
the fleet's home was pulled — ten rows naming `llamacpp-3050-big/…`, a model another seat's GPU
serves and this one does not.

**The ward was not wrong about the file; it was reading one file where the house reads two.** The
door that resolves agent models, `bin/fleet/agents-config.sh`, has always deep-merged a
**per-host overlay** (`config/agents.<host>.yaml`) over the shared file. So the resolver said one
thing and the ward said another, about the same seat, on the same minute — the same fault class as
the ruleset number and the port: a check that ignores the local reading it is judging.

### What changed

| file | change |
|---|---|
| `bin/gates/guards/model-rows-guard.sh` | reads `agents.yaml` **and** `agents.<host>.yaml`; the overlay wins per agent, the same precedence the resolver applies; `YMIR_AGENTS_MACHINE` overrides the host, so the behaviour can be tested without moving files |

### Proof, both directions

- **green with this seat's overlay:** `model rows ok · 10` — the ids the resolver returns and the
  catalogue lists.
- **still judges without it:** `YMIR_AGENTS_MACHINE=somewhereelse` → red on the shared baseline,
  naming each agent and quoting *"not in this machine's catalogue"*. A ward that went green whenever
  an overlay existed anywhere would be a ward that cannot see a fault.

### Why the shared file keeps a seat's id (and why that is still wrong)

The home is one repository across seats, so whichever seat writes a model id into the shared
`agents.yaml` makes it the fleet baseline. That is acceptable as a *default* only because every seat
may override it — but it will keep producing this conflict until the shared file names something
every seat can serve, or the rows move wholly into overlays. That decision is the fleet's, not this
ward's; the ward's part is to stop lying about it.

## CHANGE LOG

- 2026-11-06 · the guard reads the per-host overlay as the resolver does; proven green-with and
  red-without; the remaining ambiguity (a seat id in a shared file) named, not hidden.
