## hoard · unversioned · 2026-11-12 — a home path with a space is not a home path without one

### Why
- `bin/vault/hoard-lib.sh` read the recorded home (`~/.config/ymir/home`) through
  `tr -d '[:space:]'`, which deletes **every** whitespace character, not the line
  ending. On a Windows profile the recorded home is
  `C:/Users/Agent Seb/ymirhome`; the library returned
  `C:/Users/AgentSeb/ymirhome`.
- That path cannot exist, and every consumer read the mangled name: a unit
  pointing at it failed with `PermissionError`, the well bridge crash-looped at
  start, its MCP door had no backend, and a gate that logs a deletion could not
  write its log (`…/AgentSeb/ymirhome/hodd/memory/…: No such file or directory`)
  while reporting the deletion as logged.
- The same shape sits in `tr -d '[:space:]'` reads of pointer files; a home path
  is the one value that may legitimately contain a space.

### Fix
- `ymir_home_record` strips only `\r\n`. A recorded path is taken verbatim.

### Verify
- `printf 'C:/Users/Agent Seb/ymirhome\n' > ~/.config/ymir/home` then
  `bash -c '. bin/vault/hoard-lib.sh; ymir_home_root h; printf "%s\n" "$h"'`
  prints the path with its space.
- A script that resolves the home (for example `bin/no-delete-guard.sh`) writes
  its log under the real home instead of failing on a path it invented.

### Files
- `bin/vault/hoard-lib.sh`
