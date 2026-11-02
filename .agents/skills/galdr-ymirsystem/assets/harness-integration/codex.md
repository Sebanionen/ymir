# Codex Harness Adapter

> **Purpose:** Rebuild, verify, or extend the Codex adapter: the Ymir tools plugin under `.agents/harness/codex/`, its shared install/update door, and the existing project hooks below.

Codex is a **run-tier session-open** harness when the hooks feature is enabled. Each hook is a defensive `bash -lc` one-liner that self-locates with `pwd -P`, self-verifies that it is really registered in the project's `.codex/hooks.json`, and only then calls the runtime.

---

## 1. Files and gate

| File | Role |
|---|---|
| `.codex/hooks.json` | project hook registrations (SessionStart, PreToolUse, Stop) |
| `~/.codex/config.toml` | must contain `[features]\nhooks = true` for hooks to load |

Codex will not run project hooks unless the feature flag is on. The observed global config on this host:

```toml
[features]
  hooks = true
```

The hook JSON is the existing lifecycle adapter. The Codex tools plugin described below is a separate surface; the earlier claim that Codex had no plugin runtime is retired.

---

## 2. The hook file (verbatim)

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash -lc 'payload=$(cat 2>/dev/null || true); [ -n \"$payload\" ] || exit 0; command -v jq >/dev/null 2>&1 || exit 0; root=$(pwd -P) || exit 0; [ -x \"$root/bin/time/saga-sessionstart-run.sh\" ] || exit 0; [ -f \"$root/AGENTS.md\" ] || exit 0; [ -f \"$root/.codex/hooks.json\" ] || exit 0; jq -e \"any(.hooks.SessionStart[]?.hooks[]?.command?; type == \\\"string\\\" and contains(\\\"saga-sessionstart-run.sh\\\"))\" \"$root/.codex/hooks.json\" >/dev/null 2>&1 || exit 0; printf \"%s\" \"$payload\" | \"$root/bin/time/saga-sessionstart-run.sh\"'",
            "timeout": 180
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "bash -lc '... | \"$root/bin/gates/checks/syn-arm-pretool-check.sh\"'", "timeout": 10 },
          { "type": "command", "command": "bash -lc '... | \"$root/bin/gates/checks/syn-cd-pretool-check.sh\"'",  "timeout": 10 }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "bash -lc '... | \"$root/bin/gates/guards/syn-turnend-guard.sh\"'", "timeout": 30 }
        ]
      }
    ]
  }
}
```

(The PreToolUse/Stop commands are long; their full text is in `.codex/hooks.json:20`, `:25`, `:36`. Each is the same defensive preamble plus the owner script.)

---

## 3. The defensive preamble (shared by every hook)

Every hook uses the same `bash -lc` shape. Read it as a fail-closed gate:

```bash
payload=$(cat 2>/dev/null || true)          # 1. read the hook JSON payload
[ -n "$payload" ] || exit 0                 #    no payload → no-op
command -v jq >/dev/null 2>&1 || exit 0     # 2. jq is required for payload handling/verification
root=$(pwd -P) || exit 0                    # 3. Codex runs the hook from the project root
[ -x "$root/bin/<script>" ] || exit 0       # 4. the runtime script must exist and be executable
[ -f "$root/AGENTS.md" ] || exit 0          # 5. this must look like a Brokk home
[ -f "$root/.codex/hooks.json" ] || exit 0  # 6. this project's hook file must exist
jq -e "any(.hooks.<Event>[]?.hooks[]?.command?; type == \"string\" and contains(\"<script>\"))" \
   "$root/.codex/hooks.json" >/dev/null 2>&1 || exit 0   # 7. self-verify registration
