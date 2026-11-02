# Rule 02 — Agents (Brokk, the Eindri, and where they live)

**Status:** law. Read with Rule 01 (domains · houses · Eindri).

## 1. One home for agents

Agent profiles live **only** in **`.agents/agents/*.md`**. That directory is the
source of truth; everything else binds to it.

- Harness directories are **symlinks**, never copies:
  - OpenCode: `.opencode/agents/<name>.md` → `../../.agents/agents/<profile>.md`
  - Pi: `.pi/agents/<profile>.md` → the same canonical files
- **Never edit** `.opencode/agents` or `.pi/agents` — they are links. Edit
  `.agents/agents/<profile>.md` and re-run `bin/seat/valknut-load.sh --all`.

## 2. The two kinds of agent

| Kind | Who | Where |
|---|---|---|
| **Primary** | **Brokk** — the bellows; sole contact with the Allfather | `.agents/agents/brokk.md` |
| **Eindri** | the workers — isolated smiths in Utgard on Yggdrasil worktrees | `.agents/agents/<name>-<craft>.md` |

Every **Eindri** is a **specialist**: a marketer, a builder, a researcher, a
planner, a reviewer, a documenter, a scout, and their kin. An Eindri is never a
domain and never a house (Rule 01).

## 3. The profile contract

Every profile carries, in frontmatter:

```
name        the agent id (short, lowercase)      e.g. sindri
norse_name  the figure the craft is named for    e.g. Sindri
descriptor  the craft in a word                  e.g. smith
domain      the field it belongs to (Rule 01)    e.g. brokkforge
role        the functional role                  e.g. developer
capabilities  the skills list
tools       the allowed tools
mode/model/permission   the harness binding (OpenCode) — from the canonical
```

- **Name for the role, never the mood.** The Norse figure must match the craft
  (Sindri smiths, Bragi sings, Mímir remembers, Förseti judges).
- **Domains:** agents knowledgeable about the **system itself** belong to
  **Ymir Labs** (`ymirlabs`).
- The file name is `<name>-<craft>.md`; the harness link is `<name>.md`.

## 4. No mock agents

- Agent ids, names, domains, models, and status must be **real** and sourced
  (from the profile, the harness config, or live signals). **Never fabricate**
  status, traceability, task counts, or uptime.
- The **demo** roster (`apps/hlidskjalf/src/data/mock.ts` <!-- stale-ok: named as the mock this rule forbids; the file is gone --) is the single, clearly
  labelled mock and appears only in demo mode; it never stands in for live data.

## 5. Changing an agent

1. Edit `.agents/agents/<name>-<craft>.md`.
2. Run `bin/seat/valknut-load.sh --all` to rebind the harness symlinks.
3. If a governed path changed, update the owning Galdr asset in the same change
   (compliance gate `assets`).

## Permissions — bash is the hole

- A profile's `permission:` block is law for that agent over the tools.
- **A flat `bash: allow` is a total shell and overrides every `edit`/`write`
  deny.** A read-only agent with `edit: deny` but `bash: allow` can still write,
  delete, and reach the network. Never give a read-only agent a flat
  `bash: allow`; give it a **pattern map** — only the read commands it needs are
  `allow`, everything else is `ask` or `deny`.
- Network commands (`curl`, `wget`, `ssh`, arbitrary binaries) are `ask` at
  least. Code you do not fully trust belongs in **Utgard** (no host root, no
  network), not on the host behind a permissive shell.
- `mode: all` (runnable) plus a full shell is the widest door — usually not what
  you want.
- `bin/gates/guards/perm-guard.sh` flags any profile with a flat `bash: allow`
  (`--strict` exits 1). Run it before claiming an agent change done; see the
  runbook `docs/runbooks/agent-permissions.md`.

## 6. The review figure — the automatic PR-review spine (appended 2026-09-27)

The **reviewer** role is sealed to **Forseti** (`.agents/agents/forseti-reviewer.md`),
the judge of the Eindri. Every ship errand that reaches `done` with a PR has a
dedicated review errand seated for it — `<id>-review`, a **scout-kind** errand
launched through the einherjar road on the `pi` harness — before the Allfather's
seal. The mechanism is `bin/agents/eindri-review-spawn.sh`, called from the terminal act
(`bin/agents/eindri-acclaim.sh --terminal done`); it fires **once per task** (the
`.reviewed` marker), and `YMIR_AUTO_REVIEW=off` is the loud override.

Law, unchanged and restated: edit the **canonical** card in `.agents/agents/` and
re-run `bin/seat/valknut-load.sh --all`; **never** edit the harness directories by
hand. The judge's card keeps `edit: deny` / `write: deny` — the spine only ever
reads the branch it judges.

## 7. The runtime is a pinned checkout, never a working tree (appended 2026-11-02)

His question this day: *"what happends if one agent are changing from one branch to another forr ymir systems? do we
need to run some things in containers or something to make it more stable."*

**The measurement that prompted it.** On this seat, **ten systemd user units execute files from
`/home/heimdall/ymir`** — the same directory agents check branches out in:

```
units[10]{unit,what}
  "nornir","the scheduler — every cron row spawns a job from this tree"
  "mimir","the well bridge"
  "bifrost","the model bridge"
  "mcp-gateway","the MCP face"
  "housewatch","the watcher"
  "calendar-watch","the calendar poller"
  "garmr-brain","the warden's brain"
  "skirnir-telegram","the Allfather's assistant"
  "skirnir-timer","the stop-rule timer"
  "ymir-syn-watch","the supervision watcher"
```

While this very rule was being written, that tree stood on an **unmerged branch** (`rules/platforms-and-tiers`) —
my own — which means the scheduler, the well, the model bridge, the MCP face, the watcher and the assistant were all
executing unmerged code, with the Allfather's own approval nowhere in the path. Earlier the same day another hand
switched the same tree to `feat/brokk-tool-calls` mid-session, and a `git pull --ff-only` failed underneath a
running agent.

**The law.**

```
pinned_runtime[5]{rule,why}
  "A unit executes from a PINNED CHECKOUT, never from a working tree","a checkout that only ever stands on the default branch; the working tree agents switch on is their own business"
  "A DEPLOY MOVES THE PINNED CHECKOUT AND PROVES IT","one verb (the shape bin/gimle/deploy.sh already proves): fetch, move to origin/<default>, restart, and report the commit that is running"
  "AN AGENT WORKS IN A WORKTREE (Yggdrasil), NEVER IN THE PINNED ONE","isolation by default; the main hall is a place to think, not a place to leave a branch checked out"
  "CONTAINERS ARE NOT THE FIX FOR THIS","a container running the same mounted working tree inherits the same drift; containers belong where isolation of UNTRUSTED code is the point (Utgard), not where version discipline is"
  "A RUNNING VERSION IS READABLE","every long-running unit reports the commit it runs, so 'what is deployed' is answered by asking the machine, never by memory"
```

This is the same sentence the Gimlé suite learned the hard way on 2026-11-02: a deployment is a version, not a copy.
The suite was fixed first because its drift was visible in the desk; the runtime has been drifting where nobody looks.
