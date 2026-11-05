# Eindri — isolated workers

## What it is

**Eindri** are Ymir's workers: the isolated smiths. When work is complex, isolated, or
parallel, it leaves the main hall as an **Eindri** — gathered into its **own
Yggdrasil worktree** (its own branch, zero collision) and optionally **sealed in
Utgard** (a container: no host root, no network, capped). A failed run leaves no trace
on `main`.

## What you need

- Ymir installed and raised.
- For a **ship** errand: a **brief** (the task), and the project registered (see
  [Mjollnir](mjollnir-issue-to-pr.md) for the registry).
- For Utgard isolation: a container engine + the image (`bin/forge/utgard.sh build`).

## Do it

**Gather a worker into a worktree:**

```bash
bin/agents/einherjar-spawn.sh <task-id> <project-dir> \
    --mode direct-PR|local-only|no-mistakes \
    [--harness <name>] [--model <token|request>] [--effort low|medium|high|xhigh|max] \
    [--backend tmux|herdr] [--isolation auto|on|off]
```

- It creates or reuses `.yggdrasil/<task-id>` on its own branch, records
  `state/<id>.meta`, and refuses a ship task whose brief's
  `Delivery contract: mode=<mode>` disagrees with `--mode` — so an adjusted brief and
  the recorded task cannot drift.
- `--dry-run` shows what it would do and changes nothing.
- `--scout` gathers a read-only reconnaissance worker.

**Or start it directly:**

```bash
bin/agents/eindri-start.sh <task-id>
```

**Watch the fleet:** each worker's pane sits in the backend (`herdr`), and
`bin/agents/eindri-watch.sh` reports heartbeats.

## Notes and limits

- **herdr is the ordinary road; Utgard is the barrier.** A normal deploy runs in a
  herdr workspace in the worktree, **no container**. Utgard is for untrusted or
  risky work: no host root, no network by default, CPU/RAM/timeout caps. A declared
  `utgard` with no image is a **loud refusal**, never a silent downgrade.
- **One worktree per task.** Parallel workers never touch each other's files.
- **A worker smells of trust.** Read the brief before you spawn; it is the contract.
- **A worker never merges.** It ends with a PR; the seat's own agent seals it (Rule 08, the 2026-11-05
  amendment, `bin/agents/pr-seal.sh`) — never the worker, never a timer alone.
- **A spawn is not a seat until the agent list shows it.** `bin/seat/seat-prove.sh` reads
  `herdr agent list` after every launch; an unproven seat is recorded `failed: … pane <id> …`, never printed
  as `spawned`.
- **A status line is a claim; the pane is the evidence.** `bin/agents/eindri-liveness.sh` cross-checks every
  live claim at the sweep, and corrects a seat whose pane holds a shell, an exit or a crash.

## If it does not work

| What you see | What to do |
|---|---|
| `isolation=utgard requires an image` | `bin/forge/utgard.sh build`, or declare `Isolation: herdr` in the brief (deliberately). |
| `Delivery contract … disagrees` | The brief and `--mode` differ — fix the brief, or pass the matching `--mode`. The refusal is the guard, not a bug. |
| No pane appeared | The backend is down — `bin/seat/herdr-ensure.sh status`, then re-spawn. |
| The worker went quiet | `bin/agents/eindri-watch.sh` for heartbeats; `bin/agents/eindri-handoff.sh sweep` re-arms the failsafe. |
| The status says `working` but nothing happens | `bin/agents/eindri-liveness.sh check` names the verdict and the pane; `sweep` corrects the record and wakes the seat. |
| `seat=no` in `state/<id>.meta` | The launch produced no agent — read `state/<id>.status` (it says which pane), fix the cause, relaunch. |
