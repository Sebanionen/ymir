## gate · 2026-11-04 — the publish pretest leaves every push

### Why
His word: *"stop testing the npm installation on every push."* `bin/gates/ci-verify.sh` ran
`bin/forge/npm/pr-pretest.sh` on every push and every pull request. That gate packs the real tarball, installs
it in a sandbox, builds four apps and boots them — minutes per run — and it proves nothing about a change that
cannot affect the artifact. Its cost is what makes a push slow enough that the override starts to feel normal,
and a gate that must be routinely skipped is not a gate.

### Mend
- **`bin/gates/ci-verify.sh`** no longer runs the pretest by default; it prints a `SKIP` row naming where the
  proof lives now. `YMIR_PRETEST_ON_PUSH=1` restores the old behaviour for anyone who wants it.
- **`.github/workflows/npm-pretest.yml`** is the new home: `workflow_dispatch`, plus a push to `main` whose
  paths can actually change the artifact (`package.json`, the app build, `bin/forge/npm/**`, any app or package
  manifest, the Vite configs). It runs the **local leg** only — the remote leg needs a seat (heimdall), which is
  a local duty, not CI's.
- Nothing about the proof itself is weakened: `bin/forge/npm/pr-pretest.sh` is unchanged and still refuses a
  tarball that cannot install and boot.

### Proven
- `bash bin/gates/ci-verify.sh --fast` on this branch prints
  `"pr-pretest","SKIP","the publish artifact is proved by .github/workflows/npm-pretest.yml …"`.
- `bash -n bin/gates/ci-verify.sh` clean (the first edit left a stray `fi` and was caught by exactly this).
- The workflow parses (`bin/gates/checks/workflow-check.sh`).
