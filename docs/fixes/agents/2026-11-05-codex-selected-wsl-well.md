# Codex: an explicitly selected WSL well

Windows Codex and WSL can have different private homes. Checking only a local
port can make Codex drink from the wrong store or fall back to a different
home's offline log when the selected well is unavailable.

An explicit private configuration chooses a WSL distribution, Linux checkout,
home and exact database. The adapter starts the chosen user service, verifies
the bridge store from within that distribution, and runs the CLI with the
bridge required. A mismatch or unreachable bridge fails without writing another
home's fallback log. No existing data is migrated or merged. Synthetic tests
exercise service failure, mismatch, persistence, and strict offline behavior.
