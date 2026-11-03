# Rule 04 — Hodd, the private hoard, and YMIR_HOME

Every private thing the Allfather holds lives in **one** place: **Hodd**
(`hodd/`) at the repo, and **YMIR_HOME** (`$HOME/Documents/Ymir/`) as the
shareable private repo. *Hodd* is Old Norse for a hoard — guarded, and
never shown. The repo holds the **framework** (scaffolds, guards,
templates); the data lives at **YMIR_HOME**, committed and pushed to a
private GitHub repo so it can be shared between machines.

## What belongs in Hodd (at the repo)

Only **scaffolds and guards** live at the repo path `hodd/`:

- **Guards** — `hodd/.gitignore` (inner ward, tracks only itself, README,
  and `*.example` shapes)
- **README** — `hodd/README.md` (this map of the hoard)
- **Scaffolds** — `hodd/AGENTS.example.md`, `hodd/**/*.example` (templates
  so a new operator knows what belongs)

## What lives at YMIR_HOME (the real hoard)

All private data is committed to the **private YMIR_HOME git repo** and
pushed to a **private GitHub repo** for multi-machine sync. It is **NOT**
gitignored — the user owns it and shares it between computers:

| Repo location | YMIR_HOME location |
|---|---|
| `hodd/docs/` | `$YMIR_HOME/docs/` |
| `hodd/secrets/` | `$YMIR_HOME/secrets/` |
| `hodd/identity/` | `$YMIR_HOME/identity/` |
| `hodd/tenants/` | `$YMIR_HOME/tenants/` |
| `data/` | `$YMIR_HOME/data/` |
| `memory/kaia.engram*` | `$YMIR_HOME/memory/` |

## The law

- **Hodd at the repo is untracked.** `hodd/.gitignore` tracks only the guard
  and the README; everything beneath is private on every clone. A clone
  must never inherit another operator's hoard.
- **YMIR_HOME is committed.** All private data at YMIR_HOME is committed
  to the user's **private** git repo and pushed to a private GitHub repo
  for sync between machines. It is never gitignored (except runtime
  ephemera like `*.wal`, `*.shm`, `smidja/`, `state/`).
- **Secrets are referenced, never inlined.** Read them by path — `YMIR_HOARD`
  (default `$YMIR_HOME`), `bin/vault/hodd.sh emit <file>` to set them in a shell. A
  value never enters a tracked file, a commit, or a document.
- **Two wards.** `bin/gates/guards/secret-guard.sh` is the outer ward (pre-commit + CI);
  `hodd/.gitignore` is the inner one. Nothing leaves without passing both.
- **Realm boundaries are sacred.** Private data at YMIR_HOME is
  scoped per operator; a clone must never inherit another's hoard.
- **The public tree keeps only the framework** (lore, architecture, scaffold)
  and `*.example` shapes.
- A change that contradicts this rule must change the rule first (append-only;
  never silently rewritten).

## docs/ is public — plans are not

`docs/` is the **public, user-facing** tree: it holds what a user of Ymir may
read. Operator-private documents — plans, strategy, roadmaps, the masterplan,
`append-only-log`, and project planning — belong in `hodd/docs/` at the repo
(never `docs/`), or live at `$YMIR_HOME/docs/` in the private repo.

`bin/gates/guards/docs-guard.sh` blocks a commit that stages such a document under `docs/`
(wired into the pre-commit hook beside `secret-guard.sh`). When it fires, move
the file to `$YMIR_HOME/docs/` in the private repo.

---

## Correction — 2026-09-17: hodd/ *is* the YMIR_HOME data path

*Appended, citing the sections above; nothing above is rewritten.*

The mapping table above ("What lives at YMIR_HOME") implies a **flat** layout —
`hodd/identity/` → `$YMIR_HOME/identity/`, `data/` → `$YMIR_HOME/data/` — i.e.
that the repo-side `hodd/` and the data path are two different locations. On a
real home that reading produced **two parallel stores**: a flat
`$YMIR_HOME/identity/` and `$YMIR_HOME/data/` alongside `$YMIR_HOME/hodd/identity/`
and `$YMIR_HOME/hodd/data/`. They drifted, and the flat pair went stale.

The truth on a live home, and the intent of this rule:

- **`$YMIR_HOME/hodd/` *is* the private data path.** There is no second, flat
  copy. `identity/`, `data/`, `docs/`, `secrets/`, `tenants/`, and the memory
  well live **under `hodd/`**.
