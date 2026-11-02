# 25 — Agnostic by construction: one core, every device

**Appended 2026-10-18** at the Allfather's word: *"this must be a rule in ymir — we can't develop
with one device in mind. we are multi-device and hardware and operating system… we need to be
agnostic."*

**Why it exists, from this day's own wounds.** A reorganisation moved the scheduled jobs from
`bin/nornir-job-*.sh` to `bin/time/`  # allow-superseded-path: this sentence RECORDS the move and the operator's own cron kept the old spellings for
**three weeks**, because a home is not a checkout and nothing carried the change to it. On the same
day the warden was written reading `/etc/ufw` and `systemd`, the editor door was written against
Hyprland 0.56, and a rule was written that named `apps/` as if every machine had one. Rule **05**
says a core change updates every platform layer. This rule says the harder thing: **we may not
write, name, or move anything with one machine in mind in the first place.**

```
agnostic_law[8]{rule,what it means}:
  "THREE AXES, ALWAYS","device (laptop · phone · server · heart) · hardware (GPU · CPU · RAM · disk) · operating system (Omarchy/Arch · Debian · macOS · Windows/WSL · Android/Termux). A design that names none of them has assumed one."
  "PROBE, NEVER ASSUME","capability is discovered at run time (a GPU, a window manager, a package manager, a cron, a vault, python's zoneinfo) and the answer decides the path — never a hardcoded `/etc/…`, `systemctl`, `pacman`, `apt`, `hyprctl`, or `docker` on a machine that may have none."
  "A CLEAN SKIP IS A PASS","a layer that does not apply reports SKIP with the reason and exits 0. A capability that fails on another platform is a bug; a capability that PRETENDS is a lie."
  "ONE CORE, THIN LAYERS","the portable core (POSIX shell · python3 · git) does the work; each OS gets its own layer for what is genuinely theirs. A core change ships the layer change in the same commit (Rule 05), or the layer is drift."
  "A MOVE IS A MIGRATION","renaming or moving anything a machine may reference — a script, a unit, a config key, a shelf — ships, in the same change: the new path, a MIGRATION that heals existing homes and seats (.agents/migrations/), and a WARD that would have caught it. A move without those is a promise to break somebody's morning."
  "PATHS RESOLVE, NEVER HARDCODE","configuration comes from env → the recorded choice → one documented default (Rule 07). A machine's home, ports, hosts and seats are resolved, never assumed; a path that exists on this box is not a path."
  "THE LEDGER REMEMBERS WHAT MOVED",".agents/paths-ledger.yaml holds every path that has moved, with old → new and the date. The shipped tree may not reference a superseded path; the ledger is how the tree knows."
  "THE TEST IS A MACHINE THAT IS NOT THIS ONE","can a fresh clone + install reach a working seat on a device we do not own? If the answer is 'as long as it is this laptop', the work is not done."
```

**Enforced by** `bin/gates/guards/path-ledger-guard.sh` (no shipped file may reference a superseded
path from the ledger) · the platform layer probes (`bin/fleet/ymir-platform.sh`, `bin/host/*-sense.sh`)
· the clean-skip convention every `*-ensure.sh` follows · and `bin/engine/ymir-migrate.sh`, which
runs the migrations that heal an existing home.

## 2026-10-18 (appended) — the instance that proves the rule, found the day after it was written

**A derived artifact broke "PATHS RESOLVE, NEVER HARDCODE" in the one place nobody
reads.** On 2026-10-18 a session added `bin/agents/skill-index.sh` — a generated
index of every skill a machine holds — and committed its output into the **home
repo, which syncs to every machine**. The index wrote each skill's `path`
**absolute**: **192** entries under `/home/<this-seat>/…`.

On the **second machine (heimdall)** it therefore did not work at all:

- the finder resolved **nothing** — every path named a home that is not there;
- `--check` read the index as **incomplete forever**;
- the **home went dirty on every session**, as the index regenerated against the
  local tree.

The law was already written. What it cost to break it in a *generated file* rather
than in code is the part worth appending: **code is reviewed, and a generated file
is read by nobody and synced to everybody.** A derived artifact is not exempt from
this rule — it is the likeliest place to break it.

**Mended in `zerwiz/ymir` #354 and the home `12981df`:**

- the index stores `path` **relative to the shelf root** named by its `shelf`
  (`ships · local · home · pi`), and the **reader anchors it to its own machine**;
- the index and its human twin are **untracked and gitignored in the home**, beside
  `.ymir-layout.yaml` — a per-machine map must not travel;
- `stat` is **probed** (`-c %Y` → `-f %m`), never assumed, so the freshness check
  travels to BSD/macOS;
- `.agents/tests/skill-index.test.sh` **fails the build if a machine path ever
  reappears in the index** — the ward the "A MOVE IS A MIGRATION" clause asks for,
  applied to a generated file.

**The sentence to carry forward:** *any file a machine generates for itself belongs
to that machine — keep it out of the shared tree, or keep it relative.*

