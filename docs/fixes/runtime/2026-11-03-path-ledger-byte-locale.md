# Path-ledger preserves matching lines in legacy catalog bytes

The initial recursive grep now uses LC_ALL=C on the same physical command line. Invalid UTF-8 in an existing generated capability catalog previously caused grep to emit a binary-file summary, discarding the line that carried both the superseded path and its replacement. The guard then falsely reported that paired migration record as stale.

Byte-oriented matching preserves the actual line. It does not skip binary files, waive paths or suppress stale-only matches. A real-guard regression checks invalid-UTF-8 paired and old-only records alongside their valid-UTF-8 equivalents: paired records pass and old-only references fail on native Git Bash and Linux. The guard's physical line count stays unchanged; no capability catalog or full inventory was regenerated for this fix.
