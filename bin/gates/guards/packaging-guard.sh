#!/usr/bin/env bash
# packaging-guard.sh — every path a shipped installer names must exist in the tree.
#
# WHY (2026-11-03): Rule 22 moved the host layers under `bin/host/`. The Windows installer
# (`packaging/windows/ymir-setup.nsi`) went on naming `bin\bootstrap-windows.ps1`, and so did
# the README row that told an operator what to run. Nothing looked, because the only thing that
# WOULD have looked — the NSIS build — runs on tags (`push: tags: v*`) and no tag had been cut
# since the move. So the packaged Windows door was broken for a month and every gate was green:
# a gate that never runs is not a green gate, it is an absent one. Canvas 2026-11-03.
#
# WHAT IT JUDGES, all measured from the packaging artifacts themselves:
#   1. every `File "<path>"` in packaging/windows/*.nsi — NSIS resolves it relative to the .nsi,
#      and a missing source is a COMPILE error, so the .exe cannot be built at all;
#   2. every `$ROOT/<path>` a packaging script copies or tests — the inputs the build claims;
#   3. a copy that is allowed to FAIL SILENTLY (`|| true`, `2>/dev/null`) ships an installer with
#      a missing piece and no error: that is refused here too.
#
#   packaging-guard.sh check    # the ward
#   packaging-guard.sh          # alias
#
# Exit: 0 every named input exists · 1 findings · 2 usage.
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
cd "$ROOT" 2>/dev/null || { printf 'packaging-guard: cannot enter %s\n' "$ROOT" >&2; exit 2; }

case "${1:-check}" in
  check|"") ;;
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) printf 'error: unknown flag %s\nhelp: packaging-guard.sh [check]\n' "$1" >&2; exit 2 ;;
esac

[ -d packaging ] || { printf 'packaging_guard[1]{state,reason}:\n  "SKIP","no packaging shelf in this tree"\n'; exit 0; }

findings=""
note() { findings="${findings}$1"$'\n'; }

# ── 1. NSIS File directives: the input must exist where NSIS will look ───────
while IFS= read -r nsi; do
  [ -n "$nsi" ] || continue
  dir="$(dirname "$nsi")"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    # NSIS resolves a relative path against the .nsi's own directory.
    case "$rel" in
      /*|[A-Za-z]:*) target="$rel" ;;
      *) target="$dir/$rel" ;;
    esac
    target="${target//\\//}"
    [ -e "$target" ] || note "$nsi|the File directive names a file that does not exist: $rel (looked for $target)"
  # The LAST quoted token is the source; the first may be `/oname=…` (an NSIS modifier).
  done < <(sed -n 's/^[[:space:]]*File[[:space:]]\{1,\}//p' "$nsi" | sed -n 's/.*"\([^"]*\)"[[:space:]]*;\{0,1\}.*$/\1/p')
done < <(find packaging -name '*.nsi' -type f 2>/dev/null | sort)

# ── 2. every $ROOT/<path> a packaging script names ───────────────────────────
while IFS= read -r f; do
  [ -n "$f" ] || continue
  while IFS= read -r rel; do
    rel="${rel%%\**}"                      # a glob names a prefix, not a path
    rel="${rel%"${rel##*[! ]}"}"            # trailing spaces from a quoted "a b" argument
    [ -n "$rel" ] || continue
    case "$rel" in
      *'$'*) continue ;;                    # built from a variable at run time
      packaging/out|packaging/out/*) continue ;;  # the OUTPUT shelf: created by the build itself
      */|*-) continue ;;                    # a directory or an artifact prefix ($ROOT/out/…)
    esac
    [ -e "$ROOT/$rel" ] || note "$f|names \$ROOT/$rel, which is not in the tree"
  done < <(grep -o '\$ROOT/[^"]*' "$f" 2>/dev/null | sed 's|^\$ROOT/||')
done < <(find packaging -type f \( -name '*.sh' -o -name '*.command' \) 2>/dev/null | sort)

# ── 3. a packaging copy that may fail silently ───────────────────────────────
while IFS= read -r f; do
  [ -n "$f" ] || continue
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    note "$f|a packaging copy suppresses its own failure, so a missing input ships silently: ${line# }"
  done < <(grep -nE '^\s*(cp|install)\b.*(\|\|\s*true|2>/dev/null)' "$f" 2>/dev/null | head -5)
done < <(find packaging -type f -name '*.sh' 2>/dev/null | sort)

if [ -z "$findings" ]; then
  printf 'packaging_guard[2]{checked,verdict}:\n'
  printf '  "%s","PASS — every path a shipped installer names exists"\n' "$(find packaging -type f | wc -l | tr -d ' ')"
  printf '  "build","PROVED by .github/workflows/ymir-installers.yml on a packaging change"\n'
  exit 0
fi

n="$(printf '%s' "$findings" | grep -c . || true)"
printf 'packaging_guard[2]{checked,finding}:\n'
printf '  "%s","a shipped installer names a path the tree does not hold"\n' "$n"
printf '%s' "$findings" | head -20 | while IFS='|' read -r where why; do
  printf '  "%s","%s"\n' "$where" "$why"
done
cat >&2 <<'MSG'

  A shipped installer that names a missing file is a broken door, and the break is invisible
  until somebody builds it. Fix the name (the file it means), or the file (put it where the
  installer says) — and if a path MOVED, record the move in .agents/paths-ledger.yaml in the
  same change (Rule 25: a move is a migration).

  Prove it by building the artifact, not by reading the diff:

      packaging/build.sh --exe        # NSIS is a compiler: this runs on Linux too
      packaging/build.sh --check      # what this host can build, and with what
MSG
exit 1
