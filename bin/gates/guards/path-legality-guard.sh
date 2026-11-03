#!/usr/bin/env bash
# path-legality-guard.sh — a tracked path must be a name EVERY host can hold.
#
# WHY (2026-11-03): the repo root carried a zero-byte file named
# `Wed 2026-09-30 20:29:43 (1h 22min ago)` — debris from a redirect. Git held it; Windows
# cannot (a `:` is illegal on NTFS), so `git clone` on a Windows host fetched the objects and
# then died on that path with `error: invalid path`, writing NO tree at all. It survived a
# month because every seat that looked at it was Linux. Windows is a supported host by
# RULES/05 (it hosts Linux through WSL2) — so a name the host OS cannot hold is a trap laid
# across the whole path an operator on Windows walks, and no ward looked at names as names.
#
# WHAT IT JUDGES (the hosts RULES/05 names — this is the write side of agnostic):
#   · NTFS-illegal characters in any segment        : * ? " < > |
#     and the control characters, including NUL
#   · a segment ending in a space or a dot          (Windows silently strips them: two names collide)
#   · a reserved DOS device name                    CON PRN AUX NUL COM1-9 LPT1-9
#   · a segment longer than 255 bytes, or a whole path longer than 260 characters
#   · two paths differing only by CASE              (macOS and Windows are case-insensitive)
#
# WHAT IT DOES NOT JUDGE: a path that MOVED (that is path-ledger-guard), or a path a document
# NAMES (that is docs-claims / packaging-guard). This ward reads the tree's own file list.
#
#   path-legality-guard.sh check    # the ward
#   path-legality-guard.sh          # alias
#
# Exit: 0 every tracked path is legal · 1 findings · 2 usage.
set -u

VERSION="1.0.0"
_root() {
  local d; d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [ "$d" != "/" ]; do
    [ -d "$d/.pi" ] && [ -d "$d/RULES" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
}
ROOT="${YMIR_GUARD_ROOT:-$(_root)}"
cd "$ROOT" 2>/dev/null || { printf 'path-legality-guard: cannot enter %s\n' "$ROOT" >&2; exit 2; }

case "${1:-check}" in
  check|"") ;;
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) printf 'error: unknown flag %s\nhelp: path-legality-guard.sh [check]\n' "$1" >&2; exit 2 ;;
esac

command -v git >/dev/null 2>&1 || { printf 'path-legality-guard: git absent\n' >&2; exit 2; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  printf 'path-legality-guard[1]{state,reason}:\n  "SKIP","not a git worktree"\n'; exit 0; }

LIST="$(mktemp)"; trap 'rm -f "$LIST"' EXIT
git ls-files -z >"$LIST" || { printf 'path-legality-guard: git ls-files failed\n' >&2; exit 2; }

# One finding per offending path, in a stable order, so the remedy is copy-pasteable.
rows="$(python3 - "$LIST" <<'PY'
import os, re, sys

illegal_char = re.compile(r'[:*?"<>|\x00-\x1f]')
reserved = {"con","prn","aux","nul"} | {f"com{i}" for i in range(1, 10)} | {f"lpt{i}" for i in range(1, 10)}

data = open(sys.argv[1], 'rb').read().split(b'\0')
paths = [p.decode('utf-8', 'surrogateescape') for p in data if p]

findings = []
for p in paths:
    reason = ""
    for seg in p.split('/'):
        if illegal_char.search(seg):
            reason = "a character Windows cannot hold in a name"
            break
        if seg.endswith(" ") or seg.endswith("."):
            reason = "a name ending in a space or a dot (Windows strips it: two names collide)"
            break
        if seg.split(".")[0].lower() in reserved:
            reason = "a reserved DOS device name"
            break
        if len(seg.encode('utf-8', 'surrogateescape')) > 255:
            reason = "a name longer than 255 bytes"
            break
    if not reason and len(p) > 260:
        reason = "a path longer than 260 characters (Windows MAX_PATH)"
    if reason:
        findings.append((p, reason))

for p, reason in findings:
    print(f'{p}\t{reason}')

# case-only collisions: macOS and Windows keep ONE of the two and lose the other silently.
seen = {}
for p in paths:
    seen.setdefault(p.lower(), []).append(p)
for low, group in sorted(seen.items()):
    if len(group) > 1:
        print('\t'.join(group) + "\ttwo paths that differ only by case (macOS and Windows are case-insensitive)")
PY
)"

if [ -z "$rows" ]; then
  printf 'path_legality[1]{checked,verdict}:\n'
  printf '  "%s","PASS — every tracked name is legal on Linux, macOS and Windows"\n' "$(git ls-files | wc -l | tr -d ' ')"
  exit 0
fi

n="$(printf '%s\n' "$rows" | grep -c . || true)"
printf 'path_legality[2]{checked,finding}:\n'
printf '  "%s","a tracked name this tree cannot hold on every host RULES/05 names"\n' "$n"
printf '%s\n' "$rows" | head -20 | while IFS="$(printf '\t')" read -r path reason; do
  [ -n "$path" ] && printf '  "%s","%s"\n' "$path" "$reason"
done
cat >&2 <<'MSG'

  A name Windows cannot hold breaks `git clone` on a Windows host BEFORE any install runs —
  no tree is written at all. macOS and Windows are both case-insensitive, so two names that
  differ only by case lose one of them on checkout.

  Remedy: rename the path (git mv) and write the move into .agents/paths-ledger.yaml, or
  — if the file must not exist at all — retire it to the home's reference shelf and remove it
  with the Rule 11 escape, so the removal is logged and visible:

      YMIR_ALLOW_DELETE="a name no Windows checkout can hold — kept at hodd/reference/…" git rm <path>

  Then push and let the guard see it again.
MSG
exit 1
