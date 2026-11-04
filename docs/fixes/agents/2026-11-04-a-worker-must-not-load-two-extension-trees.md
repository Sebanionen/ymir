## agents · 2026-11-04 — a worker must not load two extension trees (the four dead panes)

### Why
Four Eindri were spawned into Yggdrasil worktrees on herdr, and **every one of them was born dead** while
`einherjar-spawn.sh` printed `spawned … target=w9:p1`. Each pane answered with 43 identical errors:

```
Error: Failed to load extension "~/ymir/.pi/extensions/constellation/index.ts":
       Tool "constellation_list" conflicts with
       ~/ymir/.yggdrasil/weaver-hook-and-ci/.pi/extensions/constellation/index.ts
```

The cause is a **two-load-path** defect, the exact thing RULES/13 forbids. The seat's
`~/.pi/agent/settings.json` names the **primary checkout's** extensions tree absolutely
(`/home/zerwizomar/ymir/.pi/extensions`), and Pi separately discovers the project tree under the working
directory. Run from `~/ymir` those are one canonical path and Pi dedupes them — which is why the primary
never showed the fault. Run from `.yggdrasil/<id>` they are two different paths, so all 18 extensions
registered twice and Pi refused every one of them. The dispatcher's success line was therefore a **false
green**: it proved a pane existed, not that an agent started (the same class of lie as the 2026-10-24
opencode seats).

### Mend
- **`bin/agents/einherjar-spawn.sh`** gains `pi_ext_args <cwd>` and the `pi|pi-signed` launch now emits
  `-ne -e <worktree>/.pi/extensions/<entry> …` plus `-e npm:<each package the seat's settings declare>`.
  Discovery is off, every extension is named **once**, and every path resolves **inside the worker's own
  worktree** — so a worker cannot run the primary checkout's tool code either.
- The npm packages are re-stated explicitly because `--no-extensions` also disables package discovery; a
  quiet loss of `pi-mcp-adapter` / `pi-web-access` / `pi-lmstudio` would have been a second false green.

### Proven
- The regenerated launch script, measured:
  `exec pi --model 'opencode-go/deepseek-v4.1-flash' -ne -e '/home/zerwizomar/ymir/.yggdrasil/weaver-hook-and-ci/.pi/extensions/constellation/index.ts' -e … ` (46 `-e` entries, no conflict, no module error).
- A session opened in the worktree with `-ne` + the full `-e` set: **no extension errors**; with the old
  command, 43.
- All four panes relaunched and each wrote a `working:` line — `weaver-hook-and-ci`, `catalogue-the-doors`
  ("branch cut at the foundation commit"), `hermes-parity-and-proof`, `telegram-every-machine`.
- `bash -n bin/agents/einherjar-spawn.sh` — clean.
