#!/usr/bin/env bash
# mail.sh — the operator-only mail door: a system tells the Allfather, and nobody else.
#
# WHY (the Allfather, 2026-11-06): *"he can also email me then he have merged or if he have
# questions about the merge."* The house already has a letter door
# (`systems/snotra/services/letters/mail-send.sh`) and it is RIGHT to demand an approval before
# it sends — a letter to a stranger is correspondence and it costs the operator his name. A
# notification to the operator himself is not correspondence, so it gets its own door instead of
# a weakened one.
#
# THE ONE LAW OF THIS DOOR: the recipient is the operator's own address, read from
# `hodd/identity/operator.yaml`. Any other recipient is a REFUSAL that names the rule — a
# notification door that could address anyone is a send path without an approval, which is the
# exact capability `mail-send.sh` exists to withhold.
#
# It carries no vault content and no secret (RULES/15), and it says so out loud when it cannot
# send: a FAIL line and a non-zero exit, never silence. Silence is how the mail desk was blind
# for a night (hodd/docs/diagnostics/2026-11-05-why-the-mail-door-was-blind.md).
#
# Usage:
#   mail.sh --kind merged|ask --subject "…" --body FILE [--ref <path-or-url>] [--dry-run] [--json]
#   mail.sh --kind merged --subject "…" --body-text "one paragraph"
#   mail.sh --status                 # is the Google grant usable on THIS seat?
#   mail.sh --address                # the operator's address this door will use
#
# Endpoints are configuration, never constants (Rule 07):
#   YMIR_GMAIL_API_BASE  default https://gmail.googleapis.com/gmail/v1
#   YMIR_OAUTH_TOKEN_URL default https://oauth2.googleapis.com/token
#
# Exit: 0 sent (or deliberately not sent on --dry-run) · 1 could not send (named) · 2 usage · 3 refused.
set -u
VERSION="1.0.0"

case "${1-}" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help|"") sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"

if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  for _c in "$ROOT/bin/vault/hoard-lib.sh" "$SCRIPT_DIR/../vault/hoard-lib.sh"; do
    [ -r "$_c" ] && { . "$_c"; YMIR_HOARD_LIB_LOADED=1; break; }
  done
  unset _c
fi
HOME_DIR=""; ymir_home_root HOME_DIR 2>/dev/null || true
[ -n "$HOME_DIR" ] || { printf 'mail: the home is unresolved — bin/vault/hoard-lib.sh names it\n' >&2; exit 1; }

die()    { printf 'mail: %s\n' "$*" >&2; exit 1; }
usage()  { printf 'mail: %s\n' "$*" >&2; exit 2; }
refuse() { printf 'mail: REFUSED — %s\n' "$*" >&2; exit 3; }

OPERATOR_YAML="$HOME_DIR/hodd/identity/operator.yaml"
SECRETS="$HOME_DIR/hodd/secrets"
operator_address() {
  [ -r "$OPERATOR_YAML" ] || return 1
  sed -n 's/^email:[[:space:]]*//p' "$OPERATOR_YAML" | head -1 | tr -d '"'"'" | tr -d ' '
}
vault_get() {  # <KEY>
  local key=$1 val
  # The vault door first (it decides how to decrypt); a plaintext fallback never wins over it.
  val="$(bash "$ROOT/bin/vault/hodd.sh" emit secrets/platform.env 2>/dev/null | sed -n "s/^export $key=//p" | head -1 | sed "s/^['\"]//; s/['\"]$//")"
  [ -n "$val" ] || val="$(sed -n "s/^$key=//p" "$SECRETS/platform.env" 2>/dev/null | head -1 | sed "s/^['\"]//; s/['\"]$//")"
  printf '%s' "$val"
}

