#!/usr/bin/env bash
# runtime-pinned-guard.sh — a unit that executes from a WORKING tree is a machine running whatever branch
# the last agent left checked out.
#
# Rule: RULES/02 §7 (appended 2026-11-02). Measured that day: ten user units pointed at /home/heimdall/ymir —
# the directory agents switch branches in — so a `git checkout` changed the code the scheduler, the well, the
# model bridge, the MCP face, the warden and the assistant were running, silently, with no approval.
#
#   bash bin/gates/guards/runtime-pinned-guard.sh [check]
#
# Exit 0 when every unit that names the tree names a PINNED checkout, and that checkout stands on the default
# branch. A seat with no user units (a hand, a CI runner) SKIPs at exit 0 — a clean skip is a pass (RULES/25).
set -uo pipefail

ROOT="$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
home=""
declare -f ymir_home_root >/dev/null 2>&1 && ymir_home_root home 2>/dev/null
[ -n "$home" ] || home="${YMIR_HOME:-}"
conf="${home:+$home/config/runtime.env}"
[ -n "$conf" ] && [ -r "$conf" ] && . "$conf"
PIN="${YMIR_RUNTIME_DIR:-$HOME/ymir-runtime}"
BRANCH="${YMIR_RUNTIME_BRANCH:-main}"

# Ask git about ANOTHER checkout without the caller's repository in the way. This ward runs
# inside the pre-push hook, and git exports GIT_DIR (and friends) to a hook: with GIT_DIR set,
# `git -C <other tree>` answers about the PUSHING tree, not the one it was pointed at. Measured
# 2026-11-02 — the first push from a worktree was refused with "the pinned runtime stands on
# yggdrasil/<branch>, not main", about a runtime that was standing on main: the ward read the
# pushing branch and blamed the operator's runtime for it. Every push this house makes comes
# from a worktree (Rule 08), so the gate refused all of them.
gother() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE git "$@"; }

command -v systemctl >/dev/null 2>&1 || {
  printf 'runtime-pinned-guard[1]{finding,detail}:\n  "none","no systemd on this host — units are another role\x27s business"\n'; exit 0; }
systemctl --user list-unit-files >/dev/null 2>&1 || {
  printf 'runtime-pinned-guard[1]{finding,detail}:\n  "none","no user manager reachable — a clean skip"\n'; exit 0; }

bad=()
while IFS= read -r f; do
  [ -n "$f" ] || continue
  unit=$(basename "$f")
  exec_line=$(grep -m1 '^ExecStart=' "$f" 2>/dev/null | cut -d= -f2-)
  [ -n "$exec_line" ] || continue
  # the path a unit actually executes — the first absolute path in the line
  target=$(printf '%s' "$exec_line" | grep -oE '/[^ ]+\.(sh|py|js|mjs)' | head -1)
  [ -n "$target" ] || continue
  case "$target" in
    "$PIN"/*) continue ;;                      # the pinned checkout: correct by definition
    /home/*/ymir/*|*/ymir/bin/*|*/ymir/systems/*|*/ymir/tools/*)
      # is it inside a git WORKING tree (a checkout a human switches branches in)?
      top=$(gother -C "$(dirname "$target")" rev-parse --show-toplevel 2>/dev/null)
      [ -n "$top" ] && bad+=("$unit → $target (working tree)") ;;
  esac
done < <(ls "$HOME/.config/systemd/user"/*.service 2>/dev/null)

if [ "${#bad[@]}" -gt 0 ]; then
  printf 'runtime-pinned-guard[%s]{finding,unit}:\n' "${#bad[@]}"
  for b in "${bad[@]}"; do printf '  "a unit runs a working tree","%s"\n' "$b"; done
  printf 'help: point those units at %s (bin/engine/runtime-deploy.sh does the move and proves it)\n' "$PIN" >&2
  exit 1
fi

if [ -d "$PIN/.git" ]; then
  cur=$(gother -C "$PIN" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ "$cur" != "$BRANCH" ]; then
    printf 'runtime-pinned-guard[1]{finding,detail}:\n  "the pinned runtime is off its branch","%s stands on %s, not %s"\n' "$PIN" "${cur:-unknown}" "$BRANCH"
    printf 'help: git -C %s checkout %s (or run bin/engine/runtime-deploy.sh)\n' "$PIN" "$BRANCH" >&2
    exit 1
  fi
  printf 'runtime-pinned-guard[1]{finding,detail}:\n  "none","every unit names %s, and it stands on %s"\n' "$PIN" "$BRANCH"
  exit 0
fi

printf 'runtime-pinned-guard[1]{finding,detail}:\n  "none","no unit names a working tree; no pinned checkout on this seat yet"\n'
exit 0
