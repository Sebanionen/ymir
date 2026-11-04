#!/usr/bin/env bash
# garmr.sh — GARMR, the hound at the gate: the door to Ymir's guardian.
#
#   garmr.sh status              # what is armed, what is running, what has been judged
#   garmr.sh install [--dry-run] # arm the senses (auditd) and seat the two units  [root]
#   garmr.sh start|stop|restart  # the hound (system) and the brain (user)
#   garmr.sh judge [--dry-run]   # run the judgement once, now
#   garmr.sh tail [N]            # the newest findings, judged, HIGH and CRITICAL first
#   garmr.sh once                # one sense pass (listeners/egress + audit so far)
#   garmr.sh verify              # prove the guardian is not silently dead
#
# Garmr notices, Vörðr judges in his report, Gná speaks, Runes keeps the record.
# He is read-only against the machine: he never closes a door, never kills a process.
#
# Exit: 0 ok · 1 a finding above the floor, or a broken surface · 2 usage.
set -u
VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GARMR="$ROOT/bin/ward/garmr"
PY="$(command -v python3 || echo /usr/bin/python3)"

usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; }

# Under sudo, HOME is root's and the hoard cannot resolve: adopt the operator's.
RUN_UID="${SUDO_UID:-$(id -u)}"
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
  RUN_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
  [ -n "$RUN_HOME" ] && export HOME="$RUN_HOME"
fi
as_operator() {  # run a command as the operator, with their session bus
  if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    sudo -u "$SUDO_USER" XDG_RUNTIME_DIR="/run/user/$RUN_UID" "$@"
  else
    "$@"
  fi
}

cmd="${1:-status}"; shift || true
dry=0
for a in "$@"; do
  case "$a" in
    --dry-run) dry=1 ;;
    -h|--help) usage; exit 0 ;;
    --version|-v) printf '%s\n' "$VERSION"; exit 0 ;;
  esac
done

hoard() {
  local lib="$ROOT/bin/vault/hoard-lib.sh" home=""
  if [ -r "$lib" ]; then
    # shellcheck disable=SC1090
    . "$lib" >/dev/null 2>&1 || true
    command -v ymir_home_root >/dev/null 2>&1 && ymir_home_root home
  fi
  if [ -z "$home" ] && [ -n "${YMIR_HOME:-}" ]; then home="$YMIR_HOME"; fi
  if [ -z "$home" ]; then
    printf 'error: the hoard is unresolved — set YMIR_HOME, or run from a checkout\n' >&2
    printf 'help: bin/vault/hoard-lib.sh must be able to answer\n' >&2
    exit 2
  fi
  printf '%s' "$home"
}
HOME_DIR="$(hoard)"
STATE="$HOME_DIR/hodd/state/garmr"
FINDINGS="/var/log/ymir/garmr/findings.jsonl"
AUDIT_LOG="/var/log/audit/audit.log"