KIND=""; SUBJECT=""; BODY_FILE=""; BODY_TEXT=""; REF=""; DRY=0; JSON=0
while [ $# -gt 0 ]; do case "$1" in
  --kind) KIND="${2:-}"; shift 2 ;;
  --kind=*) KIND="${1#--kind=}"; shift ;;
  --subject) SUBJECT="${2:-}"; shift 2 ;;
  --subject=*) SUBJECT="${1#--subject=}"; shift ;;
  --body) BODY_FILE="${2:-}"; shift 2 ;;
  --body=*) BODY_FILE="${1#--body=}"; shift ;;
  --body-text) BODY_TEXT="${2:-}"; shift 2 ;;
  --ref) REF="${2:-}"; shift 2 ;;
  --ref=*) REF="${1#--ref=}"; shift ;;
  --dry-run) DRY=1; shift ;;
  --json) JSON=1; shift ;;
  --status) KIND=__status; shift ;;
  --address) KIND=__address; shift ;;
  *) usage "unknown argument $1" ;;
esac; done

ADDR="$(operator_address || true)"

case "$KIND" in
  __address)
    [ -n "$ADDR" ] || die "no operator address: hodd/identity/operator.yaml carries no email: row"
    printf 'address[1]{to}:\n  "%s"\n' "$ADDR"; exit 0 ;;
  __status)
    local_cid="$(vault_get GOOGLE_MCP_CLIENT_ID)"
    local_sec="$(vault_get GOOGLE_MCP_CLIENT_SECRET)"
    local_rt="$(vault_get SNOTRA_GOOGLE_REFRESH_TOKEN)"
    state="ready"
    why=""
    [ -n "$local_cid" ] && [ -n "$local_sec" ] && [ -n "$local_rt" ] || { state="no grant"; why="a Google key is absent from the vault on this seat"; }
    if [ "$state" = ready ]; then
      tok="$(curl -sS -m 20 -X POST "${YMIR_OAUTH_TOKEN_URL:-https://oauth2.googleapis.com/token}" \
             -d "client_id=$local_cid" -d "client_secret=$local_sec" \
             -d "refresh_token=$local_rt" -d "grant_type=refresh_token" 2>/dev/null \
             | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("access_token",""))
except Exception: print("")' 2>/dev/null)"
      [ -n "$tok" ] || { state="grant refused"; why="the refresh token did not mint an access token"; }
    fi
    printf 'mail[3]{to,state,why}:\n  "%s","%s","%s"\n' "${ADDR:-none}" "$state" "${why:-the grant mints a token}"
    [ "$state" = ready ] && exit 0 || exit 1 ;;
esac

case "$KIND" in
  merged|ask) ;;
  "") usage "a kind is required: --kind merged|ask" ;;
  *) usage "unknown kind '$KIND' — merged | ask" ;;
esac

[ -n "$ADDR" ] || die "no operator address: hodd/identity/operator.yaml carries no email: row, so there is nobody this door may address"
[ -n "$SUBJECT" ] || usage "--subject is required"
if [ -z "$BODY_FILE" ] && [ -z "$BODY_TEXT" ]; then usage "a body is required: --body FILE or --body-text \"…\""; fi
if [ -n "$BODY_FILE" ]; then [ -r "$BODY_FILE" ] || die "the body file $BODY_FILE is not readable"; fi

# ── the ward: no secret, no vault content, no address of the house (RULES/15, RULES/39) ──────
BODY="$(if [ -n "$BODY_FILE" ]; then cat "$BODY_FILE"; else printf '%s' "$BODY_TEXT"; fi)"
if printf '%s' "$BODY" | grep -qE '(ghp_|github_pat_|sk-[A-Za-z0-9]{16,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|password[=:]|token[=:])'; then
  refuse "the body looks like it carries a credential — this door may not move a secret, not even to the operator (RULES/15)"
fi
if printf '%s' "$BODY" | grep -qE '[0-9]{1,3}(\.[0-9]{1,3}){3}'; then
  refuse "the body carries what looks like an IP address — the house does not hand out its addresses, not even to him by machine (RULES/39); name the door instead"
fi

