#!/usr/bin/env bash
# escalate.sh — when Skírnir wonders, he asks the Allfather where the Allfather actually is.
#
#   systems/skirnir/services/escalate.sh --tier owner --text "the question he could not answer"
#
# Two roads, both taken: a message in his PRIVATE chat with the assistant's own bot (so he can simply
# reply, and the reply is a normal turn), and Hófvarpnir at HIGH (desktop + pocket) so a closed
# Telegram does not swallow it.
#
# Rate limited like everything else: three an hour, and the suppression is written down.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo root, found by walking up to the tree that holds .pi and RULES — never counted in
# "../", because this shelf was moved once (bin/assistant/ -> systems/skirnir/, plan 149) and
# 25 scripts kept the old depth, so every $ROOT/bin/... pointed into systems/ instead (2026-11-02).
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)"
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
ymir_home_root HOME_R 2>/dev/null || true
[ -n "${HOME_R:-}" ] || exit 0
TIER=""; TEXT=""; CHAT=""; WHO=""; CONTEXT=""; REASON=""; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tier) TIER="${2:-unknown}"; shift 2 ;;
    --text) TEXT="${2:-}"; shift 2 ;;
    --chat) CHAT="${2:-}"; shift 2 ;;
    --who) WHO="${2:-}"; shift 2 ;;
    --context) CONTEXT="${2:-}"; shift 2 ;;
    --reason) REASON="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) shift ;;
  esac
done
[ -n "$TEXT" ] || exit 2

# the warm part: what was said just before, so the handoff is a conversation and not a ping.
# A context the CALLER already gathered WINS — it is the asker's own answer, not a transcript of
# the bot's own refusals.
if [ -z "${CONTEXT:-}" ]; then
CONTEXT="$(CHAT_Q="$CHAT" python3 - <<'PY'
import os, sqlite3
chat = os.environ.get("CHAT_Q") or ""
state = os.path.join(os.path.expanduser("~"), "Documents", "ymirhome", "hodd", "state", "assistant")
try:
    con = sqlite3.connect(os.path.join(state, "assistant.db"))
    rows = con.execute("SELECT text FROM turns WHERE chat=? AND role='user' "
                       "ORDER BY rowid DESC LIMIT 2", (chat,)).fetchall()
except Exception:
    rows = []
print(" | ".join(str(r[0])[:160] for r in reversed(rows)))
PY
)"
fi
DRAFT="I don't have that yet — I'll ask him and come back to you."
FULL="${TEXT}"
[ -n "$CONTEXT" ] && FULL="${FULL} — recent: ${CONTEXT}"
[ -n "$CONTEXT" ] && FULL="${FULL} — suggested reply: ${DRAFT}"

# one DM, through the assistant's own bot
STATE="$HOME_R/hodd/state/assistant"
mkdir -p "$STATE" 2>/dev/null || true
TOKEN="$(bash "$ROOT/bin/vault/hodd.sh" emit secrets/platform.env 2>/dev/null \
  | sed -n 's/^export SKIRNIR_TELEGRAM_BOT_TOKEN=//p' | tr -d "'")"
OWNER="$(bash "$ROOT/bin/vault/hodd.sh" emit secrets/platform.env 2>/dev/null \
  | sed -n 's/^export TELEGRAM_OWNER_ID=//p' | tr -d "'")"
# A handoff that cannot be delivered must SAY so: the caller promises the Allfather "he will come back
# to you", and that promise is a lie if every road failed. Exit 0 only when at least one road carried it.
SENT=0
if [ -n "$TOKEN" ] && [ -n "$OWNER" ]; then
  # a dry run never records: it exists to PREVIEW, and an ask recorded by a preview is a false waiting
if [ "$DRY" -eq 1 ]; then
  printf 'escalate: DRY — would record the ask and send:\n  %s\n' "${WHO:-someone}" >&2
  exit 0
fi

# the ask is a RECORD first, so an answer can find its way back to the person who asked
ASK_ID="$(bash "$ROOT/systems/skirnir/services/asks.sh" add --who "${WHO:-someone}" --chat "$CHAT" \
  --channel "${CHANNEL:-telegram-dm}" --question "$TEXT" --context "${CONTEXT:-}" 2>/dev/null)"
MSG="Allfather — ${WHO:-someone} asks (${TIER}, chat ${CHAT:-unknown}): “${TEXT:0:400}”. ${CONTEXT:+They said: ${CONTEXT:0:350}. }${REASON:+I could not answer it: ${REASON:0:120}. }
Suggested reply (edit it or ignore it): “${DRAFT}”
To send your own answer: tell me “tell ${WHO:-them}: …” — I will deliver it and close the ask.${ASK_ID:+ [${ASK_ID}]}"
  if [ "$DRY" -eq 1 ]; then
    printf 'escalate: DRY — would send:\n  %s\n' "$MSG" >&2
    exit 0
  fi
  RESP="$(curl -s -m 10 "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${OWNER}" \
    --data-urlencode "text=${MSG}" \
    -d "disable_web_page_preview=true" 2>/dev/null || true)"
  case "$RESP" in *'"ok":true'*) SENT=1 ;; *) printf 'escalate: telegram road failed\n' >&2 ;; esac
else
  printf 'escalate: no bot token or owner id in the vault\n' >&2
fi

# and the hotline, so it is not only on one road
if [ -x "$ROOT/bin/notify/send.sh" ]; then
  if bash "$ROOT/bin/notify/send.sh" --source assistant --severity HIGH \
       --message "Skírnir wonders — ${WHO:-someone} (${TIER}): ${TEXT:0:140}" \
       --key "assistant-ask:$(printf '%s' "$TEXT" | sha256sum | cut -c1-12)" >/dev/null 2>&1; then
    SENT=1
  fi
fi

if [ "$SENT" -eq 1 ]; then
  printf 'escalate: delivered (%s)\n' "${TIER}" >&2
  exit 0
fi
printf 'escalate: NOT delivered — every road failed\n' >&2
exit 1
