# The seats and the arm — where the work is, the whole house in one read, and who can be woken

## What it is

Three doors that answer three different questions, and none of them guesses.

**The seats** (`bin/seat/seats.sh`) — every pane that is open on this machine, in
either backend (herdr first, tmux if herdr is not running), with each pane's own
state: **working**, **idle**, **shell**, or **DEAD**. A dead shell is one whose
errand has ended and which will never answer again — it sits inside a disposable
`.yggdrasil/` worktree with no agent in it. That is the pane you close, and the door
refuses to close anything a live agent holds.

**The hall** (`bin/agents/hall.sh`) — the whole house in one read: which seat you
are, how many shell doors exist, whether anything is waiting to wake you, and the
last runes carved into the ledger. Read-only, and it writes nothing.

**The arm** (`bin/pi/arm.sh`) — whether this harness can actually be woken mid-run,
said honestly per harness. The watch *loop* is harness-agnostic (a systemd user
unit, `ymir-syn-watch.service`); the *session side* — how a wake gets into a live
session — belongs to a harness extension, and a harness with neither a hook nor an
extension cannot be armed. The door says so instead of pretending.

## What you need

- herdr or tmux for the seats (`herdr` is the ordinary road; tmux is the fallback
  and the door says which one answered).
- `python3` for the herdr pane rendering.
- For the arm: the `ymir-syn-watch` unit, run as your own user service.

## Do it

### Where the work is

```bash
bin/seat/seats.sh list
```

The first line names the backend, then one line per pane:

```
backend: herdr
pane      agent     state     dir                              title
w8:p1     pi        idle      ~                                π - <host>
w3:pJ     -         shell     ~/ymir                           you@<host>:~/ymir
wA:p1     -         DEAD      ~/ymir/.yggdrasil/<errand>       you@<host>:~/ymir/.yggdrasil/<errand>
wE:p1     pi        working   ~/ymir/.yggdrasil/<errand>       π - <errand>
```

Every state in that table is the **backend's own report**, not a claim of ours. A
pane holding an agent shows the agent and its status; a pane holding a bare shell in
an ordinary directory is `shell` — yours, and nobody's seat; a bare shell inside a
disposable worktree is `DEAD`.

Close a dead shell — and only a dead one:

```bash
bin/seat/seats.sh close wA:p1
```

Three real answers:

```
closed wA:p1 (no live agent held it; ~/ymir/.yggdrasil/<errand>)
refused: w3:pB holds a live agent (pi, done)
no such pane: no:such:0:0
```

The refusal is the feature. Closing a pane a live agent is working in destroys an
errand mid-word, so the door reads that pane's own record before it touches
anything, and refuses.

### The whole house in one read

```bash
bin/agents/hall.sh
bin/agents/hall.sh --runes 20
```

```
hall[4]{what,detail}:
  "seat","primary=<figure> host=<this-host>"
  "doors","612 shell doors listed in bin/README.md"
  "queue","0 pending wake(s)"
  "runes","<count> (last 5: <timestamp> <actor> · <timestamp> <actor> · …)"
```

Four facts, each from the door that owns it: the seat from the rendered seat file,
the door count from `bin/README.md` (the generated inventory), the queue from the
wake drain, the runes from the ledger tail. A door that cannot answer is reported as
unable, never as zero.

### The arm — which harness can be woken

```bash
bin/pi/arm.sh status
```

```
arm[3]{what,value,note}:
  "watch unit","active","the loop runs outside the session"
  "lock","none","the session that holds the helm"
  "arm","possible","the session side is an extension (Pi: gna-pi-watch; OpenCode: syn-watch-arm.js)"
```

Read it in that order. If the **watch unit** is not active, the arm is **not
possible** and the door says which service to start — there is no arming a loop
that is not running. If the unit is active, the session side decides the rest.

| harness | can it be armed mid-session? | what it needs |
|---|---|---|
| **Pi** | yes | the `gna-pi-watch` extension, already installed |
| **OpenCode** | yes | `.opencode/plugins/syn-watch-arm.js`, already installed |
| **Claude Code** | yes, via a hook | `bin/pi/arm.sh hook claude` prints the `SessionStart` hook line to add |
| **Hermes** | yes, via a hook | `bin/pi/arm.sh hook hermes` prints the same |
| **Codex, Cursor** | **no** | no session-hook surface; they can *read* the digest, but cannot be woken mid-run |

