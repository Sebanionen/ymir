# Termux / Android — the phone as a `hand`

A phone is not a small `dev`. `bin/skuld/role-lib.sh` names the shape plainly:

```
h = heart (the record) · f = forge (models/GPU) · d = dev (a full body) · n = hand (phone)
```

`components_for hand` returns **`core` alone** — no `record`, no `well`, no `web`, no
`mesh`. A phone holds the **harness** (pi and its Ymir extensions), the **sync** (the
private hoard), and the **door** to the heart's services. It never folds the record.

This page is the Termux path. It exists because three desktop assumptions break on
Android — and because each one now has a guard in the code rather than a workaround in
someone's shell history.

## What Android breaks, and where it is fixed

| Break | Error | Fix |
|---|---|---|
| npm's engine gate | `EBADPLATFORM … wanted {"os":"linux,darwin"} (current: {"os":"android"})` | `package.json` now lists `android`; `install.sh` also forces it |
| `bun` | bun's installer skips Android | `step_prereqs` provisions `bun` only for `dev`; a `hand` never asks (bun *does* publish a `bun-linux-aarch64-android` asset — unverified on Termux) |
| `engdbram` needs `sqlite-vec` | `ResolutionImpossible … no matching distributions: sqlite-vec` | a `hand` reaches the heart's well as a door; `YMIR_ENGRAM_LOCAL=1` opts into a source build |
| no systemd / no `loginctl` | `USER: unbound variable` under `set -u` | `step_autoboot` skips cleanly and never dereferences `$USER` |

## Install

The one-liner detects Termux and does the right thing — forces the npm install past the
engine gate, and runs the first setup as `--role hand`:

```sh
curl -fsSL https://raw.githubusercontent.com/zerwiz/ymir/main/install.sh | bash
```

Non-interactive / already have the tree:

```sh
npm install -g @zerwiz/ymir --force          # --force is the engine gate
export YMIR_HOME="$HOME/ymir-home"           # the private hoard (git clone)
bash bin/engine/ymir-install.sh --role hand --yes
```

## The hoard on a phone

The private data root is a git repo (`$YMIR_HOARD`), cloned once:

```sh
git clone git@github.com:zerwiz/ymirhome.git "$HOME/ymir-home"
export YMIR_HOME="$HOME/ymir-home"   # source "$YMIR_HOME/env.sh"
```

`.git-credentials` or the `gh` credential helper seat the auth. Secrets
(`hodd/secrets/platform.env.age`) are **age**-encrypted — the key is `hodd/secrets/age.key`.

## The doors — MCP over SSH

pi reads user-level servers from `~/.pi/agent/mcp.json`. The heart's gateway and well
are **localhost-only**, so a hand reaches them through an SSH tunnel, never a LAN IP:

```
# ~/.ssh/config
Host zerwizserver
  HostName 192.0.2.103
  User zerwizserver
  LocalForward 8316 127.0.0.1:8316     # gateway: well · bolthorn · skuld
  LocalForward 4602 127.0.0.1:4602     # the well bridge (engram)
  ServerAliveInterval 30
```

```json
{
  "mcpServers": {
    "well":     { "url": "http://127.0.0.1:8316/mcp/well" },
    "bolthorn": { "url": "http://127.0.0.1:8316/mcp/bolthorn" },
    "skuld":    { "url": "http://127.0.0.1:8316/mcp/skuld" },
    "firecrawl":{ "command": "npx", "args": ["-y", "firecrawl-mcp"] }
  }
}
```

## The pi extensions — the harness a phone owes

`$YMIR_ROOT/.pi/extensions/` is the one home (`valknut-load.sh` deploys nothing; pi
auto-discovers the project tree). A phone is seated only when the extensions load without
a tool-name conflict — an extension present in **both** the project tree and
`~/.pi/agent/extensions/` registers twice and pi exits.

```sh
bin/seat/valknut-load.sh --pi       # seat the record; removes any global duplicate
bin/seat/valknut-load.sh --check    # prove the deployed tree is the repo's
```

## What a `hand` does not install

`bun` (no build), the visualizer, the local model rail, the web surfaces, `record`, and
`mesh` — all withheld by the role table. Serve them on the heart; reach them over the
tunnel.

## The well, if it must be local

`sqlite-vec` publishes no `aarch64-android` wheel and no sdist, so the local well engine
is an explicit opt-in. With Termux's `clang`/`cargo` present:

```sh
YMIR_ENGRAM_LOCAL=1 bin/engine/prereq-ensure.sh engram
```

Build `sqlite-vec` from source (`github.com/asg017/sqlite-vec`), then
`pip install --user --break-system-packages --no-deps engdbram` plus its remaining deps,
and verify `python3 -c 'import engram'`.

## Verify

```sh
bin/skuld/role.sh resolve --host "$(hostname -s)" --why   # hand  registry
bash bin/engine/ymir-install.sh --role hand --check       # no bun / docker WARN
pi mcp list                                               # the doors
git -C "$YMIR_HOME" status -sb                            # the hoard syncs
```
