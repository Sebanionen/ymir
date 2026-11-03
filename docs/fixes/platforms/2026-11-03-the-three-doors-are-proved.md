# The three doors are proved — the packaged Windows door builds again, and a seat is healed by the pull

**Date:** 2026-11-03 · **Component:** platforms / install · **Found while:** auditing two collaborator PRs (Sebastian, #476 and #477)

## Why this note exists

Sebastian ran the **documented Windows path** on a clean Windows 11 host with WSL2 (Ubuntu 26.04.1, systemd) and
rebuilt a 0.1.52 seat to the merged head. He found four faults and fixed two stale pointers in #477. Auditing his
work against this tree found that the class of fault he named is wider than his two files, and that every ward which
should have caught it was either absent, blind, or never run.

RULES/05 lists Windows as a supported host — it hosts Linux through WSL2 — and RULES/25's 2026-10-28 append
demands that a capability answer on every role, not just the machine that built it. The tree did not.

```
faults[7]{fault,why_it_survived,state}:
  "packaging/windows/ymir-setup.nsi named bin\bootstrap-windows.ps1, which has not existed since Rule 22","NSIS resolves `File` to a missing source and fails to compile, and nothing built it","fixed here"
  "ymir-installers.yml ran only on workflow_dispatch and v* tags, and no tag had been cut","gh run list --workflow=ymir-installers.yml was EMPTY, so the broken directive was never compiled","fixed here (pull_request on packaging/**)"
  "packaging/build.sh hid makensis' output and reported only 'makensis failed'","a build error with no reason is a fault nobody can act on","fixed here"
  "bin/host/bootstrap-windows.ps1 called ymir-install.sh --yes with NO role","every role-gated step SKIPs and the install still ends OK — a half-install wearing a green row","fixed here (-Role, default dev, passed through)"
  "the bootstrapper piped git pull --ff-only to `|| true`","a seat could stay a version behind while the installer printed success","fixed here (the refusal is named, with the remedy)"
  "an install rewrote apps/odrerir/public/icon.svg and package-lock.json","`design-icon.sh mint --all` re-minted tracked sources and `npm install` rewrote the lockfile, so the next fast-forward pull refuses","fixed here (mint only what is missing; npm ci when a lockfile exists)"
  "a fresh seat reported 'missing: bun' on a host that has bun","the installer exported ~/.bun/bin into its own shell only; the validator asked `command -v bun`","fixed here (persist-path + a probe that asks the machine)"
```

## What changed

```
changed[10]{path,what}:
  "packaging/windows/ymir-setup.nsi","names ../bin/host/bootstrap-windows.ps1 via File /oname=…, and passes -Role through to the install"
  "packaging/build.sh","preflights every File directive BEFORE asking makensis (so a broken directive is refused on a host with no compiler too), keeps makensis' log and prints its last lines, and no longer lets the macOS copier fail silently"
  "bin/host/bootstrap-windows.ps1","-Role (default dev) passed into the distro; a fast-forward that cannot happen is printed with the local changes and the remedy, never swallowed"
  "bin/engine/prereq-ensure.sh","--persist-path writes a marked PATH block into the profile the operator's shell actually reads (probed: $SHELL; zsh → ~/.zprofile); `resolve <tool>` answers a caller by absolute path"
  "bin/engine/ymir-install.sh","npm ci when a lockfile exists; icons minted only where a source is missing; the PATH is persisted, not just exported for one run"
  "bin/engine/ymir-validate.sh","bun is PROBED at its install locations and its road is named in the row; a scheduler retired for want of a live seat is a SKIP that says so, not a FAIL"
  "bin/gates/guards/path-legality-guard.sh","new ward: every tracked NAME is legal on every host RULES/05 claims — NTFS characters, trailing space/dot, reserved DOS names, 255-byte segments, MAX_PATH, case-only collisions"
  "bin/gates/guards/packaging-guard.sh","new ward: every path a shipped installer names exists, and a packaging copy may not suppress its own failure"
  ".agents/paths-ledger.yaml","the bin/host/ move recorded (it never was) — which is why path-ledger-guard had nothing to refuse"
  ".agents/migrations/0017-the-seat-follows-the-pull.sh","the seat a pull cannot reach: hooks re-seated root-resolving, the PATH written, the pinned runtime reported"
```

## The stray file, retired lawfully

The root file named `Wed 2026-09-30 20:29:43 (1h 22min ago)` (0 bytes, nothing referenced it) carried a `:` that NTFS
cannot hold, so a Windows `git clone` fetched every object and wrote **no tree at all**. Sebastian removed it in #476,
which is the right diagnosis and the wrong door: Rule 11 says a file is **moved**, never deleted, and
`bin/no-delete-guard.sh` has exactly one escape — a stated reason, which is logged. Retired here through that escape:

```sh
YMIR_ALLOW_DELETE="a name no Windows checkout can hold (':' is illegal on NTFS) — 0 bytes, nothing references it, record kept at hodd/reference/repo-strays/2026-09-30-a-shell-redirect-that-named-a-file.md" \
  git rm "Wed 2026-09-30 20:29:43 (1h 22min ago)"
```

The record lives in the home's reference shelf, and `deleted-on-purpose.log` carries the reason. **The idea for the
ward that now refuses this class is Sebastian's** — his fix note asked for "a tracked-path legality check for the
hosts RULES/05 claims". It exists as of this change.

## Rule 11's ward, seated where the rule said it ran

RULES/11 states that `no-delete-guard.sh` runs "in the pre-commit and pre-push chains and in CI". Measured today it
ran in **none** of the three: the pre-commit hook called public/docs/private/vault/confidential/secret; the pre-push
hook called guards/branch/fixes/branch-current; and `ci-verify.sh` had no such gate. It now runs in all three, and
the pre-commit hook resolves its root at run time instead of baking one machine's path — a fault found while
installing it from a **worktree**, where `$ROOT/.git` is a file and the installer could seat no ward at all.

## What is proved, and what is not

**Proved:** every path a shipped installer names exists in this tree (the ward, run on the tree); the preflight
refuses a bad `File` directive by name; the migration runs twice with identical output; a seat's validator no longer
calls a working `bun` missing nor a session-gated scheduler a failure.

**Not proved here:** the `.exe` was not built on this host (`makensis` is absent), and no Windows machine ran this
branch. The workflow now builds both artifacts on any packaging change, and **a clean Windows run of the merged head
is still owed** — that is plan 165's phase 3 acceptance, and it is the Allfather's to dispatch or Sebastian's to
repeat.

## Files

`packaging/windows/ymir-setup.nsi` · `packaging/build.sh` · `bin/host/bootstrap-windows.ps1` ·
`bin/engine/prereq-ensure.sh` · `bin/engine/ymir-install.sh` · `bin/engine/ymir-validate.sh` ·
`bin/gates/guards/path-legality-guard.sh` · `bin/gates/guards/packaging-guard.sh` · `bin/gates/guards.sh` ·
`bin/gates/guards/fixes-guard.sh` · `bin/gates/guards/secret-guard.sh` · `bin/gates/ci-verify.sh` ·
`bin/no-delete-guard.sh` · `bin/agents/eir-doctor.sh` · `.agents/paths-ledger.yaml` ·
`.agents/migrations/0017-the-seat-follows-the-pull.sh` · `.github/workflows/ymir-installers.yml` ·
`.github/workflows/ymir-gates.yml` · `README.md`

## 2026-11-03 (appended) — the gate itself leaves the tree dirty, and that is the same fault

Running `bin/gates/ci-verify.sh` locally (to prove this change) left `package-lock.json` rewritten and the Smiðja
visualizer's `dist/` rebuilt — the same class as the install's own writes: **a step that mutates the checkout it is
judging**. On a seat that runs the gate before a push (which is the point of it), the result is a dirty tree that
blocks the next `git pull --ff-only`, which is the very failure this note is about. `pr-pretest`'s real `npm install`
and `app-build.sh` are the two writers; the fix belongs with plan 165 phase 4 (an install or a gate leaves the tree
byte-identical), and until then the state is named here rather than discovered by the next hand.