# ONE file holds the rules, so a reboot cannot disarm the house (Rule 24).
rules_text() {
  local home="$1"
  # QUOTED heredoc: the block carries explanatory backticks (`a1`, `a2`, `pidfd_send_signal`),
  # and unquoted they were command substitution — every install printed "a1: command not
  # found" and blanked the very comment that explains the rules. Nothing here needs to
  # expand, and the one watch that wanted $home below is emitted after the block.
  cat <<'RULES'
# Ymir — Garmr's senses. Installed by bin/ward/garmr.sh install. Runtime-only
# rules vanish at reboot; this file is what brings them back.
-b 8192
-a always,exit -F arch=b64 -S execve -F auid>=1000 -F auid!=unset -k ymir-exec
# THE SIGNAL THAT ENDS A BROWSER, in every way it can arrive (fixed 2026-10-31).
# The two rules that stood here filtered `a1`, which is right for kill(2) and tkill(3) but WRONG for
# tgkill(2): there the signal is `a2` and `a1` is the TID, so `-F a1=9` matched when a thread id was 9 —
# i.e. never. And `pidfd_send_signal` (what systemd uses to kill a unit's processes) and the
# `rt_*sigqueueinfo` pair were not watched at all. Eleven browser deaths left no witness; this is why.
-a always,exit -F arch=b64 -S kill -F a1=15 -k ymir-browserkill
-a always,exit -F arch=b64 -S kill -F a1=9 -k ymir-browserkill
-a always,exit -F arch=b64 -S tkill -F a1=15 -k ymir-browserkill
-a always,exit -F arch=b64 -S tkill -F a1=9 -k ymir-browserkill
-a always,exit -F arch=b64 -S tgkill -F a2=15 -k ymir-browserkill
-a always,exit -F arch=b64 -S tgkill -F a2=9 -k ymir-browserkill
-a always,exit -F arch=b64 -S rt_sigqueueinfo -F a1=15 -k ymir-browserkill
-a always,exit -F arch=b64 -S rt_sigqueueinfo -F a1=9 -k ymir-browserkill
-a always,exit -F arch=b64 -S rt_tgsigqueueinfo -F a2=15 -k ymir-browserkill
-a always,exit -F arch=b64 -S rt_tgsigqueueinfo -F a2=9 -k ymir-browserkill
-a always,exit -F arch=b64 -S pidfd_send_signal -F a1=15 -k ymir-browserkill
-a always,exit -F arch=b64 -S pidfd_send_signal -F a1=9 -k ymir-browserkill
RULES
  # ── every watch below is guarded by the path's own existence ──────────────
  # auditd refuses the ENTIRE ruleset with ENOENT — "Error sending add rule data
  # request (No such file or directory)" — when a -w names a path that is not
  # there, and then the house runs with no rules at all, silently, saying only
  # `Failed to start Load Audit Rules` in the journal. That is what happened on
  # 2026-11-04: two watches named paths this seat does not have (the hoard has no
  # .ssh/, and this is a systemd box with no cron spool), so nothing was armed and
  # auditd had burnt 11s of CPU policing an empty ruleset. Guarded, and the real
  # key file — $HOME/.ssh/authorized_keys, where the fleet keys actually live — is
  # watched as well as the hoard's, if a seat has one there.
  for p in /etc/passwd /etc/shadow /etc/group /etc/sudoers /etc/sudoers.d; do
    [ -e "$p" ] && printf -- '-w %s -p wa -k ymir-identity\n' "$p"
  done
  for p in "$HOME/.ssh/authorized_keys" "$home/.ssh/authorized_keys"; do
    [ -e "$p" ] && printf -- '-w %s -p wa -k ymir-identity\n' "$p"
  done
  for p in /etc/systemd/system /etc/systemd/user /etc/cron.d /etc/crontab /var/spool/cron; do
    [ -e "$p" ] && printf -- '-w %s -p wa -k ymir-persist\n' "$p"
  done
  for dir in "$home/hodd/data/snotra" "$home/hodd/evidence" "$home/hodd/life/meetings" \
             "$home/hodd/memory/snotra" "$home/hodd/secrets"; do
    [ -d "$dir" ] && printf -- '-w %s -p wa -k ymir-sensitive\n' "$dir"
  done
  # persistence in the operator's own tree: a unit or an autostart entry added here
  for dir in "$home/.config/autostart" "$home/.config/systemd/user"; do
    [ -d "$dir" ] && printf -- '-w %s -p wa -k ymir-persist\n' "$dir"
  done
}

