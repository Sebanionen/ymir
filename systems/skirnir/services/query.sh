#!/usr/bin/env bash
# query.sh — the ONLY way Skírnir reads his database: three fixed queries, grants enforced, audited.
#
#   bin/assistant/query.sh --tier owner --who "a person's name"
#   bin/assistant/query.sh --tier stranger --search "OVK"
#   bin/assistant/query.sh --tier owner --fact what-opti-cat-is
#
# No SQL is accepted. The door decides, from grants.yaml, whether that tier may read that class, and
# writes a row to read_audit — including the refusals.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo root, found by walking up to the tree that holds .pi and RULES — never counted in
# "../", because this shelf was moved once (bin/assistant/ -> systems/skirnir/, plan 149) and
# 25 scripts kept the old depth, so every $ROOT/bin/... pointed into systems/ instead (2026-11-02).
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)"
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
ymir_home_root HOME_R 2>/dev/null || true
TIER=owner; MODE=""; ARG=""; CHANNEL=console
while [ $# -gt 0 ]; do
  case "$1" in
    --tier) TIER="${2:-stranger}"; shift 2 ;;
    --channel) CHANNEL="${2:-console}"; shift 2 ;;
    --who) MODE=who; ARG="${2:-}"; shift 2 ;;
    --search) MODE=search; ARG="${2:-}"; shift 2 ;;
    --fact) MODE=fact; ARG="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$MODE" ] || { printf 'usage: query.sh --tier T (--who NAME | --search TEXT | --fact SLUG)\n' >&2; exit 2; }
TIER="$TIER" MODE="$MODE" ARG="$ARG" CHANNEL="$CHANNEL" STATE="$HOME_R/hodd/state/assistant"
IDENTITY="$HOME_R/hodd/identity/assistant" python3 - <<'PY'
import json, os, re, sqlite3, time, yaml
state = os.environ["STATE"]
db = os.path.join(state, "kb.db")
grants = yaml.safe_load(open(os.path.join(os.environ.get("IDENTITY", state), "grants.yaml"))) or {}
allowed = {k: set(v or []) for k, v in (grants.get("classes") or {}).items()}
tier, mode, arg, channel = os.environ["TIER"], os.environ["MODE"], os.environ["ARG"], os.environ["CHANNEL"]
con = sqlite3.connect(db)
if mode == "who":
    rows = con.execute("SELECT slug,class,claim,parties FROM facts WHERE class='contacts' AND lower(claim) LIKE ?",
                       (f"{arg.lower()}%",)).fetchall()
elif mode == "fact":
    rows = con.execute("SELECT slug,class,claim,parties FROM facts WHERE slug=?", (arg,)).fetchall()
else:
    rows = con.execute("SELECT slug,class,claim,parties FROM facts WHERE lower(claim) LIKE ?",
                       (f"%{arg.lower()}%",)).fetchall()

out = []
for slug, klass, claim, parties in rows:
    if "group" in channel and klass in ("nda", "contracted", "restricted"):
        continue
    if tier not in allowed.get(klass, set()):
        continue
    out.append({"slug": slug, "class": klass, "claim": claim})

con.execute("INSERT INTO read_audit VALUES (?,?,?,?,?)",
            (time.strftime("%Y-%m-%dT%H:%M:%S%z"), tier, channel, f"{mode}:{arg}", len(out)))
con.commit(); con.close()
print(f'query[1]{{tier,mode,class_allowed,hits}}:"{tier}","{mode}","{",".join(sorted(allowed))}","{len(out)}"')
for row in out:
    print(f'  "{row["class"]}","{row["claim"]}"')
PY
