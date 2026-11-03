# The platform claim, measured — Linux runs, macOS and Windows host Linux

**Date:** 2026-11-02 · **Component:** platforms · **At the Allfather's word:** *"make sure ymir can run on any
hardwhere and operations system the users are using"*

## What was claimed, and what is true

RULES/05 says the core is portable and macOS and Windows "bring their own layer". Measured against the tree:

- **Linux runs**: Omarchy (verified), other Linux distros via the portable core, SteamOS (verified 2026-10-19),
  Termux as a partial `hand`.
- **macOS and Windows do not run Ymir natively.** `bin/host/bootstrap-macos.sh` raises a **Lima VM**;
  `bin/host/bootstrap-windows.ps1` raises **Ubuntu on WSL2**; the installer is then run *inside* that Linux.
  This is honest and already documented in the README — and it is a different claim from "runs on any OS".
- **The portability shim is not the road taken**: only 24 of 667 shell scripts source
  `bin/fleet/ymir-platform.sh`, while `stat -c` (43 files), `sha256sum` (43), `systemctl` (27), `/proc/` (17),
  `readlink -f` (10), `flock` (10), `mapfile` (7), `setsid` (6), `nproc` (5), `loginctl` (5), `sed -i` (4),
  `md5sum` (3) and `date -d` (1) are GNU-only and unrouted.
- **The service surface is Linux-shaped**: 26 systemd units, no launchd unit, no runit/sv script for Termux, no
  Windows service. Gróa's updater is bash+git and her *schedule* is a systemd timer — so she has no macOS or
  Windows schedule at all.
- **Installers**: `packaging/build.sh` builds an NSIS `.exe` and a macOS `.pkg`, with
  `.github/workflows/ymir-installers.yml` building both. No `.deb`, `.rpm`, `.pkg.tar.zst`, Homebrew formula,
  winget/scoop manifest or Termux package. The installer workflow last ran 2026-09-16.
- **The matrix is not the test**: CI is 7 × `ubuntu-latest` and 1 × `macos-latest`, and the macOS runner builds
  the pkg rather than running the core.

## What changed in this change

`RULES/05-platforms.md` gains a dated appended section carrying the measured table and one new demand: a
platform claim is made only for a layer that has been *run* in the last thirty days, and every new core script
that touches a host facility goes through the shim rather than a GNU tool name.

Plan 160 (`svartalfaheim/whynotproductions/projects/ymir/plans/160-any-hardware-any-os.md`) carries the repair:
finish the shim and route the callers, make the service surface a contract rendered per platform manager, ship
the installers people actually need, give Gróa a schedule per platform, probe hardware honestly, and turn the
three-host matrix into the proof.

## Why this is a fix note rather than a plan alone

Because the rule was **wrong by omission** — it described intent ("runs on Linux, macOS and Windows") without
recording that the last two are VM-hosted. A rule that reads as a capability, when the tree offers a workaround,
is how a house comes to believe it supports a machine it has never booted.
