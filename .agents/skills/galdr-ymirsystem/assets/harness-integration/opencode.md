# OpenCode Harness Adapter (Öppencode)

> **Purpose:** Rebuild, verify, or extend the OpenCode adapter — the `.agents/harness/opencode/plugins/*.js` shims that seat Brokk on `session.created`, arm **Sýn** on `session.idle`, guard the turn end, and enforce the PreToolUse seatbelts.

OpenCode is Ymir's **primary harness** (`config/eindri-harness` = `opencode`; `opencode.json` sets `"default_agent": "brokk"`). Its adapters are ESM plugins built by OpenCode's Bun runtime and loaded from ONE home —
`~/.config/opencode/plugins/` — seeded from `.agents/harness/opencode/plugins/`.

---

## 1. Files

| File | Export | Norse role | Contract part |
|---|---|---|---|
| `.agents/harness/opencode/plugins/saga-sessionstart.js` | `SagaSessionstart` | **Sága** — runs the digest and injects it into the session | Session-open injection |
| `.agents/harness/opencode/plugins/syn-watch-arm.js` | `SynWatchArm` | **Sýn** — owns watcher continuity | Watch arm |
| `.agents/harness/opencode/plugins/syn-turnend-guard.js` | `SynTurnendGuard` | **Sýn** — refuses a blind turn end | Turn-end guard |
| `.agents/harness/opencode/plugins/syn-pretool-check.js` | `SynPretoolCheck` | **Sýn** — arm seatbelt | PreToolUse (arm) |
| `.agents/harness/opencode/plugins/syn-cd-check.js` | `SynCdCheck` | **Sýn** — cd seatbelt | PreToolUse (cd) |
| `.agents/harness/opencode/plugins/lib/rodd-operational-input.js` | `encodeRoddOperationalInput` | **Rödd** — the wire encoder | shared |
| `.agents/harness/opencode/plugins/package.json` | — | declares `"type": "module"` | — |

There is **no** `plugin` array in `opencode.json`; OpenCode discovers the files under
`~/.config/opencode/plugins/` — and under a project's `.opencode/plugins/` — by path.

### One home, and the one dependency (2026-11-12)

- **One home.** The project-level `.opencode/plugins` door is gone. OpenCode loads both
  paths and does not de-duplicate, so the tracked symlink that used to sit there offered
  every adapter twice — and the project copy could never resolve (a checkout carries no
  `node_modules`). The source is `.agents/harness/opencode/plugins/`; the live home is
  `~/.config/opencode/plugins/`.
- **One dependency.** Every adapter opens with `import { Plugin } from "@opencode/plugin"`,
  and OpenCode resolves that package from the plugin file's own directory upwards. A home
  with the files and no `package.json` resolves nothing and reports *"6 plugins failed"*
  while every listing looks right. The home therefore carries
  `{"dependencies": {"@opencode/plugin": "<the running opencode's version>", "effect": "^3"}}`,
  installed by `bin/seat/harness-extensions-install.sh` (the `opencode-deps` row; `--check`
  reports it `stale` when it is missing).
- **A config edit is not live until the service reloads it.** The CLI talks to a background
  service (`opencode service`), which loaded its configuration at start: `opencode service
  restart` is what makes a changed plugin or MCP entry real.

---

## 2. How the plugins are shaped

Each plugin is a named export that receives the OpenCode plugin context and returns an object of hook handlers:

```js
// .opencode/plugins/saga-sessionstart.js:44
export const SagaSessionstart = async ({ client, directory, worktree }) => {
  const root = worktree ? resolvePath(worktree) : await resolveRoot(directory);
  return { event: async ({ event }) => { /* ... */ } };
};
```

| Context field | Meaning |
|---|---|
| `client` | OpenCode SDK client; `client.session.promptAsync({ path:{id}, body:{parts:[{type:"text",text}]} })` injects a message |
| `directory` | the session working directory |
| `worktree` | the linked worktree root when OpenCode runs in one (an Eindri home) |
| `event` | callback receiving `{ event }`, where `event.type` is the lifecycle event |
| `tool.execute.before` | callback receiving `(input, output)`; **throw** to block |

### Root resolution (all plugins)

```js
async function resolveRoot(anchor) {
  if (!anchor) return "";
  const result = await runProcess("git", ["-C", anchor, "rev-parse", "--show-toplevel"]);
  const root = result.stdout.trim();
  if (result.code === 0 && root) return root;
  return resolvePath(anchor);   // realpathSync(anchor) || resolve(anchor)
}
```

