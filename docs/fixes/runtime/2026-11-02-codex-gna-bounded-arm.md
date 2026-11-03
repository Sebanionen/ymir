# Gná arms Codex without a blocking tool call

The old gna_watch_arm tool awaited the session relay for up to ten minutes and provided no Codex wake delivery. It now starts the canonical watcher and checks status with a bounded command. Windows takes the WSL route with Linux Python and POSIX paths, avoiding the native Windows PID-probe and Bash path hazards. The actual Codex thread ID is required or inherited; it is not replaced with a process identity.

The tool supports arm (default), status and read-only poll. Pending .arm.event contents stay intact until a processing turn has handled the work. This adapter does not invent a wake daemon. Automatic desktop delivery uses the existing native Codex thread heartbeat; merely seeing an idle/armed watcher is not proof of a successful wake. Codex queue --resume can enqueue while warning that resume failed and is not used as an automatic delivery loop.

Verified: focused Node tests pass; live WSL status returned daemon active, armed yes and a fresh heartbeat. The existing plugin deployment door refreshes the same Ymir plugin; restart Codex to reload its tool catalog.