## 2026-10-28 (appended) — agnostic is not enough: the capability must be functional for the fleet

**Appended at the Allfather's word** — *"this must be built so it works for this device and the fleet"*
and *"always build agnostic and functional for the fleet"*.

**Why it needed appending.** Rule 25 was satisfied by a capability that did not *crash* on another
platform: a clean skip, a printed reason, exit 0. That is the right floor and the wrong ceiling. Measured
on this day: `bin/bridge/mimir-bridge.sh --start` **skipped** on the one device the Allfather actually
carries (a `hand` — Android/Termux), so the well was dark there from session start every morning while the
skip counted as a pass. A capability that only works on the box that built it is not agnostic; it is
unfinished with a polite refusal letter.

```
fleet_law[6]{rule,what it means}:
  "THE FLEET IS THE TEST","a capability is done when it answers on every role in the fleet registry — heart · forge · dev · hand — and over every road those roles have (local engine, tunnel, tailnet, ssh door). One role unexercised means unproven, not portable."
  "THE ROLE IS READ, ONCE","the role comes from the fleet registry by hostname (bin/skuld/role.sh resolve), never from what happens to be installed on the box, and never from a second table."
  "ONE COMMAND, EVERY ROLE","the same verb must succeed on every role by taking THAT role's road. A second command, or a second flag the operator must remember, is drift: on a hand the well is borrowed through its door, elsewhere it is served — `--start` is `--start` on both."
  "A BORROWED CAPABILITY SAYS SO","status names the road that answered — `up (local)` versus `up (door)` — because a green that hides a borrow is the false green this house has paid for twice."
  "THE FLEET'S ABSENCE IS A STATE","when the heart is unreachable the answer is a named state with its reason and its repair (`well-door.sh status`), never a hang, a silent failure, or a fabricated zero."
  "PROVE IT ON A SECOND MACHINE","before a capability is called done, it is exercised from another role, not from the author's own seat. The accept line names the second machine and what it printed."
```

**Enforced by** `bin/bridge/mimir-bridge.sh` (local engine, else the door — the same verb on every role) ·
`bin/records/well-door.sh` (the hand's road, probed at both ends before it is called up) ·
`bin/skuld/role.sh resolve` (the role, once) · `fleet.json` (the registry the role is read from) ·
and the clean-skip convention, which stays law for a layer that genuinely does not apply — but a skip is
never allowed to stand in for a capability the fleet still needs.

**The sentence to carry forward:** *a skip is honest; a skip where the capability was needed is not done.*

## 2026-11-02 (appended) — not every device runs every capability, and the core is what everyone runs

His word this day, while the platform claim was being audited:

> *"all users might not run all features that gimle can do. like if they have a fleet or not. if they have a
> server or not. ymir home and basis ymir runtimes and templetes, extentions to pi, packets to opencode and other
> agent harnesses and logic are the improtant."*

That is a second axis, and this rule did not have it. The first axis asks *"does it work on this device?"*; this
one asks *"should this device have it at all?"* — and the answer is a **tier**, declared, not guessed.

```
tiers[4]{tier,what_it_is,what_it_needs of the host}
  "0 · core","the home (hodd: identity, memory, plans, secrets, daily), the baseline runtime (the portable shell + python3 + git core), the templates and principles (the agent contracts), the skills, and the harness integrations — Pi extensions, the OpenCode package, and the shims for Claude Code / Codex / Cursor","a POSIX shell, python3 and git — nothing else. No fleet, no server, no GPU, no desktop"
  "1 · desk","the local desktop layer: launchers, themes, voice, window rules, placement, crash sense","a desktop session and the layer's own packaging"
  "2 · suite","Gimlé: the gate, Plane, AFFiNE, the whiteboard, Book, the desk, the mirror","a server, containers, and a hostname — one machine that stays up"
  "3 · fleet","roles (heart · forge · dev · hand), the heart's doors, A2A grants, dispatch","two or more machines that can reach each other"
```

**The law that follows, and it bites where the installer already drifted:**

- **Tier 0 installs and passes its gates on a machine with nothing else on it.** If the core needs a role, a
  server, a fleet or a GPU to be *declared* before it will install, the tiering is wrong. Today
  `bin/engine/ymir-install.sh` requires `--role heart|forge|dev|hand`, which is a tier-3 word doing tier-0 work.
- **A higher tier is a named, gated addition.** It detects its own preconditions and reports SKIP with the reason
  when they are absent (a clean skip is a pass), never a silent half-install and never a FAIL for a capability
  the user never asked for.
- **The installer and the updater are profile-aware.** One verb, one flag: `--profile core|desk|suite|fleet`,
  defaulting to `core`; `--role` becomes what it always was — a fleet-tier detail.
- **A feature names its tier where it is documented**, so a reader knows before installing whether they are being
  asked for a laptop, a server or a fleet.

**Why this is the important half of the rule.** The house has spent months making capabilities work on every
*device* while assuming every user wants every *capability*. A person who wants an agent with a home, memory and
a set of principles should not have to answer a question about the heart's role to get one.
