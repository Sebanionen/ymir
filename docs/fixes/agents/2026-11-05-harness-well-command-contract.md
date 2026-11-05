# The harnesses call the well with its real command contract

Codex and OpenCode passed the recall limit as a positional argument even though
`mimir.sh recall` requires `--k`, and exposed `search` and `stats` actions
that `mimir.sh` did not implement. Recall therefore failed before contacting
the well, and the other actions failed as unknown commands.

Both adapters now pass `--k`; search is explicitly an alias for hybrid recall
and stats calls health. The Codex integration test exercises the real CLI with
an isolated temporary well and checks its result limit and offline health.

The HTTP bridge also returned its full over-fetched candidate set instead of
at most `k`. The CLI passed that JSON as one command-line argument, which can
exceed the platform argument limit, then reported success after printer failure.
The bridge now validates and enforces the result limit; the CLI carries the
payload over standard input and returns a printer error to its caller. If the
bridge is unavailable and the local log has no matching result, recall reports
an error instead of treating the missing remote answer as an empty well.

The local JSONL fallback is identified as such in the output, both after a
bridge failure and after a valid empty bridge answer. This distinction matters
when the bridge and CLI were configured with different homes.