```bash
bin/pi/arm.sh hook claude
bin/pi/arm.sh hook codex
```

```
claude: add a SessionStart hook that runs: …/bin/time/saga-session-start.sh
codex: no session hook surface installed — it can read the digest by running …/bin/time/saga-session-start.sh, but cannot be armed mid-session (named, never faked)
```

The digest is the recovery input: whatever a harness can do, it can run
`bin/time/saga-session-start.sh` once at the start and know where the house stands.
Arming is the *additional* thing — a wake arriving while you are mid-turn.

## Notes & limits

- **Pi arms itself.** The extension re-arms at the end of each cycle; you do not run
  the arm script by hand, and a hand-run arm is how two cycles end up fighting. If a
  notification says the cycle is missing or unhealthy, that is when a repair runs.
- **Never run `bin/pi/syn-watch-arm.sh` directly.** It is the loop's own door; the
  harness extension owns it.
- `seats.sh list` shows what the backend knows. A pane whose agent process is alive
  but wedged still reads `working` — the door reports state, it does not diagnose
  health. If a working seat never moves, that is a recovery question, not a seats one.
- On tmux the state column carries the foreground command name; a bare `bash`,
  `zsh` or `sh` is `shell` (or `DEAD` inside a worktree), and anything else is
  reported by its own name and refused on `close`.
- `seats.sh` is read-only except for `close`, and `close` is the one destructive
  action on this page.
- Where there is no session bus (a cron job, a container, a boot script),
  `arm.sh status` reports the unit as `unknown (no session bus in this context)` —
  unknown is not absent, and a wrong claim would close a question that is still open.
- `hall.sh` reads the seat file and the generated inventory; if either is stale the
  hall reports the stale number. Regenerate with `bin/gates/inventory.sh` and
  `bin/seat/seat-surface.sh` rather than editing.

## If it does not work

**`no pane backend is running (herdr and tmux both silent)`** — neither backend
answers from this shell. Start herdr, or check that `herdr pane list` answers on its
own. Herdr must be running as your user, in the same session you are asking from.

**`bin/seat/seats.sh close` says `no such pane`** — the id must be the backend's own
(pane ids look like `w3:pB` in herdr, `session:window.pane` in tmux). Copy it from
`seats.sh list`; a pane that has already been closed cannot be closed again.

**`arm` says `not possible — the watch loop is not running`** — raise the unit:

```bash
systemctl --user start ymir-syn-watch.service
systemctl --user status ymir-syn-watch.service
```

Then re-run `bin/pi/arm.sh status`. If the unit refuses to start, read its journal —
a watch loop that dies on start will not be fixed by arming harder.

**`arm` says `unknown (no session bus in this context)`** — you are not in a login
session that owns a user bus. Run the door from your own shell — the same shell you
would type `systemctl --user` in — and it will read the unit properly.

**The hall prints a door count of zero** — the count comes from the generated
inventory, not from a directory listing. Run `bin/gates/inventory.sh` to regenerate
`bin/README.md`; a zero over a full shelf is a stale generated file, and it is worth
one look because this number has lied before.

## Proven on this machine, 2026-11-04

```
bin/seat/seats.sh list          → backend: herdr, 18 panes, 4 named DEAD
bin/seat/seats.sh close w3:pB   → refused: w3:pB holds a live agent (pi, done)
bin/seat/seats.sh close no:…    → no such pane: no:such:0:0
bin/agents/hall.sh              → the seat (figure + host) · 612 doors · 0 pending wakes,
                                   the rune count and the last 5 dated (`--runes 3` narrows it)
bin/pi/arm.sh status            → watch unit active · lock none · arm possible
bin/pi/arm.sh hook claude       → the SessionStart hook line
bin/pi/arm.sh hook codex        → "cannot be armed mid-session (named, never faked)"
```

The live-seat refusal was tested on a real working pane and made no change to it;
the dead-shell close was **not** run in this pass — closing another errand's shell is
not this door's debt to pay. The 4 `DEAD` panes this run reported are real and are
the operator's to close.
