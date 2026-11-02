# Codex receives Ymir tools on installation and update

**Date:** 2026-11-02 · **Component:** harness

Codex previously received project hooks, skills and agent profiles, but no model
callable equivalent to the OpenCode Ymir tools plugin. `.agents/harness/codex/`
adds a thin stdio MCP plugin over the existing Ymir owner scripts. It does not load
Pi's ExtensionAPI or claim that terminal UI callbacks are portable to Codex.

First setup and Gróa now share `bin/seat/codex-plugin-install.mjs`. It renders a
machine-local plugin source, registers a dedicated local marketplace through
Codex's CLI, installs or refreshes the plugin, and verifies cached bytes and the
enabled registration. A failed refresh fails the update. Existing user config is
retained; an explicitly disabled plugin is never silently enabled again.

The computed installation plan names the Codex change. Gróa's check mode now
returns before its former migration/rebind/service-writing section; a check of a
stale Codex deployment reports failure without repairing it.

The installer test uses the real Codex CLI with a temporary CODEX_HOME, including
same-version refresh and config preservation. MCP behavior is tested by invoking
the real server. Shell syntax and full runtime gates remain separate requirements;
no local CLI result establishes that Bash, a fleet service or Google OAuth works.
