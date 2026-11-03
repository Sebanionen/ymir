# The Windows door was run — a clean Windows host raised the Linux seat and installed it

**Date:** 2026-11-03 · **Component:** platforms / install · **Found while:** rebuilding an operator's WSL seat

## Why this note exists

The 2026-11-02 append to RULES/05 ended with a sentence the tree had not earned and could not answer:

> Windows is packaged, not proved — run it on a clean machine before telling anyone it works.

This note is that run. A Windows 11 host with WSL2 (Ubuntu 26.04.1 LTS, systemd enabled in
`/etc/wsl.conf`, node v22.22.1) hosted a Linux seat that stood on **0.1.52**, installed as a plain
non-git tree (`~/code/ymir`) with ten systemd user units executing from it. It was rebuilt to the
merged head (`b247b13d`, 0.2.0) entirely by the documented path, in this order:

```
steps[6]{step,what_happened}:
  "clone","the fork checkout moved to the merged head; the old installed tree was retired, not deleted"
  "pinned runtime","a checkout at ~/ymir-runtime — the RULES/02 §7 shape; runtime-deploy.sh --check: deployed <head> = origin/main"
  "install","bin/engine/ymir-install.sh --role dev --yes --no-desktop, with YMIR_SKIP_LOCAL_MODEL=1 because the host already ran its own model rail"
  "seat","37 steps; the units were re-pointed at the pinned runtime; ymir.target enabled; all nine active"
  "validate","gate API 200 · SPA 200 · Bifrost · Mimir · Smidja · sandbox image · registry · runes — PASS"
  "repair","fleet-ensure re-seated every role-owed program; gateway smoke 7/7 PASS"
```

The Windows bootstrapper itself (`bin/host/bootstrap-windows.ps1`) was exercised on this host in
`-Check` form and by hand rather than end-to-end, because WSL2 + Ubuntu already stood: the script's
Linux half — clone, `git pull --ff-only`, `bin/engine/ymir-install.sh --yes` — is exactly what ran.

## What the run found

```
found[4]{finding,state}:
  "bun on PATH","prereq-ensure installs ~/.bun/bin/bun, and a non-interactive shell then cannot see it — the validator reports 'missing: bun' on a host that has it"
  "fleet was owed but did not stand","the installer's own fleet step FAILED; the remedy it printed (bin/fleet/fleet-ensure.sh ensure) seated all nine units"
  "cron is session-gated, by design","nornir retires without a live brokk.lock and says so in state/cron.log — a validator that reads pid files alone calls that a failure"
  "two tracked files rewritten","the install modified apps/odrerir/public/icon.svg and package-lock.json in the runtime checkout — the tree is not left byte-identical by an install"
```

And the Windows-specific one that started this: the README's Windows row and the bootstrapper's own
usage header both named `bin/bootstrap-windows.ps1`, a path that has not existed since Rule 22 moved
the host layers under `bin/host/`. Both are corrected here.

## What is still not proved

The NSIS `.exe` was not built from a tag in this run, no signed artefact exists, and the winget and
scoop manifests still carry placeholder hashes — so **"the install path works on Windows"** is now
true for the bootstrapper-and-clone door, and remains untrue for the packaged one. The installer
workflow has still never executed in CI.
