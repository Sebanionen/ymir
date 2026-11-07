#!/usr/bin/env bash
# nornir-job-gna-mail.sh — the desk's own clock: import, then prove the desk answers.
#
#   nornir-job-gna-mail.sh [import]      the scheduled act (default)
#   nornir-job-gna-mail.sh --check       health only, no import (for a gate or a hand)
#   nornir-job-gna-mail.sh --dry-run     read the mailbox, write nothing, print the counts
#
# GNA_DAYS sets the window (default 2: a daily overlap catches late delivery
# without re-reading a week of mail on every row).
#
# A Nornir job starts, does one thing, writes its record and exits. It never owns
# state. The one law it carries: ABSENCE IS A FAILURE, NOT AN EMPTY LIST — an
# unreadable mailbox or a desk that does not answer is reported as such, in Runes
# and on stdout, and never rendered as "no mail".
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
ymir_home_root HOME_R 2>/dev/null || true
MAIL_DIR="$HOME_R/hodd/memory/mail"
STATE="${BROKK_MACHINE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/ymir}"
DESK_URL="${GNA_DESK_URL:-http://127.0.0.1:8494}"
TOKEN_FILE="$HOME_R/hodd/state/gna-desk.token"
RUNES="$ROOT/bin/records/runes-append.sh"

MODE="${1:-import}"
DAYS="${GNA_DAYS:-2}"

say() { printf 'gna-mail[%s] %s\n' "$MODE" "$*"; }

# One resolver, no guessed home (Rule 07): hoard-lib owns the record and the one
# documented default. If it cannot name the home, this job refuses — a job that
# invents a path writes to a store nobody reads.
if [ -z "${HOME_R:-}" ]; then
  say "FAIL the home is unresolved (bin/vault/hoard-lib.sh) — refusing to guess a path"
  exit 3
fi

accounts() {
  python3 - "$MAIL_DIR/accounts.yaml" <<'PY' 2>/dev/null
import sys, yaml
try:
    rows = (yaml.safe_load(open(sys.argv[1])) or {}).get("accounts") or []
except Exception:
    sys.exit(0)
for row in rows:
    if isinstance(row, dict) and row.get("id"):
        print(row["id"])
PY
}

addresses() {
  # The register of addresses the house uses (plan 116 §15.3.1). A desk that reads an
  # inbox nobody can mail is an empty page with a confident face: this line says so
  # every round, and NEVER fails the import — an undeliverable inbound address is a
  # DNS/console fault, not a reason to stop reading the mail that does arrive.
  local out rc
  [ -x "$ROOT/bin/mail/addresses.sh" ] || return 0
  out="$("$ROOT/bin/mail/addresses.sh" --check 2>&1)"; rc=$?
  case "$rc" in
    0) return 0 ;;
    1) say "WARN an address the house uses cannot receive (addresses.sh --check rc=1):"
       printf '%s\n' "$out" | sed -n 's/^  undeliverable  /       undeliverable  /p; s/^  unmeasured     /       unmeasured     /p' ;;
    3) say "WARN no address is PROVEN deliverable yet (addresses.sh --check rc=3 — declared, never assumed):"
       printf '%s\n' "$out" | sed -n 's/^  unproven       /       unproven       /p' ;;
    *) say "WARN the address register could not be read (addresses.sh --check rc=$rc)"
       printf '%s\n' "$out" | tail -2 ;;
  esac
  printf '%s gna-mail WARN addresses rc=%s\n' "$(date -Is)" "$rc" >> "${STATE:-/tmp}/gna-mail.log" 2>/dev/null || true
  return 0
}

health() {
  local token out
  token="$(cat "$TOKEN_FILE" 2>/dev/null || true)"
  [ -n "$token" ] || { say 'FAIL the desk has no token — run: bash bin/mail/install.sh'; return 2; }
  out="$(curl -fsS -m 5 -H "Authorization: Bearer $token" "$DESK_URL/health" 2>/dev/null)" || {
    say "FAIL the desk did not answer at $DESK_URL — the gate will say so too"
    return 2
  }
  say "desk ${out}"
  return 0
}

if [ "$MODE" = "--check" ]; then
  addresses
  health; exit $?
fi

if [ ! -f "$MAIL_DIR/accounts.yaml" ]; then
  say "FAIL no scope file at $MAIL_DIR/accounts.yaml — the desk is unconfigured, not idle"
  mkdir -p "$STATE"
  printf '%s gna-mail FAIL no-scope-file\n' "$(date -Is)" >> "$STATE/gna-mail.log"
  exit 3
fi

ACCOUNTS="$(accounts)"
if [ -z "$ACCOUNTS" ]; then
  say "FAIL accounts.yaml holds no usable row — unreadable is not empty"
  mkdir -p "$STATE"
  printf '%s gna-mail FAIL no-accounts\n' "$(date -Is)" >> "$STATE/gna-mail.log"
  exit 3
fi

DRY=""
[ "$MODE" = "--dry-run" ] && DRY="--dry-run"

rc_total=0
while IFS= read -r account; do
  [ -n "$account" ] || continue
  out="$(python3 "$ROOT/bin/mail/gna_import.py" --account "$account" --days "$DAYS" $DRY 2>&1)"
  rc=$?
  printf '%s\n' "$out"
  if [ $rc -ne 0 ]; then
    say "FAIL import failed for one account (rc=$rc) — reported, never rendered as an empty inbox"
    rc_total=$rc
  fi
done <<< "$ACCOUNTS"

mkdir -p "$STATE"
printf '%s gna-mail rc=%s\n' "$(date -Is)" "$rc_total" >> "$STATE/gna-mail.log"
# Freshness the gate can show: a last RUN, not only a last write — an unchanged
# store is a success and must not read as "the desk stopped working".
if [ -d "$HOME_R/hodd/state" ]; then
  printf '{"at":"%s","days":%s,"rc":%s}\n' "$(date -Is)" "$DAYS" "$rc_total" \
    > "$HOME_R/hodd/state/gna-mail-last-run.json"
fi

if [ -x "$RUNES" ]; then
  "$RUNES" gna gna-mail-import --message "mail desk import: rc=$rc_total · accounts=$(printf '%s' "$ACCOUNTS" | wc -l)" >/dev/null 2>&1 || true

# AS THEY COME (2026-11-05, plan 193): a successful import tells the arm about arrivals it has
# not spoken about before. gna_notify marks each message `notified_at` by appending a version,
# batches the line (the arm has a flood brake), and refuses silently when it cannot speak.
if [ "$rc_total" -eq 0 ] && [ "$MODE" != "import" ]; then :; fi
if [ "$rc_total" -eq 0 ] && [ -x "$ROOT/bin/mail/gna_notify.py" ]; then
  if out="$("$ROOT/bin/mail/gna_notify.py" --nudge 2>&1)"; then
    printf '%s\n' "$out" | sed 's/^/gna-mail[notify] /'
  else
    say "WARN the arm could not be told about new mail: $(printf '%s' "$out" | head -1)"
    "$RUNES" gna gna-mail-notify --message "notify failed: $(printf '%s' "$out" | head -1 | cut -c1-160)" >/dev/null 2>&1 || true
  fi
fi
fi

addresses
health || rc_total=2
exit $rc_total
