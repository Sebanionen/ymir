# Runbook — harnesses: which agents Ymir knows, and how the house reaches them

Ymir does not assume one agent. It detects what you are running, and gives each harness the same contract and the
same extensions.

## Detection and descriptors

```
harnesses[9]{name,detected_by}
  "pi","process (pi, pi-signed)"
  "opencode","process (opencode)"
  "claude","process (*claude*)"
  "codex","process (*codex*)"
  "cursor","process (cursor, cursor-agent)"
  "grok","process (*grok*) or GROK_HOOK_* markers"
  "kimi","process (kimi)"
  "muse","process (muse, muse-bin-*)"
  "zed","process (zed) or ~/.config/zed — included by descriptor; reads AGENTS.md natively"
```

`bin/backend/fm-harness.sh` answers *which harness am I inside*. Each harness also has a **descriptor** in
`.agents/harnesses/<name>.yaml`: binary, transcript shape and root, where its extensions and instructions live,
and its capability flags.

## The two verbs

```bash
bin/seat/harness-contract-install.sh --check    # does each harness read the seat's one contract?
bin/seat/harness-contract-install.sh            # link them all to ~/.agents/AGENTS.md
bin/seat/harness-extensions-install.sh --check  # is each harness's extension set the tree's?
bin/seat/harness-extensions-install.sh          # sync pi · opencode · claude · codex · cursor · zed
```

Both are idempotent, both report `current · synced · stale · absent`, and both are re-run by
`bin/agents/groa-update.sh` on every update — an update that leaves your agent reading last month's law, or
running without the house's tools, is not an update.

## Where each harness keeps its history

This is the thing to know before writing anything that reads a transcript:

```
transcripts[5]{harness,shape,where}
  "pi","jsonl tree (id/parentId; a branch is a second child in one file)","~/.pi/agent/sessions/…"
  "claude","flat jsonl","~/.claude/projects/<project>/<uuid>.jsonl"
  "codex","flat jsonl","$CODEX_HOME/sessions/YYYY/MM/DD/rollout-*.jsonl"
  "opencode","database (v2) + plaintext log","~/.local/share/opencode/log/opencode.log"
  "cursor","sqlite per chat","~/.cursor/chats/<uuid>/<uuid>/store.db"
```

Three shapes, two hook mechanisms, one plugin event API. Parse **one** normalised shape, not a vendor file.

## What goes wrong

- **An agent booted outside the checkout has no Ymir.** The extensions are loaded from the settings entry that
  points at your pinned runtime; check it, then run the installer.
- **An extension loads twice.** Pi does not de-duplicate by directory — two load paths seat nobody. Keep one path.
- **OpenCode has guards but no tools.** The tool set lives in `ymir-tools.ts`; `opencode debug config` should list
  it under `plugin`.
- **Zed and MCP.** Zed stores servers as `context_servers` inside `settings.json`; a block copied from another
  client (`mcpServers`) does nothing.
- **A user's own `settings.json`.** The installer *names* it and refuses to merge blind — that file is theirs.