CID="$(vault_get GOOGLE_MCP_CLIENT_ID)"; CSEC="$(vault_get GOOGLE_MCP_CLIENT_SECRET)"; RT="$(vault_get SNOTRA_GOOGLE_REFRESH_TOKEN)"
if [ -z "$CID" ] || [ -z "$CSEC" ] || [ -z "$RT" ]; then
  printf 'mail: FAIL — the Google grant is not readable on this seat (vault unreadable or a key absent); nothing was sent\n' >&2
  printf 'mail[2]{to,state}:\n  "%s","not sent"\n' "$ADDR"
  exit 1
fi

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STAMP="$(date -u +%Y-%m-%d)"
SUBJECT_LINE="[ymir] $KIND · $SUBJECT"
FOOTER="—
Sent by bin/notify/mail.sh at $TS from $(hostname -s 2>/dev/null || echo a seat).
This door may only address the operator. A merge record, a question, or nothing at all."

PAYLOAD_FILE="$(mktemp)"
trap 'rm -f "$PAYLOAD_FILE"' EXIT
python3 - "$ADDR" "$SUBJECT_LINE" "$BODY" "$FOOTER" "$REF" "$PAYLOAD_FILE" <<'PY' || die "the message could not be built"
import base64, json, sys
from email.message import EmailMessage
to, subject, body, footer, ref, out = sys.argv[1:7]
msg = EmailMessage()
msg["To"] = to
msg["Subject"] = subject
msg["X-Ymir-Source"] = "reviewer"
if ref:
    msg["X-Ymir-Ref"] = ref
text = body + ("\n\nReference: " + ref if ref else "") + "\n\n" + footer + "\n"
msg.set_content(text)
raw = base64.urlsafe_b64encode(bytes(msg)).decode()
json.dump({"message": {"raw": raw}}, open(out, "w"))
PY

if [ "$DRY" = 1 ]; then
  printf 'mail[3]{to,kind,state}:\n  "%s","%s","dry-run — nothing sent"\n' "$ADDR" "$KIND"
  exit 0
fi

TOKEN="$(curl -sS -m 20 -X POST "${YMIR_OAUTH_TOKEN_URL:-https://oauth2.googleapis.com/token}" \
          -d "client_id=$CID" -d "client_secret=$CSEC" -d "refresh_token=$RT" \
          -d "grant_type=refresh_token" 2>/dev/null \
          | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("access_token",""))
except Exception: print("")' 2>/dev/null)"
if [ -z "$TOKEN" ]; then
  printf 'mail: FAIL — the refresh token did not mint an access token; nothing was sent\n' >&2
  printf 'mail[2]{to,state}:\n  "%s","not sent"\n' "$ADDR"
  exit 1
fi

RESP="$(curl -sS -m 60 -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
         --data-binary "@$PAYLOAD_FILE" -w '\n%{http_code}' \
         "${YMIR_GMAIL_API_BASE:-https://gmail.googleapis.com/gmail/v1}/users/me/messages/send" 2>/dev/null)"
CODE="$(printf '%s' "$RESP" | tail -1)"
BODYJSON="$(printf '%s' "$RESP" | sed '$d')"
ID="$(printf '%s' "$BODYJSON" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("id",""))
except Exception: print("")' 2>/dev/null)"
if [ "$CODE" = "200" ] || [ "$CODE" = "202" ]; then
  if [ "$JSON" = 1 ]; then
    printf '{"to":"%s","kind":"%s","id":"%s","state":"sent"}\n' "$ADDR" "$KIND" "$ID"
  else
    printf 'mail[4]{to,kind,id,state}:\n  "%s","%s","%s","sent"\n' "$ADDR" "$KIND" "${ID:-?}"
  fi
  exit 0
fi
printf 'mail: FAIL — Gmail answered %s; nothing was sent\n' "${CODE:-no answer}" >&2
printf '%s\n' "$BODYJSON" | head -3 >&2
printf 'mail[2]{to,state}:\n  "%s","not sent"\n' "$ADDR"
exit 1
