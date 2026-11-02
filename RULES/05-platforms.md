# Rule 05 — Platform installations

Ymir is **Omarchy-first**: the Omarchy layer is the first-class desktop
integration. Different operating systems and desktops may have their own
installation layer — macOS and Windows bring their own — while the **core stays
portable** and identical everywhere.

## The law

- **One core, many installations.** The core runtime — session digest, lock,
  watch, cron, skills, the installer's user-space prerequisites, machine-config
  rendering — runs on Linux, macOS and Windows (WSL2; MSYS best-effort).
  Anything platform-specific lives in an *installation layer* beside the core,
  never as a branch inside it.
- **A layer is gated, never assumed.** It detects its own host and reports a
  clean skip elsewhere (`/usr/share/omarchy`, `uname`, `ymir_os`). A layer that
  assumes it is present is a bug on every other machine.
- **Core changes propagate to every layer.** When a core feature changes, **every
  platform installation layer must be updated in the same change**. A layer that
  still installs the old shape is drift — and drift here means a machine that
  boots expecting a runtime it no longer has.
- **A layer owns its integration, not a copy of the core.** No layer forks a
  core script. It calls the core and adds only what its platform needs; two
  copies of one script is how the platforms silently diverge.
- **The desktop is a platform concern.** Window placement, launcher entries,
  service managers (systemd / launchd / Windows services) and GPU tooling belong
  to the layer that knows the platform.
- **Verification is per-layer.** "It works" is a claim about *one* layer. Name
  the layer that was tested; never let a core change be called verified because
  one platform's install passed.

## The layers

```
layers[4]{layer,host,owns}:
  "Omarchy (first-class)","Omarchy (Arch + Hyprland)","host sensing, numbered-desktop placement, launcher entries, shell plugins, post-update hook"
  "macOS","macOS","launchd services, .command/.app launchers, Apple GPU reporting"
  "Windows","WSL2 (MSYS best-effort)","WSL service wiring, .cmd/.lnk launchers"
  "Core (portable)","every platform","the runtime, the capability shim, generated config, user-space prerequisites"
```

## Where this shows up

| Place | What carries the rule |
|---|---|
| `bin/fleet/ymir-platform.sh` | the capability shim: the one place a platform difference is known |
| `bin/engine/ymir-install.sh` | runs the core; Omarchy steps are gated on the host |
| the Omarchy layer (`omarchy-sense`, `omarchy-plugins`, `omarchy-hook-install`, `desktop-place`) | Omarchy only, each reporting a clean skip elsewhere |
| `galdr/assets/installation.md` | the two-layer model, and the rule for new desktop features |
| `galdr/assets/build-method.md` | the maintenance duty: a core change updates every layer |

## Maintenance duty

A core change is not complete until every layer has been checked against it. The
check is cheap and must be explicit:

```bash
# which layers does this change touch?
git grep -l "<the changed core interface>" -- bin scripts .agents/skills
```

If a layer needs a matching edit, make it in the same change, or record why it
does not. A rule that contradicts this rule must change the rule first
(append-only; never silently rewritten).

**Related:** `RULES/04-hoard.md` (what is private), `AGENTS.md` (the contract),
`.agents/skills/galdr-ymirsystem/assets/installation.md` (the install procedure).

## 2026-11-02 — appended: measured against the tree, not against intent

The law above is unchanged. What follows is the measurement of how far the tree actually obeys it, so the next
change has a true starting point instead of a hopeful one.

**How to run on a given host, as it stands today:**

```
hosts[5]{host,how,what_actually_runs}
  "Omarchy / Arch","bin/engine/ymir-install.sh","first-class; verified"
  "other Linux (Ubuntu · Fedora · Debian)","bin/engine/ymir-install.sh","the core; the Omarchy layer skips cleanly — believed, not recently verified in CI"
  "SteamOS","bin/engine/ymir-install.sh --role dev","verified 2026-10-19"
  "Android (Termux)","the curl bootstrap","partial by design: a `hand` — pi, the hoard, the heart's doors; no record, no rail, no bun"
  "macOS","bin/host/bootstrap-macos.sh","a **Linux VM** (Lima) is the host; Ymir runs inside it, not on the Mac"
  "Windows","bin/host/bootstrap-windows.ps1","a **Linux VM** (WSL2 + Ubuntu) is the host; Ymir runs inside it, not on Windows"
```

**So: Ymir runs on Linux, and on macOS and Windows by hosting Linux.** That is a legitimate answer — it is the
one the README already gives — but it is not the same claim as "runs on any operating system", and the rule
must not pretend the two are equal.

**The portability debt, counted:**

```
debt[8]{idiom,files,note}
  "stat -c","43","BSD/macOS stat takes -f; the shim has no ymir_stat yet"
  "sha256sum","43","macOS ships shasum -a 256 instead"
  "systemctl","27","26 systemd units are shipped and no launchd unit at all; the service surface is Linux-shaped"
  "path /proc/","17","absent on macOS and Windows"
  "readlink -f","10","BSD readlink has no -f"
  "flock","10","absent on macOS; mkdir-lock is the portable fallback"
  "mapfile","7","bash 4+ only; macOS ships bash 3.2"
  "setsid, nproc, loginctl, sed -i (4), md5sum (3), date -d (1)","5–6 each","same class: GNU-only, no shim"
```

**Only 24 of 667 shell scripts source `bin/fleet/ymir-platform.sh`.** The shim is the right idea and is not the
road actually taken.

**The installer and updater layer:** `packaging/` builds an NSIS `.exe` and a macOS `.pkg`
(`packaging/build.sh`), with `packaging/macos/Ymir Installer.command` and `packaging/windows/ymir-setup.nsi`;
`.github/workflows/ymir-installers.yml` builds both in CI. There is **no** `.deb`, `.rpm`, `.pkg.tar.zst`,
Homebrew formula, winget/scoop manifest or Termux package, and the installer workflow has not run since
2026-09-16. Gróa (the updater) is a bash+git door whose schedule is a **systemd timer** — so the updater has no
launchd or Task Scheduler equivalent.

**What the rule therefore demands of the next change:** a platform claim is made only for a layer that has been
*run* in the last thirty days, and every new core script that touches a host facility goes through
`bin/fleet/ymir-platform.sh` — not through a GNU tool name.

## 2026-11-02 (appended, later) — what shipped, and the words "Windows" and "portable" still do not mean what they sound like

**Merged and live:** the pinned runtime (`~/ymir-runtime`, ten units, `bin/engine/runtime-deploy.sh`,
`runtime-pinned-guard`), the harness-contract installer, the recovered OpenCode plugin, and the first gate routed
through the platform shim (`vault-guard` → `ymir_sha256`).

**In review, not merged:** the shim's six verbs, the portability ratchet, and the Windows package manifests
(`winget`, `scoop`) beside the NSIS installer.

**The honest state, in one paragraph, for whoever reads this rule next.** Windows works by hosting Linux: the NSIS
installer raises Ubuntu on WSL2 and runs the Linux install inside it — packaged, and *not proved*, because no clean
Windows machine has run it and the installer workflow last executed on 2026-09-16. Portability is 1 of 82: the verbs
exist and the ratchet holds the line, but 33 tracked files still call `stat -c`, 33 `sha256sum`, 7 `mapfile`,
5 `flock`, 3 `sed -i`, 1 `nproc`, and the service surface is still 26 systemd units with no launchd or Windows
rendering. A rule that says "runs on Linux, macOS and Windows" while all of that is true is a rule that needs this
paragraph attached to it — which is what this is.
