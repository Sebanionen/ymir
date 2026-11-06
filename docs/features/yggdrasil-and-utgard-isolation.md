# Yggdrasil and Utgard — isolation

## What it is

Two kinds of isolation, for two kinds of risk:

- **Yggdrasil** — the worktree manager (the world‑tree). Every task gets its **own
  checkout on its own branch** under `.yggdrasil/<id>/`, so parallel work never
  collides. Merging and cleanup are explicit; nothing happens by accident.
- **Utgard** — the sealed execution barrier (the realm outside the wall). Untrusted or
  risky code runs in an **ephemeral container**: no host root, **no network by
  default**, CPU/RAM/timeout caps, a read‑only rootfs, and **only the task worktree
  mounted**. A failed run leaves no trace on `main`.

Yggdrasil keeps work *apart*; Utgard keeps it *contained*.

## What you need

- Ymir installed.
- For Utgard: a container engine (Docker or rootless Podman) and the image —
  `bin/forge/utgard.sh build` builds `utgard-runner:latest`.

## Do it

**Yggdrasil — a worktree per task:**

```bash
bin/forge/yggdrasil.sh create <id>            # .yggdrasil/<id>/ on its own branch
bin/forge/yggdrasil.sh list
bin/forge/yggdrasil.sh status <id>
bin/forge/yggdrasil.sh merge  <id>            # explicit, never automatic
bin/forge/yggdrasil.sh cleanup <id>           # remove it when done
```

**Utgard — a sealed run:**

```bash
bin/forge/utgard.sh status                    # image, network default, caps
bin/forge/utgard.sh build                     # build the image (once)
bin/forge/utgard.sh run <worktree> -- <command…> \
    [--network none|on] [--cpus N] [--memory M] [--timeout S]
```

**Sandcastle** is the engine underneath; the door delegates to it:
`bin/forge/utgard.sh sandcastle <args…>`.

## Notes and limits

- **A sealed run is one‑shot.** Utgard runs a command, capped and read‑only — it is not
  an interactive shell (for an interactive no‑network shell, use a **confidential
  session**, Rule 16).
- **No network by default.** `--network none` is the default; opening it is a
  deliberate act printed in the command, never a hidden setting.
- **herdr is the ordinary road; Utgard is the barrier.** Normal work runs in a herdr
  workspace in the worktree with **no container**; Utgard is for untrusted code. A
  declared `utgard` with no image is a **loud refusal**, never a silent downgrade.
- **One worktree per task** — parallel workers never touch each other's files.

## If it does not work

| What you see | What to do |
|---|---|
| `image utgard-runner:latest missing` | `bin/forge/utgard.sh build`. |
| `neither docker nor podman is reachable` | Start the engine, or declare `Isolation: herdr` deliberately. |
| A run times out | Raise `--timeout`, or the work does not fit the cap — split it. |
| A worktree will not merge | It diverged; resolve on its branch (see [resolving conflicts]). Yggdrasil never forces. |

## Added 2026-10-24 — a worktree carries no second extension tree

A new worktree used to check out `.pi/extensions/` like any other file. A pi seat inside
it then loaded the same extensions **twice** — the worktree's copy and the seat's — every
tool name collided, pi exited, and the errand's brief landed in a bare shell. Four
dispatches died that way.

`bin/forge/yggdrasil.sh create` now leaves that one path out of the worktree, using git's
own sparse-checkout. **You do not have to do anything**: a worktree made by the road from
now on is clean, and the files are still tracked — they are simply not checked out, so the
worktree stays clean and nothing is deleted.

Ask which extension tree serves the tree you are standing in, and whether that is one home:

```bash
bin/seat/valknut-load.sh --ext-home    # {tree, state, seat_root, serving}
bin/seat/valknut-load.sh --check       # exit 1 if a second home exists
```

`state` is `own` (this tree holds the extensions), `shared` (a worktree of the seat's own
repository — one home, served by the seat tree), `shared-copy` (this worktree has its own
copy — the fault) or `absent`. A worktree of a **different** repository is its own home.

**An older worktree is not rewritten.** If `--check` names one, its owner repairs it with
the single line the gate prints:

```bash
git -C <worktree> sparse-checkout set --no-cone '/*' '!/.pi/extensions/'
```

Two things to know: the exclusion relies on `extensions.worktreeConfig = true` in the
repository's config (git sets it when the first worktree becomes sparse — do not remove
it, or a later checkout repopulates the second tree), and a tree whose `.pi/` held *only*
extensions would no longer recognise its own worktree once sparse. Ymir's own tree keeps
`.pi/agents`, `.pi/shared` and `.pi/mcp-adapter.json` there, so this is a note, not a
limitation you will meet in this repository.

## A third shape — the box (2026-11-06)

Utgard above is the **locker**: thirty seconds, sealed, gone. It is right for one untrusted command and wrong for a run
that lasts, because it cannot install a tool, keep a clone, or be walked into.

A **box** is the workshop: a whole computer an agent owns for the length of a run, with its own root, its own copy of the
work, and nothing of yours — no home directory, no vault, no key. It is reached through one door, and that door holds the
credential so the box never does.

```bash
bin/forge/utgard.sh box build
bin/forge/utgard.sh box new myrun --ttl 4h --repo .
bin/forge/utgard.sh box enter myrun
bin/forge/utgard.sh box pull myrun /box/work /tmp/harvest
bin/forge/utgard.sh box rm myrun
```

Full page: [utgard-boxes.md](utgard-boxes.md).