- **`bin/vault/hoard-lib.sh` is the single source of truth** for that path: it
  resolves `${YMIR_HOARD:-${YMIR_HOME:-$HOME/Documents/Ymir}/hodd}`. A script
  that needs the hoard calls `hoard_root`, never a hardcoded path.
- **`.ymir-layout.yaml` records the real layout** and must name only paths that
  exist. A layout entry pointing at a nonexistent directory is stale, and a
  stale map is what let private work land outside the hoard.
- The three-way reading in the section above (`hodd/x/` → `$YMIR_HOME/x/`) is
  **superseded**: read every row as `$YMIR_HOME/hodd/x/`.
- The "docs/ is public" section's closing line ("move the file to
  `$YMIR_HOME/docs/`") is likewise read as **`$YMIR_HOME/hodd/docs/`**.

Confirmed by the Allfather 2026-09-17. Drift of this kind is caught by
`bin/agents/eir-doctor.sh`'s hoard placement check.

---

## Appended 2026-10-01 — personal data is not only secrets; the ward must see it

The first law says: *never store personal or private data in this repo — not a
secret, a key, a name, a plan, a schedule, a client, a credential, or a note.*

Read until now, the automated wards enforced only the **secret** half.

- `bin/gates/guards/secret-guard.sh` scanned content for **credential values** (keys, tokens).
- `bin/gates/guards/private-guard.sh` scanned **paths** for private roots.
- **Nothing scanned file content for who the operator IS or WHERE their machines
  live.** So an operator username, a tailnet domain, a personal hostname and a
  fleet hardware inventory were committed and pushed to a public remote while
  every gate reported green. Measured 2026-10-01 across `origin` =
  `github.com/zerwiz/ymir` (public).

**The law, as the Allfather laid it down:**

1. A person's **identity and topology are personal data** whether or not they are
   a secret. Username, home path, tailnet domain, hostnames, machine names and
   the fleet's hardware inventory are **never** committed to this repo.
