#!/usr/bin/env bash
# learn.sh — a fact learned in conversation, waiting for the Allfather's approval.
#
#   bin/assistant/learn.sh --tier owner --chat 123 --fact "Andre prefers email on weekdays"
#
# Nothing a stranger says becomes knowledge by being said: the fact lands in `pending/` with its
# provenance, and a notification asks the Allfather to approve it. Approving runs `approve-fact.sh`,
# which moves it to `approved/` and rebuilds the digest.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo root, found by walking up to the tree that holds .pi and RULES — never counted in
# "../", because this shelf was moved once (bin/assistant/ -> systems/skirnir/, plan 149) and
# 25 scripts kept the old depth, so every $ROOT/bin/... pointed into systems/ instead (2026-11-02).
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)"
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
ymir_home_root HOME_R 2>/dev/null || true
S="$HOME_R/hodd/identity/assistant"
R="$HOME_R/hodd/state/assistant"
TIER=""; CHAT=""; FACT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tier) TIER="${2:-}"; shift 2 ;;
    --chat) CHAT="${2:-}"; shift 2 ;;
    --fact) FACT="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$FACT" ] || { printf 'usage: learn.sh --tier owner --chat ID --fact "…"\n' >&2; exit 2; }
SLUG="learned-$(printf '%s' "$FACT" | sha256sum | cut -c1-10)"
mkdir -p "$S/pending" "$S/approved" "$R"
cat > "$S/pending/$SLUG.md" <<DOC
---
approved_by: (pending)
approved_at: ""
class: public
learned_from: ${TIER:-unknown}
learned_in: ${CHAT:-unknown}
learned_at: $(date -Iseconds)
---
$FACT
DOC
DOOR="$ROOT/bin/notify/send.sh"
[ -x "$DOOR" ] && bash "$DOOR" --source assistant --severity MEDIUM --ask \
  --key "learn:$SLUG" --message "Skírnir learned: “${FACT:0:120}”. Approve it as knowledge?" \
  --exec "$SCRIPT_DIR/approve-fact.sh $SLUG" >/dev/null 2>&1 || true
printf 'learn[1]{slug,state}: "%s","pending your approval"\n' "$SLUG"
