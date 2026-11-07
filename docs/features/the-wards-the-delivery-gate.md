# The wards — the delivery gate

## What it is

The **wards** are Ymir's tree gates. Before a change leaves a machine, the wards judge
it non‑zero‑or‑nothing: a secret, a private path, a guessed default, a broken schedule,
an uncatalogued page, a copied vault file, an out‑of‑vault write, dead code — each has
a ward, and any hit **refuses the push**. They run in the pre‑push hook **and** in CI,
so the gate is the same on every machine.

## What you need

- Nothing extra. The wards are scripts under `bin/gates/guards/` and run with the shell.

## Do it

```bash
# every ward, on this tree
bin/gates/guards.sh

# just the names
bin/gates/guards.sh --list
```

You will get one row per ward — `PASS`, or `FAIL` with the finding:

```
guards[7]{ward,status,finding}:
  "runtime-guard","PASS",""
  "defaults-guard","PASS",""
  "cron-guard","PASS",""
  "features-guard","PASS",""
  "vault-guard","PASS",""
  "confidential-guard","PASS",""
  "dead-code-guard","PASS",""
```

Run a single ward directly when you want its detail:

```bash
bin/gates/guards/defaults-guard.sh check     # one ward, full findings
bin/gates/guards/secret-guard.sh --all       # every tracked file, once
bin/gates/guards/private-guard.sh --all
```

Wards also run themselves:

- **`bin/gates/guards.sh`** — the pre‑push hook and both CI hosts call it; a fault
  stops the push.
- **pre‑commit** — `secret-guard --install` seats the repo hook (public, docs, private,
  vault, confidential, secret); `hoard-guard --install` seats the home's. Git runs them
  on every commit, including the hasty ones.

## The wards

| Ward | What it refuses |
|---|---|
| `runtime-guard` | the tree becoming a runtime |
| `defaults-guard` | a guessed home/default (Rule 07) |
| `cron-guard` | a cron job naming a script that does not ship |
| `features-guard` | a `docs/features/` page not in `FEATURES.md` (Rule 14) |
| `vault-guard` | a file copying the open vault verbatim (Rule 15) |
| `confidential-guard` | a commit outside the vault during a session (Rule 16) |
| `dead-code-guard` | an unreached file, function, branch or constant (Rule 17) |
| `secret-guard` · `private-guard` · `public-guard` · `docs-guard` | a credential, a private path, a live secret shape, a private doc under `docs/` |
| `branch-guard` | a push to a protected branch |
| `fixes-guard` | a push range with no fix note |

## Notes and limits

- **A gate that does not say why is an obstacle.** Every ward prints the finding and
  the remedy; read the `help:` line.
- **The gate is not a formality.** A `FAIL` means the change does not leave — fix the
  cause, don't bypass it. The one loud override is `YMIR_SKIP_FIXES_GUARD=1` for the
  fix‑note ward; everything else has no bypass by design.
- **Never push to a protected branch.** Delivery is a **PR** (Rule 08); the ward makes
  a direct push impossible.

## If it does not work

| What you see | What to do |
|---|---|
| A ward `FAIL`s on push | Read its remedy; fix the cause. `bin/gates/guards/<ward>.sh check` shows the detail. |
| `fixes-guard: no fix note in this range` | Add a note under `docs/fixes/<component>/` for THIS push range (`bin/gates/fixes.sh record --component=…`). |
| A pre‑commit refuses | The same wards run on commit — fix it before committing, or you are committing a leak. |
| CI fails but the push passed | CI runs the same `guards.sh`; the difference is the tree — re‑run it locally and read the FAIL. |

## The ship door — the PR is what ships, not the push (2026-11-06)

A branch push is how work travels; a pull request is how work ships. Those are two doors, and the
house now names them apart.

A **smith** — a worker agent — pushes its own branch, under a namespaced name like `eins/<id>`, and
writes a handoff packet carrying the branch and its head sha. It may never open a pull request and
may never merge. The **reviewer** fetches the branch, refuses it if the fetched sha is not the sha in
the packet, runs the rules floor and the tests on that commit, and only then opens the PR and merges.

Two doors enforce it. `branch-guard` keeps the only push refusal that survives: a push that lands on
`main`. `pr-ship-guard` judges every open pull request by its **author**: a PR opened by a login in
the smith registry is refused, and the refusal names the PR, its head and the way back.

To name your smiths, copy `hodd/identity/smiths.txt.example` to
`$YMIR_HOME/hodd/identity/smiths.txt` and list one GitHub login per line. With no registry the ward
skips and says so — never a silent pass.

```
bash bin/gates/guards/pr-ship-guard.sh --author <login>   # judge one login, no network
bash bin/gates/guards/pr-ship-guard.sh check              # judge every open PR
```

**If it does not work:** a refusal naming a login means a worker opened a PR — close it and let the
reviewer open its own from the pushed branch. A `SKIP` line is not a failure; it names what is
missing (no registry, no `gh`, no network) and the gate resumes once that exists.
