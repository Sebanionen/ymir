#!/usr/bin/env bash
# seats.sh — where the work actually is: panes in either backend, and the dead shells named.
#
#   seats.sh list     # herdr first, tmux fallback; a shell whose owner is gone is named DEAD
#   seats.sh close <pane>
#
# A pane's state is the BACKEND's own report, never a claim of ours:
#   working · idle    a live agent holds the pane (close refuses it)
#   shell             a bare shell in an ordinary directory — yours to keep
#   DEAD              a bare shell inside a disposable .yggdrasil worktree: the errand it
#                     was seated for is gone and nothing will ever answer in it again
set -uo pipefail

# herdr's `pane list` answers JSON; render the fields a person needs, one pane per line.
# `-c` and not a heredoc: a heredoc would take stdin from the script and eat the pipe.
render_herdr() {
  python3 -c '
import json, sys
try:
    panes = (json.load(sys.stdin).get("result") or {}).get("panes") or []
except Exception:
    sys.exit(1)
print("pane      agent     state     dir                              title")
for p in panes:
    pid = p.get("pane_id") or "?"
    agent = p.get("agent") or ""
    status = p.get("agent_status") or ""
    cwd = p.get("cwd") or p.get("foreground_cwd") or "-"
    title = p.get("terminal_title") or p.get("terminal_title_stripped") or ""
    if not agent or status in ("", "unknown"):
        agent = "-"
        status = "DEAD" if "/.yggdrasil/" in cwd else "shell"
    print(f"{pid:<9} {agent:<9} {status:<9} {cwd:<32} {title}")
'
}

# one pane's own record, so a refusal is decided on the JSON and not on a substring of it:
# `<agent> <agent_status> <cwd>` or empty when the pane is not there.
herdr_pane() {
  herdr pane list 2>/dev/null | python3 -c '
import json, sys
want = sys.argv[1]
try:
    panes = (json.load(sys.stdin).get("result") or {}).get("panes") or []
except Exception:
    sys.exit(0)
for p in panes:
    if p.get("pane_id") == want:
        print(p.get("agent") or "-", p.get("agent_status") or "-", p.get("cwd") or "-")
        break
' "$1"
}

case "${1:-list}" in
  -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  list)
    if command -v herdr >/dev/null 2>&1 && herdr pane list >/dev/null 2>&1; then
      echo "backend: herdr"
      herdr pane list 2>/dev/null | render_herdr || echo "herdr answered, but not with a pane list"
    elif command -v tmux >/dev/null 2>&1 && tmux list-panes -a >/dev/null 2>&1; then
      echo "backend: tmux"
      printf 'pane                     state     command        dir                              title\n'
      tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}|#{pane_current_command}|#{pane_current_path}|#{pane_title}' 2>/dev/null |
      while IFS='|' read -r pane cmd path title; do
        case "$cmd" in
          bash|zsh|sh|"") case "$path" in */.yggdrasil/*) state=DEAD ;; *) state=shell ;; esac ;;
          *) state="$cmd" ;;
        esac
        printf '%-24s %-9s %-14s %-32s %s\n' "$pane" "$state" "$cmd" "$path" "$title"
      done
    else
      echo "no pane backend is running (herdr and tmux both silent)"
    fi ;;
  close)
    # close a shell whose OWNER is gone — never a live seat
    target="${2:-}"; [ -n "$target" ] || { echo "close needs a pane id" >&2; exit 2; }
    if command -v herdr >/dev/null 2>&1; then
      record="$(herdr_pane "$target")"
      if [ -n "$record" ]; then
        read -r agent status cwd <<<"$record"
        case "$agent" in
          -|"") : ;;  # no agent attached — the shell is nobody's seat
          *) printf 'refused: %s holds a live agent (%s, %s)\n' "$target" "$agent" "$status"; exit 1 ;;
        esac
        case "$status" in
          working|idle) printf 'refused: %s holds a live agent\n' "$target"; exit 1 ;;
        esac
        herdr pane close "$target" 2>/dev/null && printf 'closed %s (no live agent held it; %s)\n' "$target" "$cwd" && exit 0
      fi
    fi
    if command -v tmux >/dev/null 2>&1 && tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null | grep -qx "$target"; then
      cmd="$(tmux display-message -p -t "$target" '#{pane_current_command}' 2>/dev/null)"
      case "$cmd" in bash|zsh|sh|"") tmux kill-pane -t "$target" && printf 'closed %s (bare shell)\n' "$target" && exit 0 ;; esac
      printf 'refused: %s is running %s\n' "$target" "$cmd"; exit 1
    fi
    printf 'no such pane: %s\n' "$target"; exit 1 ;;
  *) printf 'error: unknown action %s\nhelp: seats.sh [list|close <pane>]\n' "$1" >&2; exit 2 ;;
esac
