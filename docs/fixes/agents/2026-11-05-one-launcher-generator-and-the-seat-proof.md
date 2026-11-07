## agents · unversioned · 2026-11-05 — one launcher generator, and a spawn is not a seat until the agent list shows it

### Why

Two faults, both measured on 2026-11-05, both of which killed errands while the dispatcher printed
`spawned`.

**1. Two launchers for one shape.** The 2026-11-04 mend put `-ne` plus every named extension into
`bin/agents/einherjar-spawn.sh` — and left `src/ymir_runtime/harness.py::build_launch_command` composing its
own pi line: `pi --model … "$(cat …)"`, no `-ne`, no `-e`. The engine is the ordinary road
(`state/<id>.meta` carries `engine=ymir_runtime/phase1`), so a worker seated by it inherited the seat's
absolute extension tree through `~/.pi/agent/settings.json` **and** discovered the worktree's own; pi
registered every tool twice and refused to load a single extension:
`Tool "ymir_index" conflicts with …/.yggdrasil/<id>/.pi/extensions/ymirhome.ts`. Three errands died on it
tonight, and the record of one of them still claims a pane that holds a bare shell.

**2. Nothing compared the claim to the pane.** `spawned … target=wQ:p1` was printed for an errand whose
agent had come up in `w3:pS`; the meta named the wrong pane and would have been steered as if it were a
worker.

### The fix

1. `bin/seat/pi-launcher.sh` — the ONE launcher generator (`extensions` · `print` · `write`). Discovery off,
   every extension named once from the **worktree**, the seat's npm packages re-stated, `YMIR_PI_SETTINGS`
   naming the settings file. It refuses a cwd with no `.pi/extensions` tree.
2. Both roads call it: `bin/agents/einherjar-spawn.sh` and
   `src/ymir_runtime/harness.py::build_launch_command(selection, brief_ref, launch_cwd)`. `seat.py` passes
   the worktree.
3. `bin/seat/seat-prove.sh <pane> <cwd>` — the proof door, asking `bin/seat/herdr-agents.py --find` (the one
   reader of `herdr agent list`) and, on tmux, the pane's foreground command. It prints the pane the agent
   ACTUALLY stands in, and exits 1 with the pane named when there is none.
4. Both roads act on it: the engine records `seat=yes|no` and `window=<the real pane>`, raises on unproven and
   writes `failed: the launch produced NO agent — pane <id> …`; the shell road does the same, notifies
   through Gná (`bin/notify/send.sh`) and exits 3. Neither prints `spawned` for an unproven seat.

### Proof

```
# (a) a fresh errand seats and appears in herdr agent list
$ einherjar-spawn.sh seal-proof-shell … --harness pi --model …
spawned seal-proof-shell harness=pi kind=ship mode=local-only … target=wT:p1 … seat=yes
$ bin/seat/herdr-agents.py
  "pi","idle","wT:p1","/home/…/.yggdrasil/seal-proof-shell","/home/…/.yggdrasil/seal-proof-shell"
$ grep -E '^(seat|seat_pane|seat_state|window)=' state/seal-proof-shell.meta
window=wT:p1  seat=yes  seat_pane=wT:p1
```

### Files

- `bin/seat/pi-launcher.sh` (new)
- `bin/seat/seat-prove.sh` (new)
- `bin/seat/herdr-agents.py` (adds `--find` and the `foreground` column)
- `bin/agents/einherjar-spawn.sh` (calls the generator, proves the seat, records the real pane)
- `src/ymir_runtime/harness.py`, `src/ymir_runtime/seat.py` (the engine calls the same two doors)
- `src/ymir_runtime/tests/test_harness.py`, `test_seat.py`, `tests/support.py`
- `.agents/skills/galdr-ymirsystem/assets/brokk-distro-runtime.md`

galdr-reread: `brokk-distro-runtime.md` (the launch road and its proof).
