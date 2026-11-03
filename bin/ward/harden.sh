#!/usr/bin/env bash
# harden.sh — Vörðr's hands: the MENDS, written out, and the safe ones applied.
#
# A warden that only reports is half a warden — but a warden that changes the firewall
# on a travelling box without being asked is a warden that locks its operator out. So:
#
#   harden.sh plan                 # every mend, with its risk and its revert line — changes NOTHING
#   harden.sh apply --sshd         # keys-only login (backup + validate + rollback on failure)
#   harden.sh apply --ssh-keys-perm# chmod 600 the plaintext secrets and the vault key
#   harden.sh apply --ufw          # REFUSED unless --i-will-not-travel-blind; prints the exact rules
#
# Why --ufw is refused by default, in one sentence: narrowing 22/3889 to the LAN and
# the tailnet is right for a box that stays home and wrong for one that is about to be
# opened in a hotel — the tailnet is the road that always works, and that is a decision.
#
# Exit: 0 ok · 1 a mend failed (and was rolled back where it could be) · 2 usage · 3 refused.
set -u

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"

if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  for _w in "$SCRIPT_DIR/../vault/hoard-lib.sh"; do
    [ -r "$_w" ] && { . "$_w"; YMIR_HOARD_LIB_LOADED=1; break; }
  done
fi
HOME_DIR=""; [ -n "${YMIR_HOME:-}" ] && HOME_DIR="$YMIR_HOME"
[ -n "$HOME_DIR" ] || { command -v ymir_home_root >/dev/null 2>&1 && ymir_home_root HOME_DIR; }

SSHD_DROPIN="/etc/ssh/sshd_config.d/10-ymir-ward.conf"
STAMP="$(date -u +%Y%m%d-%H%M%S)"

usage() { sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; }

ACTION="${1:-plan}"; shift || true
DO_SSHD=0 DO_KEYS=0 DO_UFW=0 FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --sshd) DO_SSHD=1; shift ;;
    --ssh-keys-perm) DO_KEYS=1; shift ;;
    --ufw) DO_UFW=1; shift ;;
    --i-will-not-travel-blind) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    *) printf 'error: unknown flag %s\nhelp: harden.sh --help\n' "$1" >&2; exit 2 ;;
  esac
done

case "$ACTION" in plan|apply) ;; *) printf 'error: unknown action %s\nhelp: harden.sh [plan|apply]\n' "$ACTION" >&2; exit 2 ;; esac

plan_sshd() {
  cat <<EOF
mend sshd[3]{what,now,after}:
  "PasswordAuthentication","(compiled default: yes)","no"
  "KbdInteractiveAuthentication","no (arch drop-in)","no"
  "PermitRootLogin","prohibit-password (default)","prohibit-password"
revert[1]{file,line}:
  "/etc/ssh/sshd_config.d/10-ymir-ward.conf","backed up to ${SSHD_DROPIN}.bak-${STAMP}; or delete the drop-in and: systemctl reload sshd"
EOF
}

plan_ufw() {
  cat <<EOF
mend ufw[4]{rule,now,after}:
  "ssh","--dport 22 -j ACCEPT (any source)","-s 192.0.2.0/24 + in on tailscale0"
  "the gate","--dport 3889 -j ACCEPT (any source)","in on tailscale0 + the Cloudflare tunnel only"
  "the rail","--dport 8080 -s 192.0.2.0/24 and in on tailscale0","unchanged — already narrow"
  "LocalSend","--dport 53317 (any source)","unchanged — a deliberate transfer port; say so here"
commands[4]{run,why}:
  "sudo ufw allow from 192.0.2.0/24 to any port 22 proto tcp","the LAN road stays"
  "sudo ufw allow in on tailscale0 to any port 22 proto tcp","the tailnet road — the one that always works"
  "sudo ufw delete allow 22/tcp","remove the world's door (do this only after the two above answer)"
  "sudo ufw allow in on tailscale0 to any port 3889 proto tcp && sudo ufw delete allow 3889/tcp","the gate: tailnet + the tunnel, not the world"
verify[1]{how}:
  "from another machine: ssh user@<lan-ip> and ssh user@<tailnet-name> — BOTH must answer before the delete line is run"
EOF
}

plan_keys() {
  printf 'mend keys[2]{what,after}:\n'
  printf '  "plaintext secrets and the vault key in %s/hodd/secrets","mode 600"\n' "${HOME_DIR:-<home>}"
  printf '  "the .bak copies of the encrypted env","mode 600"\n'
}