printf "%s" "$payload" | "$root/bin/<script>"            # 8. run the owner script
```

The **self-verification** step (7) is the distinctive Codex safeguard: the hook refuses to run unless the project's own `.codex/hooks.json` still declares a command containing the target script name. A copy of the hook JSON placed in a foreign home, or a hijacked registration, no-ops instead of running the runtime.

`root=$(pwd -P)` resolves symlinks, so a hook launched through a symlinked path still resolves the real project root.

---

## 4. Per-event behavior

### 4.1 `SessionStart` → `bin/time/saga-sessionstart-run.sh`

- Pipes the JSON payload into the wrapper; the wrapper parses `source` without `jq` (`bin/time/saga-sessionstart-run.sh:34-44`).
- Source routing is the same as Claude: `startup`/`new` run the digest; `clear`/`compact` re-emit after a completed startup; `resume`/`reload`/`fork` nudge.
- `timeout: 180`.
- The wrapper always exits 0 on the transport path; a run-tier print of the digest reaches model context.

### 4.2 `PreToolUse` (matcher `Bash`) → seatbelts

Two hooks, each piping the payload to an owner script:

```bash
... printf "%s" "$payload" | "$root/bin/gates/checks/syn-arm-pretool-check.sh"
... printf "%s" "$payload" | "$root/bin/gates/checks/syn-cd-pretool-check.sh"
```

- `timeout: 10`.
- Exit **2** blocks the Bash call; the reason is on stderr.
- These scripts normally take `--command <cmd>`; in the Codex flow the command is carried in the payload. The owner scripts are the policy holders either way.

### 4.3 `Stop` → `bin/gates/guards/syn-turnend-guard.sh`

- Pipes the payload (typically `{"stop_hook_active":false}`) into the guard.
- Exit **2** surfaces the recovery instruction and re-prompts instead of letting the turn end blind.
- `timeout: 30`.
- **No re-arm.** Codex has no async Stop continuation in this adapter, so there is no long-lived arm child. The guard is inert until something else writes `state/.supervision-armed`.

---

## 5. Install / enable / verify

### Enable the feature gate

```bash
# Codex global config must have:
grep -A1 '^\[features\]' ~/.codex/config.toml   # expect: hooks = true
```

If absent, add:

```toml
[features]
hooks = true
```

### Syntax / schema

```bash
cd "$BROKK_HOME"
python3 -m json.tool .codex/hooks.json >/dev/null && echo "codex hooks JSON ok"
command -v jq >/dev/null && echo "jq present" || echo "jq MISSING - adapter will no-op"
```

### Verify the session-open path

```bash
printf '{"source":"startup"}' | bin/time/saga-sessionstart-run.sh | head -n 20; echo "exit=$?"
printf '{"source":"compact"}' | bin/time/saga-sessionstart-run.sh | head -n 3
```

### Verify the self-verification gate

```bash
# The jq expression the SessionStart hook runs; must be true in-tree:
jq -e 'any(.hooks.SessionStart[]?.hooks[]?.command?; type == "string" and contains("saga-sessionstart-run.sh"))' .codex/hooks.json
jq -e 'any(.hooks.PreToolUse[]?.hooks[]?.command?; type == "string" and contains("syn-arm-pretool-check.sh"))' .codex/hooks.json
jq -e 'any(.hooks.Stop[]?.hooks[]?.command?; type == "string" and contains("syn-turnend-guard.sh"))' .codex/hooks.json
# All three must print true and exit 0.
```

### Verify Stop

```bash
rm -f state/.supervision-armed
printf '{"stop_hook_active":false}' | bin/gates/guards/syn-turnend-guard.sh; echo "inert -> $? (expect 0)"
touch state/.supervision-armed; rm -f state/.watch.heartbeat
printf '{"stop_hook_active":false}' | bin/gates/guards/syn-turnend-guard.sh; echo "armed+stale -> $? (expect 2)"
```

### Verify seatbelts

```bash
bin/gates/checks/syn-arm-pretool-check.sh --command 'bin/pi/syn-watch-arm.sh &'; echo "arm -> $? (expect 2)"
bin/gates/checks/syn-cd-pretool-check.sh  --command 'cd ../..';             echo "cd  -> $? (expect 2)"
```

---

## 6. Gotchas

- **`[features].hooks = true` is mandatory and lives in the global config**, not the project. Without it, `.codex/hooks.json` is ignored entirely.
- **`jq` is a hard dependency.** Every hook exits 0 if `jq` is missing, disabling injection, seatbelts, and the guard.
- **The self-verification step can brick the adapter after an edit.** If you rename `saga-sessionstart-run.sh` or `syn-arm-pretool-check.sh`, the `contains(...)` check silently starts returning false and the hooks no-op. Keep script names stable or update the strings in `.codex/hooks.json` in the same change.
- **`pwd -P` requires Codex to launch hooks from the project root.** If a future Codex version runs hooks from elsewhere, the root resolves wrong and every gate fails closed (silent no-op).
- **There is no re-arm.** Do not assume Codex owns supervision across turns; the guard is inert until an arm exists.
- **No `PreToolUse` matcher for non-Bash tools.** Only `Bash` is guarded; other tool calls bypass the seatbelts by design.
- **Payload shape is assumed JSON.** A hook with empty stdin no-ops (`[ -n "$payload" ]`).
- **Do not simplify the preamble.** Each guard (`AGENTS.md`, `.codex/hooks.json`, executable bit, registration self-check) exists to keep the adapter from running in a foreign or partially installed home.

**Skills.** This harness reads project skills from `.codex/skills/`; `bin/seat/valknut-load.sh` binds it to the one tree (`.codex/skills -> ../.agents/skills`). Never copy a `SKILL.md` in — a copy is drift, and a nested `SKILL.md` with frontmatter is loaded as a phantom skill.


## Codex tools plugin — installation and update

The canonical plugin lives beside the OpenCode adapter at `.agents/harness/codex/`.
It exposes the OpenCode model tool set through a Node stdio MCP server, calling
Ymir's existing owner scripts. Pi UI callbacks and terminal keybindings are not
loaded into Codex. The existing `.codex/hooks.json` remains the project lifecycle
adapter; the plugin does not register duplicate hooks.

`node bin/seat/codex-plugin-install.mjs` is Valknut's single Codex deployment door.
First setup (`step_codex_plugin`) and Gróa (`bin/agents/groa-update.sh`) call this
same helper. The computed installation plan names the Codex change before consent.
A host without Codex skips this harness integration; installed Codex with missing
Node, unsupported plugin CLI, stale files or a failed refresh is a failure.

The helper stages the public plugin under `$CODEX_HOME/ymir-marketplace/` (default
`~/.codex/ymir-marketplace/`), renders `mcp.json` with the actual Node executable,
canonical Ymir server path and `YMIR_ROOT`, and writes a runtime root record there.
These machine-specific paths are generated user state, never tracked content.
The dedicated local marketplace is registered using `codex plugin marketplace add`;
`codex plugin add ymir@ymir --json` installs or refreshes the cached plugin. Codex
itself owns config mutations; the installer preserves unrelated user settings and
refuses to silently re-enable an explicitly disabled Ymir plugin.

`node bin/seat/codex-plugin-install.mjs --check` checks staged files, marketplace
source, enabled installation, version and cached bytes. It never redeploys or
repairs stale content. Gróa's `--check` returns before migrations, service restarts
and harness rebinding. A normal update fails if Codex refresh fails. Restart Codex
after a refresh to load changed tools and skills into a new session.

Canonical skills and agent profiles still bind through Valknut's existing paths;
they are not copied into a second authoritative skill tree. The plugin includes
its own entry skill to route into those existing Ymir capabilities. Shell-backed
tools require working Bash and the underlying Ymir runtime dependencies. Installing
the plugin is not proof that a fleet service or a Google grant is available.

Verification: `node --test tests/test_codex_install.mjs tests/test_codex_plugin.mjs`.
The installer suite uses the real Codex CLI in a temporary `CODEX_HOME` to prove
installation, same-version refresh, idempotence and preservation of unrelated
settings. That case reports an explicit skip when Codex is absent. The MCP tests
exercise the actual stdio server; neither suite needs production credentials.
Run `bash -n` on touched shell doors and the canonical compliance/CI gates too.

Format references: [OpenAI plugin packaging](https://developers.openai.com/plugins/build/plugins)
and the installed `codex plugin add --help` / `codex plugin marketplace add --help`.