`worktree` wins when set, so an Eindri launched by `bin/agents/einherjar-spawn.sh` into `.yggdrasil/<id>` resolves its **own** worktree root and never the primary checkout.

---

## 3. Event hooks used

| Event | Plugin | Action |
|---|---|---|
| `session.created` | `saga-sessionstart.js` | run `bin/time/saga-sessionstart-run.sh` once per session id; inject its stdout |
| `session.idle` | `syn-watch-arm.js` | ensure an arm cycle is running (`sessionOwnsLock`, primary root, `shouldArm`) |
| `session.idle` | `syn-turnend-guard.js` | first ask the watch-arm coordinator; only if it could not arm, run `bin/gates/guards/syn-turnend-guard.sh` and re-prompt on exit 2 |
| `tool.execute.before` | `syn-pretool-check.js` | run `bin/gates/checks/syn-arm-pretool-check.sh --command <cmd>`; throw on exit 2 |
| `tool.execute.before` | `syn-cd-check.js` | run `bin/gates/checks/syn-cd-pretool-check.sh --command <cmd>`; throw on exit 2 |

### 3.1 `session.created` — Sága injection

`.opencode/plugins/saga-sessionstart.js:48-76`:

1. Ignore unless `event.type === "session.created"`.
2. Extract `sessionID = event.properties?.info?.id ?? event.properties?.sessionID`.
3. Skip if already handled (`handledSessions` Set) or no root.
4. Run `${root}/bin/time/saga-sessionstart-run.sh` with no args.
5. If exit ≠ 0 or empty output, silently return (**never block the session**).
6. Encode the digest via the Rödd bridge; on encoder failure fall back to the raw digest.
7. `client.session.promptAsync({ path:{id:sessionID}, body:{parts:[{type:"text",text}]} })`; delivery errors are swallowed.

Because the plugin **runs** the wrapper and injects the result, OpenCode is run-tier in execution with nudge-style delivery.

### 3.2 `session.idle` — Sýn arm ownership

`.opencode/plugins/syn-watch-arm.js:490-505`:

```js
export const SynWatchArm = async ({ client, directory, worktree }) => {
  const root = worktree ? resolvePath(worktree) : await resolveRoot(directory);
  const paths = effectivePaths(root);
  globalThis[COORDINATOR_KEY] = {
    ensureArmed: (sessionID, activeClient) => ensureArm(paths, sessionID, activeClient ?? client),
  };
  return {
    event: async ({ event }) => {
      if (event.type !== "session.idle") return;
      const sessionID = event.properties?.sessionID;
      if (!sessionID) return;
      void ensureArm(paths, sessionID, client);
    },
  };
};
```

`COORDINATOR_KEY = "__brokkOpenCodeWatchArm"` (line 15) is the shared handoff the turn-end guard reads.

Arm gating (`.opencode/plugins/syn-watch-arm.js`):

| Gate | Function | Rule |
|---|---|---|
| primary root only | `isPrimaryRoot` (102-111) | `AGENTS.md` + `bin/` must exist and `git rev-parse --git-dir` must equal `--git-common-dir` (a linked Eindri worktree reports a different git-dir and must not own supervision) |
| live lock | `sessionOwnsLock` (123-140) | walk ancestors of `process.pid` up to 8 levels; must equal `state/.lock` pid |
| arm needed | `shouldArm` (113-121) | false if `state/.afk` exists; true if `config/x-mode.env` exists; else true only if some `state/*.meta` exists |
| single flight | `launchInFlight` (470-488) | serializes concurrent `session.idle` callbacks |

The spawned command is:

```js
// .opencode/plugins/syn-watch-arm.js:355
const armChild = spawn("bash", ["-lc",
  'config_dir="${BROKK_CONFIG_OVERRIDE:-$BROKK_HOME/config}"; [ -f "$config_dir/x-mode.env" ] && . "$config_dir/x-mode.env"; exec "$BROKK_ROOT_OVERRIDE/bin/pi/syn-watch-arm.sh" --restart'],
  { cwd: paths.root, env, stdio: ["ignore","pipe","pipe"] });
```

