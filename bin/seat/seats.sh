#!/usr/bin/env bash
# seats.sh — where the work actually is: panes in either backend, and the dead shells named.
#
#   seats.sh list     # herdr first, tmux fallback; a shell whose owner is gone is named DEAD
set -uo pipefail
case "${1:-list}" in
  -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  list)
    if command -v herdr >/dev/null 2>&1 && herdr pane list >/dev/null 2>&1; then
      echo "backend: herdr"; herdr pane list 2>/dev/null | head -40
    elif command -v tmux >/dev/null 2>&1 && tmux list-panes -a >/dev/null 2>&1; then
      echo "backend: tmux"; tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_title} pid=#{pane_pid} cmd=#{pane_current_command}' 2>/dev/null | head -40
    else
      echo "no pane backend is running (herdr and tmux both silent)"
    fi ;;
  close)
    # close a shell whose OWNER is gone — never a live seat
    target="${2:-}"; [ -n "$target" ] || { echo "close needs a pane id" >&2; exit 2; }
    if command -v herdr >/dev/null 2>&1; then
      info="$(herdr pane list 2>/dev/null | grep -o "\"pane_id\":\"$target\"[^}]*" | head -1)"
      case "$info" in
        *'"agent_status":"working"'*|*'"agent_status":"idle"'*) printf 'refused: %s holds a live agent\n' "$target"; exit 1 ;;
      esac
      herdr pane close "$target" 2>/dev/null && printf 'closed %s (no live agent held it)\n' "$target" && exit 0
    fi
    if command -v tmux >/dev/null 2>&1 && tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null | grep -qx "$target"; then
      cmd="$(tmux display-message -p -t "$target" '#{pane_current_command}' 2>/dev/null)"
      case "$cmd" in bash|zsh|sh|"") tmux kill-pane -t "$target" && printf 'closed %s (bare shell)\n' "$target" && exit 0 ;; esac
      printf 'refused: %s is running %s\n' "$target" "$cmd"; exit 1
    fi
    printf 'no such pane: %s\n' "$target"; exit 1 ;;
  *) printf 'error: unknown action %s\nhelp: seats.sh [list|close <pane>]\n' "$1" >&2; exit 2 ;;
esac
