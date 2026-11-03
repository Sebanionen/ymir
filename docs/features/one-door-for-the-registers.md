# One door for every generated register

**What it is.** Ymir keeps registers that *describe the tree* rather than being written by hand — the `bin/`
inventory (`bin/README.md`, with `.agents/backend/README.md` beside it) and the capability register
(`.agents/assets/agents/capabilities.md`). Each is written by its own generator, and a change that adds a door
must run **every** generator, not the one it happens to remember. `bin/gates/registers.sh` is the list.

**What you need.** Nothing. It is a shell door over the generators that already exist.

**The commands.**

```
bin/gates/registers.sh list       # every generator, in order
bin/gates/registers.sh generate   # run them all — this is the one to run before committing
bin/gates/registers.sh check      # is every register current? (0 yes, 1 no)
```

The ward `bin/gates/guards/registers-guard.sh` calls `check`, and it is seated in `bin/gates/guards.sh`, so a
push and CI judge the same set. `--version` and `--help` are there too.

**The order that matters.** `bin/gates/inventory.sh` enumerates **tracked** files. A register written *before*
`git add` records a tree without your new doors, so it is stale the moment the commit exists and the push gate
fails on a branch where nothing is wrong. The order that works is:

```
write → git add → bin/gates/registers.sh generate → git add the registers → commit → push
```

**Limits, stated plainly.** `generate` writes the registers and nothing else; it never touches code, never
commits and never pushes. `check` reads only. A generator that fails is reported by name and the door exits
non-zero — it does not silently skip one. The list lives in the door and nowhere else: a new generator is added
there, or it is not run anywhere.

**If it does not work.**

- *`STALE` next to a generator.* Run `generate`, then stage the register it wrote.
- *`failed <generator>`.* That generator's own error is above the line; run it directly to see why.
- *`unavailable: no generators are declared`.* The list in the door is empty — a door with no generators is a
  pass that proves nothing, so it refuses instead.
- *A push still fails with `bin/README.md is STALE` after generating.* You generated before staging. Stage
  first, then generate.
