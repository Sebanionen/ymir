# APPS — the applications, and only the applications

**This directory IS the registry: a directory here is an application, and an
application lives here.** Nothing else in Ymir may carry an application's name in
its path (Rule 22).

An application is something **the operator opens** — a hall, a seat, a smithy — that
carries a figure's name, a `README.md`, and its own build. Tooling that serves the
*machine* (placing windows, opening files, watching ports) belongs under `bin/`,
named for its function.

| app | figure | what it is | what runs it |
|---|---|---|---|
| **`hlidskjalf/`** | Hlidskjalf — the Allfather's high seat | the master control dashboard: the one plane that shows the whole house (React 19 + Vite SPA) | `bin/desktop/…` · `scripts/start.sh` (SPA :3888, gate :3889) |
| **`odrerir/`** | Óðrerir — the mead of poetry | the fleet's **Live Hall**, a Hlidskjalf-type app: the boards, the tickets, the plans made visible | `bin/desktop/…`→ its own deploy shim; see its README |
| **`sessrumnir/`** | Sessrúmnir — Freyja's hall of seats | the **desktop seat**: a GUI front-end for the Pi and OMP coding agents, chat / projects / files / commands in one window (vendored fork of `pi-desktop`, Apache-2.0) | `bin/desktop/sessrumnir-launch.sh` (launch), `bin/desktop/sessrumnir-ensure.sh` (deploy) |
| **`hvergelmir/`** | Hvergelmir — the well every stream runs into | the **news app**: a proactive, checkpointed agent that sweeps many sources on a cron tick, lets a decision model discard hype and keep signal, and renders survivors as cards (vendored from `zerwiz/pi-durable-news-agent`, MIT) | `apps/hvergelmir` · `just combos dev` (UI :4851) |
| **`smidja/`** | Smíðja — the smithy | the **agent factory**, stamped from the factory's templates: roster, phases, envelopes, the trace store, and the Visualizer UI (`:8437`) | `bin/desktop/smidja-bootstrap.sh`, `bin/desktop/smidja-board.sh` |
| **`smidja-factory/`** | — (the same craft, upstream) | the **factory clone** from `zerwiz/smidja`: the templates and skills that *stamp* `smidja/` into a repo. Not a UI the operator opens | `uv run .agents/skills/smidja-factory/scripts/install.py` |

**The rule that follows from this list** (Rule 22): the applications are the names
above. A path under `bin/` that carries one of those names is a misfiled tool — a
capability of the machine wearing an application's coat — and is moved out, named for
its function, or kept only as a thin `<app>-<function>.sh` shim in the layer that
deploys it.

**Adding an application:** create `apps/<figure>/` with its README and its build,
add its row here, and — if a layer must deploy or check it — add one shim in that
layer named `<figure>-<function>.sh`. That is the whole procedure.

## A vendored upstream keeps its own layout

`apps/smidja-factory/` is a **clone of `zerwiz/smidja`** (the upstream that stamps
`smidja/`), vendored into this tree. It carries its own `apps/visualizer` and its own
`scripts/` — **its** layout, not ours — and Rule 23 binds *our* code: the ward allows
this one path by name, and nothing else under `apps/` may nest an `apps/`.

If the factory is ever un-vendored (a package dependency instead of a clone), this
exception dies with it.
