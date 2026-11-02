#!/usr/bin/env bash
# ban.sh — refuse a chat outright, and write down why.
#   bin/assistant/ban.sh <chat-id> --why "reason"
#   bin/assistant/ban.sh --list
#   bin/assistant/ban.sh --unban <chat-id>
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo root, found by walking up to the tree that holds .pi and RULES — never counted in
# "../", because this shelf was moved once (bin/assistant/ -> systems/skirnir/, plan 149) and
# 25 scripts kept the old depth, so every $ROOT/bin/... pointed into systems/ instead (2026-11-02).
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)"
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
ymir_home_root HOME_R 2>/dev/null || true
F="$HOME_R/hodd/identity/assistant/banned.yaml"
[ -f "$F" ] || printf 'banned: []\n' > "$F"
case "${1:-}" in
  --list) sed -n 's/^- //p' "$F" ;;
  --unban) ID="${2:-}"; [ -n "$ID" ] || exit 2
    ID="$ID" F="$F" python3 - <<'PY'
import os, yaml, pathlib
p = pathlib.Path(os.environ["F"]); d = yaml.safe_load(p.read_text()) or {}
d["banned"] = [x for x in (d.get("banned") or []) if str(x) != os.environ["ID"]]
p.write_text(yaml.safe_dump(d, sort_keys=False))
print("unbanned", os.environ["ID"])
PY
    ;;
  ""|-h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) ID="$1"; shift; WHY=""
    [ "${1:-}" = "--why" ] && WHY="${2:-}"
    ID="$ID" WHY="$WHY" F="$F" python3 - <<'PY'
import os, yaml, pathlib, time
p = pathlib.Path(os.environ["F"]); d = yaml.safe_load(p.read_text()) or {}
rows = [str(x) for x in (d.get("banned") or [])]
if os.environ["ID"] not in rows:
    rows.append(os.environ["ID"])
d["banned"] = rows
d.setdefault("reasons", {})[os.environ["ID"]] = {"why": os.environ["WHY"],
                                                 "at": time.strftime("%Y-%m-%dT%H:%M:%S%z")}
p.write_text(yaml.safe_dump(d, sort_keys=False, allow_unicode=True))
print(f"banned {os.environ['ID']}: {os.environ['WHY'] or '(no reason given)'}")
PY
    ;;
esac
