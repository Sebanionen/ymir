## install · unversioned · 2026-11-02 — the home is a contract: what the runtime reads now ships as a shape

### Why

At ten thousand downloads, a missing template is the same papercut ten thousand times on
machines nobody can ssh into — and it fails silently, which is the worst property a boot
fault can have.

Measured this day by raising a home in a temp directory and running the session digest
against it, exactly as a new user's first session would:

```
ABSENT: hodd/data/operator.md       the standing preferences, read at every start
ABSENT: hodd/data/projects.md       the project registry in prose
ABSENT: hodd/data/learnings.md      the facts the digest prints
ABSENT: <realm>/HOOD.md             the holdings map the digest prints whole
refused: hodd/identity/seats.yaml   "roster not readable" — the seat could not be named
realm fell back to `default`, with no .env.realm
```

Five documents a session opens with, and a fresh home held none of them. They existed on
this machine only because a hand wrote them there over months — Rule 04's fault, one shelf
over: work that is correct and unreachable. Thirty-four `.example` shapes did ship, so the
gap was not "nothing ships"; it was that **only what somebody remembered to templatise
shipped, and nothing measured the difference.**

A second fault, same hour, in the same class: `step_tree()` wrote
`hodd/identity/workspaces.yaml` from an **inline heredoc whose shape its own shipped
template did not teach**, while `registry/workspaces.yaml.example` taught a different one.
Two writers of one file, and the user gets whichever the code path happened to run.

A third, found while auditing the ward that was supposed to catch the first two: `hodd/`
`.gitignore` said *"track only this file, the README, and `*.example` shapes"* — and `*`
swallowed the directory, so a template could not be committed beside the shelf whose file
it teaches. `hodd/data/operator.md.example` was refused by the guard whose sentence
promises it. The intent was right; the pattern did not implement it.

### Files

- `RULES/42-the-home-is-a-contract.md` (+ its `RULES/README.md` row) — the law: every file
  the runtime reads ships as a shape, arrives by one door, is healed by an update, and is
  named in one contract a ward reads.
- `.agents/home-contract.yaml` — the contract itself: 45 rows, each with `path · kind ·
  template · door · required · why`; kinds are `seeded · stub · defaulted · optional ·
  generated`, so a file that must be raised and a file that is a door's output are never
  confused again.
- `bin/engine/home-seed.sh` — the ONE seeder and the ONE parser of the contract. Seeds only
  the rows whose door is itself, never overwrites, fails loudly naming a row whose template
  is missing, and prints the one command that names an empty-roster seat.
- `bin/engine/ymir-install.sh` — `step_tree()` no longer writes `workspaces.yaml` or
  `projects.yaml` by hand; it calls the doors that own them. 1754 → 1742 lines, two sources
  of one truth gone.
- `bin/identity/registers-seed.sh` — now the one owner of all four identity registers
  (`companies · clients · projects · workspaces`), which is what its own header claimed.
- `.agents/migrations/0016-home-contract.sh` — the update door: heals an existing home
  forward, additively, and refuses to touch a file that exists.
- `bin/gates/checks/home-contract-check.sh` + `bin/gates/guards/home-contract-guard.sh` +
  its `guards.sh` row — the ward. It refuses a row whose template or door does not exist, a
  required file with no shape, a line the parser cannot read, a home file claimed twice, and
  a template no row names.
- `hodd/data/{operator,learnings,machines,projects}.md.example`,
  `hodd/identity/seats.yaml.example`, `svartalfaheim/examples/HOOD.md.example` — six stubs:
  an empty shape with a prompt, placeholders only, zero private values.
- `hodd/.gitignore` — `!*/`, so the sentence it already carried is true beneath `hodd/`.

### Proof

- `bin/gates/guards.sh` — 18/18 PASS, `home-contract-guard` among them.
- The ward was proved by breaking what it watches: a moved template, an orphan template and
  a line the parser cannot read each produced a FAIL naming the row and the remedy, and the
  tree went clean again when restored.
- A temp home + migration `0016` produced 16 files and a digest with no ABSENT line; the
  second run seeded nothing and said so.
- `rendered`: `home_contract[3]{rows,findings,state}: "45","0","clean"`.

### Not done, and named

A `defaulted` row (`config/cron.yaml`, `config/model-catalog.yaml`, `config/guardian.yaml`,
`config/garmr-rules.yaml`, `config/logretta-stack.yaml`, `config/suite-workspaces.yaml`,
`config/tenant-terms.txt`) is still read through a shipped-default fallback in its reader.
Rule 42 requires that reader to **say which file answered**; that sentence is owed in
each door and is recorded in the audit
(`hodd/docs/audits/2026-11-02-the-home-contract-audit.md`, finding F6).