2. **Local-model knowledge is never in this repo, under any circumstances.**
   The modeltesting skill, its benchmarks, VRAM ceilings, measured prefill/decode
   and per-seat host profiles are **operator-specific** and live at
   **`$YMIR_HOME/.agents/skills/modeltesting`**. This repo may carry only the
   *doctrine* — which engines exist, how to detect them, why honest measurement
   beats a lucky load — never the measurements, the hosts, or the numbers.
   (Supersedes commit `cb5c2f1`, 2026-09-12, which moved the skill to a galdr
   asset; the asset remains doctrine, the skill is the Allfather's own.)
3. The **public way** to say a private thing is a placeholder: `$HOME`,
   `$HOME_SEAT`, `<user>`, `<host>`, `<tailnet>`, `<gpu>`, `<seat>`, `<home>`.
   Docs use the placeholder and stay universal; the value stays in the hoard.
4. The wards must **fail** on this class, not merely be able to. A test that
   cannot fail on the leak is not a test.

**The ward:** `bin/gates/guards/private-guard.sh` now scans content for identity/topology by
**shape, never by value** — a literal `/home/<name>/`, a `*.ts.net` tailnet host,
a CGNAT `100.64/10` address — and exempts synthetic fixtures and `.example`
files. It deliberately contains **no** operator name, domain or hostname: naming
them in the guard would re-create the very leak the guard exists to stop.

Confirmed by the Allfather 2026-10-01. Law 06: this entry is appended, never
rewritten; a correction is a new entry citing this one.

---

## Appended 2026-10-01 — data comes FROM the hoard; the repo holds only craft

Laid down by the Allfather, following the entry above.

The repo must not merely *avoid* personal data — it must not **contain a copy of
it in any form**, not even a placeholder that a human filled in once. Every piece
of operator data is **read at run time from `$YMIR_HOME`**, and the repo ships
only the *function* that reads it.

| Belongs in `$YMIR_HOME` (data) | Belongs in this repo (craft) |
|---|---|
| the modeltesting skill, benchmarks, VRAM ceilings, host profiles | the doctrine: which engines exist, how to detect them |
| machine / seat inventories, topology, hostnames | `.example` **shapes** with synthetic names |
| the operator's model ids, context windows, measured limits | the scripts that read `$YMIR_HOME` and decide |

Rules:

1. **No copy.** A value that exists in the hoard is never also pasted into the
   repo — not as a value, not as an "example" filled with the real thing.
2. **Examples are synthetic.** An `.example` carries a made-up name
   (`h1.<host>.tailnet.ts.net`, `/home/alice`), never a real seat, domain or user. A ward
   enforces it; see `bin/gates/guards/private-guard.sh` and the exempt-fixture rule in
   `.agents/tests/private-guard-identity.test.sh`.
3. **Functions read the hoard.** Anything needing operator data resolves it
   through `bin/vault/hoard-lib.sh` (`hoard_root`) at run time. A machine that has no
   hoard says so loudly; it never falls back to a value baked into the tree.
4. **One source of truth.** When the data and the repo disagree, the hoard is
   right and the repo is drift.

Confirmed by the Allfather 2026-10-01. Appended under Law 06; a correction is a
new entry citing this one.

`bin/agents/eir-doctor.sh`'s hoard placement check.

---

## Appended 2026-10-01 — personal data is not only secrets; the ward must see it

The first law says: *never store personal or private data in this repo — not a
secret, a key, a name, a plan, a schedule, a client, a credential, or a note.*

Read until now, the automated wards enforced only the **secret** half.

- `bin/gates/guards/secret-guard.sh` scanned content for **credential values** (keys, tokens).
- `bin/gates/guards/private-guard.sh` scanned **paths** for private roots.
- **Nothing scanned file content for who the operator IS or WHERE their machines
  live.** So an operator username, a tailnet domain, a personal hostname and a
  fleet hardware inventory were committed and pushed to a public remote while
  every gate reported green. Measured 2026-10-01 across `origin` =
  `github.com/zerwiz/ymir` (public).

**The law, as the Allfather laid it down:**

1. A person's **identity and topology are personal data** whether or not they are
   a secret. Username, home path, tailnet domain, hostnames, machine names and
   the fleet's hardware inventory are **never** committed to this repo.
2. **Local-model knowledge is never in this repo, under any circumstances.**
   The modeltesting skill, its benchmarks, VRAM ceilings, measured prefill/decode
   and per-seat host profiles are **operator-specific** and live at
   **`$YMIR_HOME/.agents/skills/modeltesting`**. This repo may carry only the
   *doctrine* — which engines exist, how to detect them, why honest measurement
   beats a lucky load — never the measurements, the hosts, or the numbers.
   (Supersedes commit `cb5c2f1`, 2026-09-12, which moved the skill to a galdr
   asset; the asset remains doctrine, the skill is the Allfather's own.)
3. The **public way** to say a private thing is a placeholder: `$HOME`,
   `$HOME_SEAT`, `<user>`, `<host>`, `<tailnet>`, `<gpu>`, `<seat>`, `<home>`.
   Docs use the placeholder and stay universal; the value stays in the hoard.
4. The wards must **fail** on this class, not merely be able to. A test that
   cannot fail on the leak is not a test.

**The ward:** `bin/gates/guards/private-guard.sh` now scans content for identity/topology by
**shape, never by value** — a literal `/home/<name>/`, a `*.ts.net` tailnet host,
a CGNAT `100.64/10` address — and exempts synthetic fixtures and `.example`
files. It deliberately contains **no** operator name, domain or hostname: naming
them in the guard would re-create the very leak the guard exists to stop.

Confirmed by the Allfather 2026-10-01. Law 06: this entry is appended, never
rewritten; a correction is a new entry citing this one.

---

## Appended 2026-10-01 — data comes FROM the hoard; the repo holds only craft

Laid down by the Allfather, following the entry above.

The repo must not merely *avoid* personal data — it must not **contain a copy of
it in any form**, not even a placeholder that a human filled in once. Every piece
of operator data is **read at run time from `$YMIR_HOME`**, and the repo ships
only the *function* that reads it.

| Belongs in `$YMIR_HOME` (data) | Belongs in this repo (craft) |
|---|---|
| the modeltesting skill, benchmarks, VRAM ceilings, host profiles | the doctrine: which engines exist, how to detect them |
| machine / seat inventories, topology, hostnames | `.example` **shapes** with synthetic names |
| the operator's model ids, context windows, measured limits | the scripts that read `$YMIR_HOME` and decide |

Rules:

1. **No copy.** A value that exists in the hoard is never also pasted into the
   repo — not as a value, not as an "example" filled with the real thing.
2. **Examples are synthetic.** An `.example` carries a made-up name
   (`h1.<host>.tailnet.ts.net`, `/home/alice`), never a real seat, domain or user. A ward
   enforces it; see `bin/gates/guards/private-guard.sh` and the exempt-fixture rule in
   `.agents/tests/private-guard-identity.test.sh`.
3. **Functions read the hoard.** Anything needing operator data resolves it
   through `bin/vault/hoard-lib.sh` (`hoard_root`) at run time. A machine that has no
   hoard says so loudly; it never falls back to a value baked into the tree.
4. **One source of truth.** When the data and the repo disagree, the hoard is
   right and the repo is drift.

Confirmed by the Allfather 2026-10-01. Appended under Law 06; a correction is a
new entry citing this one.


---

## Appended 2026-10-10 — the repo is the door users install; the home is personal; every command must resolve to shipped craft

Laid down by the Allfather, asking: *"are all needed scripts for Ymir function
getting from the ymir repo? That's the door the users get. And the ymir home is
personal, so those scripts are not reachable for a user except us."*

The answer, and the law:

1. **The repo is the door.** A user installs Ymir from this repo (clone,
   `install.sh`, or the npm package). Every script the runtime *needs* to
   function must ship here. Nothing a job runs may live only on the author's
   machine.
2. **The home is personal.** `$YMIR_HOME` holds **data** — config, secrets, state,
   workspaces, plans, the vault. It is not a delivery channel: a script kept only
   in a home is invisible to every other user, and to a fresh install.
3. **Cron law — commands must ship, schedules may differ.** Nornir runs every job
   from the **repo root** (`home=$ROOT`; measured 2026-10-10), so in a cron line
   `bin/…` ALWAYS means `<repo>/bin/…`. Schedules are per user and per seat —
   times, roles, which jobs — and that is deliberate and fine; but the
   **commands** must resolve to a script that **ships in the repo**. A personal
   script referenced as `bin/…` can never resolve: the job fires and the command
   is not found. A script the schedule needs belongs in the repo.
4. **Secrets.** `bin/gates/guards/secret-guard.sh --all` is **clean** — no secret
   value lives in this repo. Secrets live at `$YMIR_HOME/hodd/secrets/`
   (age-encrypted; read through `bin/vault/hodd.sh`).

**The ward:** `bin/gates/guards/cron-guard.sh`, seated in `guards.sh`'s `WARDS`
(so the pre-push hook and CI run it). It reads the effective cron
(`$YMIR_CRON_FILE` → the operator's home cron → the shipped
`config/cron.yaml.example`), extracts every `bin/*.sh` on a non-comment line, and
refuses any that does not ship under the repo root.

**What it found on 2026-10-10 (11 findings):** the operator's private home cron
used pre-`bin/`-move paths (`bin/nornir-job-*.sh` where the scripts live at  # allow-superseded-path: this line RECORDS the move, it does not make it
`bin/time/…`; `bin/agents/eindri-handoff.sh` at `bin/agents/…`) — every job unfindable —
and named `bin/time/well-vault-sync.sh`, which existed **only in the home**. Fixed: the  # allow-superseded-path: this line RECORDS the move
well sync now ships as `bin/time/well-vault-sync.sh` (generic; it resolves the
home through `bin/vault/hoard-lib.sh`, never guesses it), and the private cron was
corrected to the moved paths.

Confirmed by the Allfather 2026-10-10. Appended under Law 06; a correction is a
new entry citing this one.

## Correction — 2026-10-11 · the two wards moved, and the check kept calling the old paths

**Cites:** the ward paragraphs above (the lines naming `bin/gates/guards/private-guard.sh` and
`bin/gates/guards/secret-guard.sh`) and the appended Rule 04 section of 2026-10-01.

The `bin/` move seated both wards under `bin/gates/guards/`:

```
  the private ward   bin/gates/guards/private-guard.sh
  the secret ward    bin/gates/guards/secret-guard.sh
```

`bin/gates/guards/private-guard.sh` and `bin/gates/guards/secret-guard.sh` no longer exist. Every reference
above is therefore a path to nothing — and the compliance gate, which called them
by those paths, was failing with an **empty** reason: bash answered
`No such file or directory`, the ward's own summary line never printed, and the row
read `FAIL — private-guard: `. The hoard boundary went **unjudged**, silently, from
the move until this correction, while the gate looked merely red with nothing to
say. The one test that proves the ward fails on personal data,
`.agents/tests/private-guard-identity.test.sh`, was dead the same way.

**The law stands unchanged.** What is recorded here is where the ward lives, not
what it judges: a wrong path is a silent ward, and a silent ward is no ward.
Correction, not rewrite — the text above is left exactly as it was written.

## 2026-10-21 — a person is private data (appended)

**Measured, and merged before it was noticed.** The public repository carried a collaborator's **full
name and two email addresses** in `FEATURES.md`, a feature page and two fix notes. Every ward passed.

Three reasons, each worth keeping:

1. **`private-guard` watches paths, vault references and secret shapes** — not names. A name is not a
   path and not a key.
2. **Rule 26 explicitly allows a participant's name** — correctly, on a *meeting record*, which is an
   external artifact. A **public repository is not a meeting record**; it is the store from which every
   artifact and every clone is made.
3. **Nothing said "a person is private data."** A missing sentence is how a gate passes.

```
person_law[4]{rule,why}:
  "a person named in the operator's registries is PRIVATE DATA","their name, their address, their number — the widest surface in the house is the public tree, and a clone outlives any correction"
  "the registries are the source of the prohibition, not a dictionary of names","a public author quoted in research is not a 'person' in this sense; the guard compares against `collaborators.yaml` and the NDA register"
  "the public tree names a ROLE, never a person","'a prospective collaborator', 'the client', 'the operator' — the record still says what happened without saying who"
  "history is not rewritten to hide it","a name already merged stays in history; removing it means a force-push across every clone, which is the operator's explicit decision and never a tidiness edit"
```

**Enforced by `bin/gates/guards/people-guard.sh`** (in `guards.sh`): it builds the list from the
registries at push time and fails on any occurrence in the tree, with file and line. Proved to fail on
a probe file, and clean afterwards.

**And one plain instruction for every agent:** when a document needs to say *who*, write the role.
A name in this tree is not a detail — it is a person's data, published for ever.


---

## Appended 2026-11-03 — the repository carries TEMPLATES and LOGIC, and nothing else

**At the Allfather's word, after a violation found in this repository on this day:**

> *"YMIR CAN ONLY CARRY TEMPLASTE AND LOCIG:: NOT SECREATS OR PRIVATE DATA::"*
> *"ymir are a PUBLIC repo!!"*
> *"WE CAN NOT STORE PERSONAL DATA IN YMIR TAHTA BELONG IN YMIR HOME!!"*

Everything above stands. This section names the two clauses the automated wards had missed, so that the next ward is
written against them and not against a taste.

```
repo_carries[2]{what,examples}:
  "TEMPLATES","`*.example` with synthetic names, JSON/YAML schemas, and public defaults that name no real seat, project, company, client, host or person"
  "LOGIC","the code that reads the home at run time — `bin/vault/hoard-lib.sh`, the resolvers, the wards — functions, never values"

repo_never_carries[4]{what,rule}:
  "an author identity that is a private mailbox","a commit's author line IS data in this repository, in every `git log`, every page, every fork. A commit is made as the ACCOUNT (`<id>+<login>@users.noreply.github.com`) or as a house identity (`*@ymir`, `*@ymir.local`, `*@zerwiz.org`); enforced by `bin/gates/guards/identity-guard.sh` in the pre-push chain and in CI"
  "a private address, a tailnet name, a hostname or a machine name — including in a FIXTURE","a private address appears only as a CIDR range (`192.168.0.0/16`, `192.0.2.0/10`) or in RFC 5737 space (`192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`); a tailnet name only as the shape `<host>.<host>.tailnet.ts.net`; a mailbox only as an RFC 2606 example domain, a noreply account form, or a house address — enforced by `bin/gates/guards/public-guard.sh --tree`"
  "the operator's or a client's name, in a guard, a document or a fixture","the words live in `$YMIR_HOME/hodd/security/public-tokens.txt`; the repository carries the door that reads it at run time"
  "a shipped default that has to name a place","a default is resolved from the home or refused; a real address as a code default ('one documented default' in RULES/07) is not a default, it is a leak with a fallback"
```

**The clause about the ward itself, quoted from the 2026-10-01 append because this day broke it:** *a guard "deliberately
contains no operator name, domain or hostname: naming them in the guard would re-create the very leak the guard exists
to stop."* Measured 2026-11-03: `public-guard.sh` carried the operator's personal name as two literal alternatives, in a
public file, for a month — and its `$HOME` alternative, being inside a single-quoted string, never expanded, so it
matched nothing. **A ward that names what it forbids is the leak; a ward whose pattern cannot match is decoration.**

**Also named here, and not fixed by a ward:** the commits already pushed carry whatever identity they were made with.
Unmaking them is a history rewrite and the operator's decision — plan 171, phase 4.

A change that contradicts this rule must change the rule first (append-only; never silently rewritten).