`env` includes `BROKK_HOME`, `BROKK_ROOT_OVERRIDE`, `BROKK_CONFIG_OVERRIDE`, `BROKK_STATE_OVERRIDE`, `BROKK_WATCH_PREDECESSOR_ARM_PID`.

Continuity: on any non-actionable close, `scheduleRetry` re-arms with exponential backoff (`BROKK_WATCH_REARM_RETRY_BASE_MS` 250 → `..._MAX_MS` 4000, limit `..._LIMIT` 5). On an actionable line, `restoreAfterActionableClose` starts a successor and then `deliverActionableWake` prompts the session.

### 3.3 `session.idle` — Sýn turn-end guard

`.opencode/plugins/syn-turnend-guard.js:65-104`:

1. Ignore unless `event.type === "session.idle"`.
2. If `skipNextIdle`, clear and return (prevents a re-prompt loop).
3. `letWatchArmRun(sessionID, client)` calls `globalThis.__brokkOpenCodeWatchArm.ensureArmed(...)`; return early on `armed`, `wake`, or `failed`.
4. Otherwise run `${root}/bin/gates/guards/syn-turnend-guard.sh` with stdin `{"stop_hook_active":false}`.
5. Only on exit **2**: encode the fixed recovery text + stderr through Rödd and `promptAsync`; set `skipNextIdle`.

The ordering matters: **watch-arm is asked first**. The guard exists for the residual case where the coordinator could not arm.

### 3.4 `tool.execute.before` — seatbelts

`.opencode/plugins/syn-pretool-check.js:50-60`:

```js
"tool.execute.before": async (input, output) => {
  if (!root || input?.tool !== "bash") return;
  const command = output?.args?.command;
  if (!command || typeof command !== "string") return;
  const result = await runProcess(`${root}/bin/gates/checks/syn-arm-pretool-check.sh`, ["--command", command]);
  if (result.code !== 2) return;
  throw new Error(result.stderr.trim() || "denied by the watcher-arm PreToolUse seatbelt");
}
```

`.opencode/plugins/syn-cd-check.js` is identical but calls `bin/gates/checks/syn-cd-pretool-check.sh`. A thrown error blocks the tool call; the owner scripts hold the policy (`syn-arm-pretool-check.sh` denies backgrounding `syn-watch-arm.sh`; `syn-cd-pretool-check.sh` denies `cd .../../`).

---

## 4. The Rödd bridge

`.opencode/plugins/lib/rodd-operational-input.js` is the **only** way the plugins encode operational text. It is a cross-language adapter; `bin/agents/rodd-operational-input.sh` owns the protocol.

```js
// .opencode/plugins/lib/rodd-operational-input.js:6-15
const adapterRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
export function encodeRoddOperationalInput(root, kind, content) {
  const requested = `${root}/bin/agents/rodd-operational-input.sh`;
  const script = existsSync(requested) ? requested : `${adapterRoot}/bin/agents/rodd-operational-input.sh`;
  // spawn(script, ["encode", kind], ...) ; stdin = content ; stdout = encoded
}
```

- Signature: `encodeRoddOperationalInput(root, kind, content) => Promise<string>`.
- It spawns `bin/agents/rodd-operational-input.sh encode <kind>` with the body on stdin.
- It prefers the runtime's own `bin/` and falls back to the adapter's repo `bin/` (three levels up from `.opencode/plugins/lib/`).
- Valid `kind`s are owned by the shell script (`RODD_KINDS`): `session-start watcher turn-end-guard away-supervisor launch-brief branch-outcome`, plus the special `from-brokk` carrier.
- Wire form: `U+2063 RODD_OP: v1 <kind>: <body>`.

Do **not** hand-build the marker in a plugin; call the bridge (or import `RODD_*` only from the shell library).

---

## 5. Configuration (`opencode.json`)

The adapter reads runtime roots from the environment and OpenCode behaviour from `opencode.json`.

| Key | Value in Ymir | Why it matters |
|---|---|---|
| `default_agent` | `"brokk"` | a bare OpenCode launch opens as Brokk |
| `agent.brokk.mode` | `"primary"` | the primary agent |
| `agent.*.mode` | `subagent` (build, builder, plan, planner, reviewer, documenter, scout) | dispatched Eindri profiles |
| `skills.paths` | `[".agents/skills"]` | single skill source; the `galdr` skill loads from here |
| `model` | `""` | empty → harness default |
| `permission` | `allow` for read/edit/glob/grep/bash/task/skill/question/webfetch/websearch/external_directory | primary autonomy |

