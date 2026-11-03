# Runbook — platforms: Linux, macOS, Windows, and portable code

**Ymir runs on Linux.** On macOS it runs inside a Lima VM; on Windows inside Ubuntu on WSL2. That is a legitimate
way to support a machine and it is not the same claim as "runs natively" — say it that way to whoever asks.

```
hosts[4]{platform,how}
  "Linux (Arch · Debian · Fedora · Ubuntu)","bin/engine/ymir-install.sh — the portable core; desktop layers skip cleanly"
  "Windows","bin/host/bootstrap-windows.ps1 — raises Ubuntu on WSL2, then installs inside it"
  "macOS","bin/host/bootstrap-macos.sh — raises a Lima VM, then installs inside it"
  "Android (Termux)","the curl bootstrap — a 'hand': pi, the home, and the doors to a host"
```

## Installing for someone else

```bash
bin/host/bootstrap-windows.ps1      # Windows (elevated; one reboot on a machine that never had WSL)
bin/host/bootstrap-macos.sh         # macOS
packaging/build.sh --check          # what this machine can build, and with what
packaging/build.sh --exe            # NSIS installer (needs makensis)
packaging/build.sh --mac            # macOS .pkg (needs a Mac with pkgbuild)
```

Package manifests sit beside the installers under `packaging/`. The winget and scoop manifests carry placeholder
hashes until a signed release exists — do not publish them as they stand.

## Writing portable code

`bin/fleet/ymir-platform.sh` is the one place a platform difference is known. Do not call a GNU tool by name.

```bash
ymir_os                                   # linux | macos | wsl | msys | android
ymir_stat size|mtime|mode <path>
ymir_stat_c '<gnu-format>' <path>         # the call sites already say stat -c '%s:%Y'; this translates on BSD
ymir_sha256 <file>                        # sha256sum → shasum -a 256 → openssl dgst
ymir_nproc · ymir_sed_i · ymir_lock · ymir_read_lines
```

A **ratchet** keeps the debt from growing:

```bash
bash bin/gates/checks/portability-ratchet.sh check            # a count may fall, never rise
bash bin/gates/checks/portability-ratchet.sh --write-baseline # after a fall
```

It judges the commit (`git show HEAD:<path>`), ignores comment-only mentions, and carries a stated tolerance
because the count can flicker on a live machine.

## Routing a caller — the safe order

1. Put the shim source **after** `ROOT` is assigned — never inside a multi-line `ROOT="$( … )"`, or you get a
   script that parses and silently loses the verb.
2. Replace the GNU call with the verb.
3. **Run the file**, not just `bash -n`.
4. Re-run the ratchet; if the count fell, lower the baseline and commit it.

## The honest state

Portability is a migration, not a switch: the verbs and the ratchet exist, and many callers are still GNU-only.
The service surface is systemd-shaped, with no launchd or Windows rendering. Windows is packaged, not proved —
run it on a clean machine before telling anyone it works.
