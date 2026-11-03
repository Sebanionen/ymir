# What shipped, and what "Windows" and "portable" still do not mean

**Date:** 2026-11-02 · **Component:** platforms

A dated appendix to RULES/05 recording, in one place, the state of the two claims that keep being asked about.

**Merged and live:** the pinned runtime (`~/ymir-runtime`, ten units re-pointed, `bin/engine/runtime-deploy.sh`,
`runtime-pinned-guard`), `bin/seat/harness-contract-install.sh`, the recovered OpenCode plugin, the first gate
routed through the shim (`vault-guard` → `ymir_sha256`).

**In review:** the shim's six verbs, the portability ratchet, the `winget` and `scoop` manifests.

**Windows** — packaged, not proved. `bin/host/bootstrap-windows.ps1` raises Ubuntu on WSL2 and runs the Linux
install inside it; the NSIS `.exe` builds in CI; the manifests exist. No clean Windows machine has run the
installer, and the installer workflow last executed 2026-09-16.

**Portability** — 1 of 82. `stat -c` in 33 tracked files, `sha256sum` 33, `mapfile` 7, `flock` 5, `sed -i` 3,
`nproc` 1. The verbs exist and the ratchet holds the line against new callers; the migration has started and is one
file deep. The service surface is still 26 systemd units with no launchd or Windows rendering, and there is no
three-host CI matrix.

The rule now carries this paragraph, so the next reader cannot take "runs on Linux, macOS and Windows" for more
than it is.