OpenCode does **not** need a `plugin` declaration: `plugins/*.js` are auto-loaded. The `.opencode/plugins/package.json` exists only to force ESM:

```json
{ "private": true, "type": "module" }
```

---

## 6. Install / enable / verify

### Enable

No install step is required beyond the files being present. OpenCode auto-loads `.opencode/plugins/*.js` on startup. To confirm the plugin modules parse:

```bash
cd "$BROKK_HOME"
node --input-type=module -e 'await import("./.opencode/plugins/saga-sessionstart.js"); await import("./.opencode/plugins/syn-watch-arm.js"); await import("./.opencode/plugins/syn-turnend-guard.js"); await import("./.opencode/plugins/syn-pretool-check.js"); await import("./.opencode/plugins/syn-cd-check.js"); console.log("plugins import ok")'
```

### Verify the four contract parts

```bash
# 1) session-open: the wrapper the plugin runs
bin/time/saga-sessionstart-run.sh | head -n 15 ; echo "exit=$?"

# 2) Rödd encode round-trip (what the plugin calls)
printf 'hello' | bin/agents/rodd-operational-input.sh encode session-start | bin/agents/rodd-operational-input.sh kind
# expected: session-start

# 3) watch arm + heartbeat + wake exit
bin/pi/syn-watch-arm.sh --restart &   # only with a live lock; prints watcher: started...
sleep 1
test -s state/.watch.heartbeat && echo "heartbeat ok"
: > state/.wake-queue              # arm should exit with "signal: wake queue"

# 4) seatbelts (exit 2 = block)
bin/gates/checks/syn-arm-pretool-check.sh --command 'foo & bar';             echo "expect 0 -> $?"
bin/gates/checks/syn-arm-pretool-check.sh --command 'bin/pi/syn-watch-arm.sh &'; echo "expect 2 -> $?"
bin/gates/checks/syn-cd-pretool-check.sh  --command 'cd ../..';              echo "expect 2 -> $?"
```

### End-to-end smoke

```bash
# OpenCode session in BROKK_HOME: the first injected message must begin with the
# Sága digest (or the RODD_OP marker wrapping it), and the session must address
# the operator as Allfather. Then drop a wake and confirm the watcher fires.
: > state/.wake-queue
```

---

## 7. Gotchas

- **Two `session.idle` plugins race by design — but not for the guard.** `syn-watch-arm.js` and `syn-turnend-guard.js` both listen on `session.idle`; the guard *asks* the arm coordinator first, and only runs the guard when arming failed. Reversing this produces spurious "TURN WOULD END BLIND" prompts during normal operation.
- **`handledSessions` is per-process, never persisted.** After an OpenCode restart the digest runs again for a new session id; that is intended. Do not persist the Set — a resumed session with a new id must still be seated.
- **`promptAsync` failures are swallowed.** If OpenCode's SDK errors, the digest is silently dropped. Diagnose by running `bin/time/saga-sessionstart-run.sh` by hand; the plugin cannot surface a delivery error.
- **`shouldArm` returns false with no `state/*.meta` and no `config/x-mode.env`.** A fresh home therefore arms nothing until there is a task or x-mode. This is deliberate: no fleet, no supervision. Do not "fix" it by always arming.
- **The arm refuses on a linked worktree.** `isPrimaryRoot` requires `git-dir == git-common-dir`; an Eindri worktree under `.yggdrasil/<id>` will never own supervision. Correct — the primary owns it.
- **`read-only` is final for the cycle.** If `sessionOwnsLock` is false, `beginArm` returns `read-only` and no retry is scheduled. A second OpenCode session must not fight the lock holder.
- **The plugin must never be replaced by a model bash call.** `syn-arm-pretool-check.sh` denies backgrounding the arm precisely so the model cannot fork a second watcher.
- **`config/x-mode.env` is sourced by the arm spawn** (`.opencode/plugins/syn-watch-arm.js:355`). It is not present by default; treat it as an operator opt-in.
- **`.opencode/plugins/lib/` is not a package** — there is no `package.json` there. Relative imports (`./lib/rodd-operational-input.js`) are what make it work; the top-level `package.json` supplies `"type":"module"`.
- **Tool name matching is exact.** The seatbelts only inspect `input.tool === "bash"`. If OpenCode renames the shell tool, both seatbelts silently stop enforcing.
