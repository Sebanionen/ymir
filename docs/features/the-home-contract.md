# The home contract — every file Ymir reads, a shape that ships

**What it is.** Ymir keeps everything private in a home of your own — `$YMIR_HOME`,
by default `~/Documents/ymirhome`. The runtime reads a number of files from it:
your standing preferences, your learnings, your machines, your project registry,
the identity registers, your schedule, your agents' settings. **The home contract
is the one list of those files**, and the door that gives you each one.

Before the contract, a home was assembled from whatever somebody remembered to
templatise. Measured on 2026-11-02: a freshly raised home held **none** of the five
documents a session opens with, and no roster to name the seat — the startup digest
opened with four `ABSENT` lines. If you installed Ymir before that date, your home
is probably missing them too (see *If it does not work*, below).

## What you need

Nothing beyond a normal install. The contract is a file in the code tree
(`.agents/home-contract.yaml`) and the seeder ships with it.

## The commands

Check what your home is missing — writes nothing:

```sh
bin/engine/home-seed.sh --check
```

Give your home every file it is missing. It copies what is absent and **never
overwrites a file you already have**:

```sh
bin/engine/home-seed.sh
```

Heal a home that predates the contract (same effect, run by the updater):

```sh
bin/engine/ymir-migrate.sh status
bin/engine/ymir-migrate.sh apply
```

Read the contract itself — every file, what kind it is, what shape ships it and
which door writes it:

```sh
bin/gates/checks/home-contract-check.sh --list
```

Name the seat you are sitting at. The roster ships **empty on purpose** — a name is
yours to choose, never a script's invention:

```sh
bin/agents/seat-identity.sh set <this-host> brokk
```

## The five kinds, and what each promises you

- **seeded** — copied once from its template if absent, then yours. Your settings
  survive every update.
- **stub** — a writing prompt, not a policy: `operator.md`, `learnings.md`,
  `machines.md`, `projects.md`, `seats.yaml`, `hodd/AGENTS.md` and your realm's
  `HOOD.md`. Each arrives as an empty shape with headings, and is never touched again.
- **defaulted** — read from your home if it is there, otherwise from the shipped
  default. Nothing is written into your home behind your back.
- **optional** — read when present; absent, the feature reports a clean skip and
  says why instead of failing or hanging.
- **generated** — written by a door from live facts (the well, the skill index, the
  name registry). Never seeded, never hand-edited.

## Limits

- **Nothing is overwritten, ever.** A file that exists is your record, and it
  outranks any default Ymir ships.
- **A stub is not advice.** It teaches the shape and asks the questions; the answers
  are yours, and no update will replace them.
- **The contract covers what the runtime reads**, not what it writes while you work:
  `hodd/state/`, `hodd/memory/` (the well and the daily log), `hodd/secrets/` and your
  plans are outside it by design — a record is created by its own door, and a secret
  is never templated.
- **A `{realm}` row** resolves to the realm your home pins in `hodd/data/realm.md`,
  or to `default` when nothing is pinned.

## If it does not work

- **The digest still says `ABSENT: hodd/data/operator.md`** — the file was not
  seeded. Run `bin/engine/home-seed.sh` and look at its output; it names every row
  it skipped and why.
- **`home-seed.sh` says "no usable template for: …"** — the checkout is incomplete.
  Update the tree (`bin/agents/groa-update.sh`) and run it again; the seeder fails
  loudly rather than half-writing a home.
- **`seat-identity.sh` says "roster not readable"** — the roster is absent or empty.
  `bin/engine/home-seed.sh` creates it; then name the seat with the command above.
- **The gateway reports the contract is not clean** — run
  `bin/gates/checks/home-contract-check.sh check`. It names the row at fault: a
  template that does not ship, a door that does not exist, a required file with no
  shape, or a template no row names.
- **A file of yours was replaced** — that is a bug, and a serious one. The seeder and
  migration `0016` refuse to write an existing file; report it with the path and the
  update you ran.