arm_senses() {
  local sensitive=(
    "$HOME_DIR/hodd/data/snotra"
    "$HOME_DIR/hodd/evidence"
    "$HOME_DIR/hodd/life/meetings"
    "$HOME_DIR/hodd/memory/snotra"
    "$HOME_DIR/hodd/secrets"
  )
  local run=(sudo)
  [ "$dry" = 1 ] && run=(echo "would run:")
  "${run[@]}" mkdir -p /var/log/ymir/garmr
  rules_text "$HOME_DIR" | "${run[@]}" tee /etc/audit/rules.d/ymir.rules >/dev/null
  # `auditctl -R` aborts on the first rule that already exists, so each line is
  # loaded on its own and an existing rule is not an error. augenrules does the
  # same job properly when the package ships it.
  if command -v augenrules >/dev/null 2>&1; then
    "${run[@]}" augenrules --load >/dev/null 2>&1 || true
  fi
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    # shellcheck disable=SC2086
    "${run[@]}" auditctl $line >/dev/null 2>&1 || true
  done < /etc/audit/rules.d/ymir.rules
}

seat_units() {
  local render="$SCRIPT_DIR/../../tools/mill/systemd"
  # The units must run the PINNED runtime, never the checkout an agent happens to be
  # standing in (runtime-pinned-guard). Resolve it once, and fall back to this tree
  # only when no pinned checkout exists.
  local unit_root="${YMIR_RUNTIME_DIR:-$HOME/ymir-runtime}"
  [ -d "$unit_root" ] || unit_root="$ROOT"
  local run=(sudo)
  [ "$dry" = 1 ] && run=(echo "would run:")
  # The hound's two units live in /etc and need root. A sudo that must ask for a
  # password will block an unattended refresh for ever — measured 2026-11-03, three
  # runs of Groa died here. Probe first; skip the root half with a named refusal and
  # still seat the operator's own brain timer below.
  if [ "$dry" = 1 ] || sudo -n true 2>/dev/null; then
    sed "s|__YMIR_ROOT__|$unit_root|g" "$render/garmr-hound.service" \
      | "${run[@]}" tee /etc/systemd/system/garmr-hound.service >/dev/null
    sed "s|__YMIR_ROOT__|$unit_root|g" "$render/garmr-arm.service" \
      | "${run[@]}" tee /etc/systemd/system/garmr-arm.service >/dev/null
    "${run[@]}" systemctl daemon-reload
    "${run[@]}" systemctl enable garmr-arm.service
    "${run[@]}" systemctl restart garmr-arm.service
    "${run[@]}" systemctl enable --now garmr-hound.service
  else
    printf 'garmr: the hound needs root, and sudo is not available without a password here; its two system units were left alone (run: sudo -v, then garmr.sh install)\n' >&2
  fi
  mkdir -p "$HOME/.config/systemd/user"
  sed "s|__YMIR_ROOT__|$unit_root|g; s|__PYTHON__|$PY|g" "$render/garmr-brain.service" \
    > "$HOME/.config/systemd/user/garmr-brain.service"
  cp "$render/garmr-brain.timer" "$HOME/.config/systemd/user/garmr-brain.timer"
  as_operator systemctl --user daemon-reload
  as_operator systemctl --user enable --now garmr-brain.timer
}

status() {
  local hound brain judged=0
  hound="$(systemctl is-active garmr-hound.service 2>/dev/null || echo unknown)"
  brain="$(systemctl --user is-active garmr-brain.timer 2>/dev/null || echo unknown)"
  [ -f "$STATE/judged.jsonl" ] && judged="$(wc -l < "$STATE/judged.jsonl" | tr -d ' ')"
  printf 'garmr{seals}:\n'
  printf '  hound (system)          %s\n' "$hound"
  printf '  brain timer (user)      %s\n' "$brain"
  printf '  audit rules armed       %s\n' "$(sudo -n auditctl -l 2>/dev/null | grep -c ymir- || echo '0 (or no sudo)')"
  printf '  findings file           %s\n' "$([ -f "$FINDINGS" ] && wc -l < "$FINDINGS" | tr -d ' ' || echo 'none yet')"
  printf '  judged                  %s\n' "$judged"
  printf '  heartbeat               %s\n' "$(cat "$STATE/hound.heartbeat" 2>/dev/null || echo 'never')"
  printf '  paused                  %s\n' "$([ -f /var/log/ymir/garmr/PAUSED ] && echo "yes (root marker, since $(cat /var/log/ymir/garmr/PAUSED))" || echo no)"
  printf '  config                  %s\n' "$(GARMR_PRINT_CONFIG=1 "$PY" - <<'PY' 2>/dev/null
import sys, os
sys.path.insert(0, os.path.join(os.environ.get('ROOT','.'), 'bin/ward/garmr'))
import common
print(common.load_config()['_config_path'])
PY
)"
}

