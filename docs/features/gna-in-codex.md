# Gná supervision in Codex

Use gna_watch_arm with the actual threadId (or an inherited CODEX_THREAD_ID). The default action arms the canonical Sýn watcher and returns its status. action=status inspects it; action=poll also returns a pending event without consuming it. Calls are bounded rather than waiting for a future event.

On Windows, Ubuntu WSL2 and Linux Python are required. YMIR_WSL_DISTRO selects a distribution when needed; YMIR_WSL_PYTHON defaults to /usr/bin/python3. The code, home and state paths are translated into POSIX paths. No native Windows watcher or PID probe is started.

For automatic wakes, configure a native Codex thread heartbeat on that same thread to inspect the canonical event and wake queue. Stay quiet while unchanged. Handle work before acknowledging an event, and re-read before acknowledging so a newer event cannot be lost. This is a separate transport: watcher up does not prove delivery. CLI queue --resume with a warning proves only enqueue, not wake.

After installing or refreshing the Ymir plugin, restart Codex to load its current MCP tools. Check tools/list for gna_watch_arm. The server and skill must come from the same canonical deployed runtime; do not add a duplicate standalone server.