case "$ACTION" in
  plan)
    printf 'warden-plan[4]{mend,detail}:\n  "sshd","keys-only login"\n  "secrets","mode 600 at rest"\n  "ufw","narrow 22 and 3889 to the LAN + the tailnet"\n  "further","fail2ban or CrowdSec, a file-integrity baseline, a vulnerability scan (plan 81 S2-S5)"\n'
    plan_sshd; plan_keys; plan_ufw
    exit 0 ;;
esac

# ── apply --ssh-keys-perm (safe, local, reversible by chmod) ───────────────────
if [ "$DO_KEYS" = 1 ]; then
  [ -n "$HOME_DIR" ] || { printf 'error: cannot resolve the home\nhelp: bin/ward/harden.sh plan\n' >&2; exit 1; }
  n=0
  while IFS= read -r f; do
    case "$(basename "$f")" in .*|*.age|*.pub|*.example) continue ;; esac
    mode="$(stat -c '%a' "$f" 2>/dev/null || echo '?')"
    [ "$mode" = "600" ] && continue
    chmod 600 "$f" && n=$((n+1))
  done < <(find "$HOME_DIR/hodd/secrets" -maxdepth 1 -type f 2>/dev/null)
  printf 'harden[1]{mend,changed}:\n  "secrets at rest -> 600",%s\n' "$n"
fi

# ── apply --sshd (needs root; validates before it keeps it) ───────────────────
if [ "$DO_SSHD" = 1 ]; then
  [ "$(id -u)" = 0 ] || { printf 'error: the sshd drop-in needs root\nhelp: sudo bin/ward/harden.sh apply --sshd\n' >&2; exit 1; }
  keys="$(grep -c '^ssh-' "$HOME/.ssh/authorized_keys" 2>/dev/null || echo 0)"
  [ "$keys" -gt 0 ] || { printf 'error: no ssh key is authorized — turning passwords off would lock you out\nhelp: seat a key first (bin/host/heimdall-ensure.sh)\n' >&2; exit 1; }
  mkdir -p "$(dirname "$SSHD_DROPIN")"
  [ -e "$SSHD_DROPIN" ] && cp -a "$SSHD_DROPIN" "$SSHD_DROPIN.bak-$STAMP"
  cat >"$SSHD_DROPIN" <<'CONF'
# Written by the warden (bin/ward/harden.sh apply --sshd). Keys only: a password that
# can cross the network is a password that can be guessed at leisure.
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
CONF
  if ! sshd -t 2>/tmp/ward-sshd-check; then
    rm -f "$SSHD_DROPIN"
    printf 'harden[1]{mend,result,reason}:\n  "sshd keys-only","ROLLED BACK","%s"\n' "$(head -1 /tmp/ward-sshd-check)"
    exit 1
  fi
  systemctl reload sshd 2>/dev/null || systemctl restart sshd 2>/dev/null || true
  if sshd -T | grep -qi '^passwordauthentication yes'; then
    printf 'harden[1]{mend,result,reason}:\n  "sshd keys-only","NOT APPLIED","sshd still reports passwords enabled — check for another drop-in that overrides this one"\n'
    exit 1
  fi
  printf 'harden[1]{mend,result,dropin}:\n  "sshd keys-only","applied and verified","%s"\n' "$SSHD_DROPIN"
fi

# ── apply --ufw (refused without the loud flag) ───────────────────────────────
if [ "$DO_UFW" = 1 ]; then
  if [ "$FORCE" != 1 ]; then
    printf 'harden[1]{mend,result,reason}:\n  "narrow ufw","REFUSED","the box travels: this is the Allfather'"'"'s decision, and the tailnet road must be proven first"\nhelp: bin/ward/harden.sh plan && then, deliberately: sudo bin/ward/harden.sh apply --ufw --i-will-not-travel-blind\n' >&2
    exit 3
  fi
  [ "$(id -u)" = 0 ] || { printf 'error: ufw needs root\nhelp: sudo bin/ward/harden.sh apply --ufw --i-will-not-travel-blind\n' >&2; exit 1; }
  ufw allow from 192.0.2.0/24 to any port 22 proto tcp
  ufw allow in on tailscale0 to any port 22 proto tcp
  ufw deny 22/tcp
  ufw allow in on tailscale0 to any port 3889 proto tcp
  ufw deny 3889/tcp
  ufw status verbose | head -12
  printf 'harden[1]{mend,result}:\n  "narrow ufw","applied — prove BOTH roads before you travel"\n'
fi

exit 0
