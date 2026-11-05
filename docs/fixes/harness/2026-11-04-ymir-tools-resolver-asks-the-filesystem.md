# ymir-tools asked a file API about a directory, so the root never resolved

**Date:** 2026-11-04 · **Component:** harness

## What was wrong

One plugin still failed on every boot: `ymir-tools`, with
`Cause([Die(Error: YMIR_ROOT not resolved)])`. The other seven loaded. The twenty
Ymir tools (`ymir_recall`, `ymir_errand`, `ymir_plan`, …) were therefore absent from
OpenCode even though the plugin file was present and its dependencies resolved.

## Why

`resolveYmirPaths` validated each pointer candidate with

```ts
if (candidate && await Bun.file(`${candidate}/bin`).exists()) { … }
```

`Bun.file()` describes a **file**. Measured on bun 1.4.2:

```
/home/ymir/coding/ymir/bin   => false
/home/ymir/coding/ymir/AGENTS.md => true
```

So every candidate in `~/.pi/agent/extensions/.ymir-root` — both of them, each with a
real `bin/` directory — was rejected. The only remaining fallback was
`git rev-parse --show-toplevel`, run in the **server process's** cwd. The OpenCode
background service does not run inside a checkout, so that exit 128'd too, and the
resolver threw.

The 2026-11-04 repair (*twelve plugins loaded, none ran*) proved the **module** loaded;
it did not prove the resolver answered, because the check it used measured the same
wrong thing.

## Fix

- `.agents/harness/opencode/plugins/ymir-tools.ts` (and the deployed copy at
  `~/.config/opencode/plugins/ymir-tools.ts`):
  - directory existence is asked with `stat(...).isDirectory()` from
    `node:fs/promises`, not `Bun.file().exists()`;
  - a candidate must prove it is a Ymir root — **both** `bin/` and `RULES/` are
    directories;
  - the candidates are tried in one list: `YMIR_ROOT` env → every line of
    `.ymir-root` → the directory OpenCode was opened in (`ctx.location.directory`,
    so a worktree resolves to itself) → `git rev-parse --show-toplevel` run in that
    directory;
  - the failure message names the three doors to mend instead of saying only
    `YMIR_ROOT not resolved`.
- Synced into `/home/ymir/ymir-runtime` as well, so a re-deploy from either checkout
  cannot resurrect the broken resolver.

## Proof

Resolver run with bun from `/tmp` (a cwd inside no repository, matching the server):

```
{"root":"/home/ymir/coding/ymir","home":"/home/ymir/Documents/ymirhome","state":"/home/ymir/Documents/ymirhome/state"}
```

After `bin/seat/harness-extensions-install.sh`:

```
"opencode","synced","1 file(s) into /home/ymir/.config/opencode/plugins"
```

Opencode log, next load (18:57:13Z): `ymir-tools.ts` loads with no
`failed to load plugin` line after it, and the `ymir_*` tools appear in the session's
tool catalog. The last failure in the log is the one from before the fix (18:54:41Z).

## Not changed

The supervision watcher re-armed itself on plugin reload (`.arm.lease` and
`.watch.heartbeat` written at 19:57 local); no hand re-arm was needed.