verify() {
  local fails=0
  "$PY" "$GARMR/hound.py" --once --stdout >/dev/null 2>&1 || { echo "FAIL: the hound cannot run"; fails=$((fails+1)); }
  [ -f "$FINDINGS" ] || { echo "note: no findings file yet — the hound has written nothing"; }
  local beat="$STATE/hound.heartbeat"
  if [ -f "$beat" ]; then
    local age=$(( $(date +%s) - $(date -r "$beat" +%s) ))
    [ "$age" -gt 600 ] && { echo "FAIL: the hound is silent (heartbeat ${age}s old)"; fails=$((fails+1)); }
  else
    echo "note: no heartbeat yet — the hound has not run as the service"
  fi
  systemctl is-active --quiet garmr-hound.service || { echo "note: garmr-hound.service is not active"; }
  [ "$fails" -eq 0 ] && echo "garmr: surfaces whole"
  return "$fails"
}

case "$cmd" in
  pause|resume)
    # The on/off switch is ROOT's. A guardian an ordinary process can silence is a
    # guardian that can be silenced by the thing it watches.
    if [ "$(id -u)" -ne 0 ]; then
      printf 'refused: pausing or resuming the hound needs root.\n' >&2
      printf 'help: sudo bin/ward/garmr.sh %s\n' "$cmd" >&2
      exit 1
    fi
    marker="/var/log/ymir/garmr/PAUSED"
    log="/var/log/ymir/garmr/pause.log"
    mkdir -p /var/log/ymir/garmr
    if [ "$cmd" = "pause" ]; then
      date -Iseconds > "$marker"
      printf '%s\tpaused\tby uid %s\n' "$(date -Iseconds)" "${SUDO_UID:-$UID}" >> "$log"
      systemctl stop garmr-hound.service 2>/dev/null || true
      as_operator systemctl --user stop garmr-brain.timer 2>/dev/null || true
      printf 'garmr: PAUSED by root at %s — the state is written down, and the tower will say so\n' "$(date -Iseconds)"
    else
      if [ -f "$marker" ]; then
        printf '%s\tresumed\twas paused since %s\n' "$(date -Iseconds)" "$(cat "$marker")" >> "$log"
      fi
      rm -f "$marker"
      systemctl start garmr-hound.service 2>/dev/null || true
      as_operator systemctl --user start garmr-brain.timer 2>/dev/null || true
      printf 'garmr: resumed\n'
    fi ;;
  refresh)
    seat_units
    printf 'garmr: units re-rendered and reloaded (rules untouched)\n' ;;
  status)  status ;;
  install) arm_senses; seat_units; echo "garmr: senses armed, units seated" ;;
  start)   sudo systemctl start garmr-hound.service; systemctl --user start garmr-brain.timer ;;
  stop)    sudo systemctl stop garmr-hound.service; systemctl --user stop garmr-brain.timer ;;
  restart) sudo systemctl restart garmr-hound.service; systemctl --user restart garmr-brain.timer ;;
  judge)   "$PY" "$GARMR/brain.py" --once ${dry:+--dry-run} ;;
  once)    "$PY" "$GARMR/hound.py" --once ;;
  verify)  verify ;;
  tail)    "$PY" "$GARMR/brain.py" --file "$FINDINGS" --once --dry-run | tail -n "${1:-20}" ;;
  -h|--help) usage ;;
  *) printf 'error: unknown command %s\nhelp: garmr.sh [status|install|start|stop|restart|judge|once|verify|tail]\n' "$cmd" >&2; exit 2 ;;
esac
