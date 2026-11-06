#!/usr/bin/env bash
# install.sh — seat Gná's desk on THIS machine. Idempotent: one desk per install.
#
#   bash bin/mail/install.sh [--port 8494] [--user]
#
# - installs a systemd USER unit (gna-desk.service) that runs the desk on loopback
# - Restart=always: a desk that dies is raised again, because a dead desk and an
#   empty inbox must never look the same to the gate
# - enables it, starts it, and proves /health answers before it says it is done
#
# The desk reads its store and scope from the HOME (Rule 04):
#   $YMIR_HOME/hodd/memory/mail/{accounts.yaml,retention.yaml,messages.jsonl}
#   $YMIR_HOME/hodd/state/gna-desk.token
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
PORT="${GNA_DESK_PORT:-8494}"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT="$UNIT_DIR/gna-desk.service"
PY="$(command -v python3 || echo /usr/bin/python3)"

while [ $# -gt 0 ]; do case "$1" in
  --port) PORT="${2-}"; shift 2 ;;
  --user) shift ;;
  -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "install: unknown option $1" >&2; exit 2 ;;
esac; done

command -v systemctl >/dev/null 2>&1 || { echo "install: no systemctl — this seat cannot be served by systemd" >&2; exit 1; }
mkdir -p "$UNIT_DIR"

cat > "$UNIT" <<UNITEOF
[Unit]
Description=Gna — the one mail desk (read-only, loopback)
Documentation=file://$ROOT/docs/features/gna-the-one-mail-desk.md
After=network-online.target

[Service]
Type=simple
WorkingDirectory=$ROOT
Environment=GNA_DESK_PORT=$PORT
Environment=YMIR_TREE=$ROOT
ExecStart=$PY $ROOT/bin/mail/gna_desk.py --port $PORT
Restart=always
RestartSec=5
# The desk reads the vault and the home store; it writes only its own state.
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=default.target
UNITEOF

# A unit seated from a WORKTREE is honest tonight and fragile tomorrow: prune the
# worktree and the desk has no code. Say so rather than discover it at a reboot.
case "$ROOT" in
  */.yggdrasil/*) printf 'install: WARNING — seated from a worktree (%s), not from the main tree.\n          Re-run this installer from the main checkout after the branch merges.\n' "$ROOT" >&2 ;;
esac

systemctl --user daemon-reload
systemctl --user enable --now gna-desk.service >/dev/null 2>&1 || {
  echo "install: systemctl could not enable gna-desk.service" >&2
  systemctl --user status gna-desk.service --no-pager 2>&1 | tail -12 >&2
  exit 1
}

for _ in 1 2 3 4 5 6 7 8 9 10; do
  sleep 0.6
  if curl -fsS -m 3 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    HEALTH="$(curl -fsS -m 3 "http://127.0.0.1:$PORT/health" 2>/dev/null)"
    printf 'install{desk,port,unit,health}:\n'
    printf '  "gna-desk","%s","%s","%s"\n' "$PORT" "$UNIT" "$(printf '%s' "$HEALTH" | head -c 160)"
    printf '  token in hodd/state/gna-desk.token (inside the home) · a reboot raises it again\n'
    exit 0
  fi
done

echo "install: the unit is enabled but /health did not answer on 127.0.0.1:$PORT" >&2
systemctl --user status gna-desk.service --no-pager 2>&1 | tail -15 >&2
exit 1
