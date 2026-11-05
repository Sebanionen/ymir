#!/usr/bin/env bash
# mimir.sh — the well (Mimirsbrunn). Drink before you act, water it after.
#
# Talks to Kaia's engram bridge (:4602) when it is up; otherwise operates the
# local well log (episodes.jsonl). Galdr-style TOON.
#
# Every write passes the GATE in bin/records/mimir-policy.py: does this change
# future behaviour, is it a commitment with consequences, or is it a decision with
# rationale? If none of the three, it is dropped — and the drop is reported, with
# the reason, never swallowed.
#
# Usage:
#   mimir.sh health
#   mimir.sh memory [--check]                  # the one row Eir reports (well size, last *)
#   mimir.sh recall <query> [--k N] [--mode hybrid|cosine|spreading]
#              [--tag T] [--store episodic|semantic|procedural] [--actor A]
#              [--task T] [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--archived]
#   mimir.sh observe <text> [--tags a,b] [--source S] [--task T] [--store TYPE]
#              [--privacy CLASS] [--retention RULE] [--scope SCOPE] [--confidence F]
#              [--salience F] [--shape behaviour|commitment|decision] [--force]
#   mimir.sh correct <episode-id> <text> [--source S] [--tags a,b]
#   mimir.sh retract <episode-id> [--why "one line"] [--source S]
#   mimir.sh why <episode-id>                  # the correction chain, both ways
#   mimir.sh grade [--apply]                   # continuous forgetting: report, or annotate
#   mimir.sh timeline [--entity X]
#   mimir.sh policy [--self-test]              # prove the gate, types, chain and grading
#   mimir.sh --version
set -u
# The ONE resolver (Rule 07): env -> the recorded choice -> the one default.
if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  for _yc in "${ROOT:-}/bin/vault/hoard-lib.sh" \
             "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/bin/vault/hoard-lib.sh" \
             "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/bin/vault/hoard-lib.sh" \
             "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/hoard-lib.sh"; do
    [ -n "$_yc" ] && [ -r "$_yc" ] && { . "$_yc"; YMIR_HOARD_LIB_LOADED=1; break; }
  done
  unset _yc
fi
if [ -z "${YMIR_HOME:-}" ] && command -v ymir_home_root >/dev/null 2>&1; then
  ymir_home_root YMIR_HOME
fi

VERSION="1.1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"
YMIR_HOME="${YMIR_HOME}"
# The well log lives INSIDE the hoard, which is `$YMIR_HOME/hodd/` (Rule 04) — this
# line omitted the `hodd/` segment, so recall and observe pointed at a path that has
# never existed. Found by the ymirhome door calling it, not by reading it.
# The append log — one resolution with the bridge and the policy (they read
# ENGRAM_LOG, then the store's own `well/` shelf). Two defaults for one log meant a
# session could gate against one file and write to another (found 2026-10-26 by the
# well-policy test, not by reading it).
if [ -n "${ENGRAM_LOG:-}" ]; then WELL="$ENGRAM_LOG"
elif [ -n "${YMIR_MEMORY_DIR:-}" ]; then WELL="$YMIR_MEMORY_DIR/episodes.jsonl"
else WELL="$YMIR_HOME/hodd/memory/well/episodes.jsonl"; fi
BRIDGE="${MIMIRSBRUNN_URL:-http://127.0.0.1:4602}"
# The policy is stdlib-only ON PURPOSE, so the gate still answers when the engine
# cannot be imported and the bridge is down. `python3` is the floor; the bridge's
# own interpreter is the fallback (it is guaranteed to exist where a store does).
POLICY="$SCRIPT_DIR/mimir-policy.py"
PY="${MIMIR_PY:-$(command -v python3 2>/dev/null || true)}"
[ -n "$PY" ] || PY="python3.12"
# The store, resolved the way the bridge resolves it (one well, Rule 04/07).
STORE="${ENGRAM_DB:-$YMIR_HOME/hodd/memory/kaia.engram}"

usage() { sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; }

CMD="${1-}"; shift || true
case "$CMD" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help|"") usage; exit 0 ;;
esac
if [ "${MIMIR_REQUIRE_BRIDGE:-0}" != 1 ]; then
  [ -e "$WELL" ] || { mkdir -p "$(dirname "$WELL")" 2>/dev/null; : >"$WELL" 2>/dev/null; }
fi

bridge_up() {
  command -v curl >/dev/null 2>&1 || return 1
  if [ -n "${MIMIR_EXPECTED_STORE:-}" ]; then
    local health
    health=$(curl -fsS --max-time 2 "$BRIDGE/health" 2>/dev/null) || return 1
    EXPECTED_STORE="$MIMIR_EXPECTED_STORE" "$PY" -c 'import json,os,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("status")=="up" and d.get("store")==os.environ["EXPECTED_STORE"] else 1)' <<<"$health" 2>/dev/null
  else
    curl -fsS --max-time 2 "$BRIDGE/health" >/dev/null 2>&1
  fi
}
well_count() { wc -l <"$WELL" | tr -d ' '; }
urlenc() { "$PY" -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.stdin.read()))'; }

# The gate, offline. When the bridge is up IT decides (it has the store); when it
# is down this decides, against the log — so a keeper can still be told "no".
gate_json() {  # <json request>
  printf '%s' "$1" | "$PY" -c '
import json, sys
req = json.load(sys.stdin)
sys.argv = ["mimir-policy.py", "gate"] + [
    "--content", req["content"],
    "--source", req.get("source") or "brokk",
]
if req.get("tags"): sys.argv += ["--tags", ",".join(req["tags"])]
for key, flag in (("task", "--task"), ("store", "--store-type"), ("shape", "--shape"),
                  ("privacy", "--privacy"), ("retention", "--retention"),
                  ("scope", "--scope")):
    if req.get(key): sys.argv += [flag, str(req[key])]
for key in ("salience", "confidence"):
    if req.get(key) is not None: sys.argv += ["--" + key, str(req[key])]
if req.get("force"): sys.argv += ["--force"]
sys.argv += ["--json"]
import runpy
runpy.run_path(__import__("os").environ["MIMIR_POLICY"], run_name="__main__")
' 2>/dev/null
}

# ── the recall printer: one shape for both doors ─────────────────────────────
_recall_print() {  # <json-or-empty> <localhost|bridge>
  TAG="$TAG" ACTOR="$ACTOR" SINCE="$SINCE" UNTIL="$UNTIL" STORE_TYPE="$STORE_TYPE" \
  TASK="$TASK" ARCHIVED="$ARCHIVED" WHERE="$2" python3 -c "$(cat <<'PYR'
import json, os, sys
well, q, k = sys.argv[1], sys.argv[2], int(sys.argv[3])
payload = sys.stdin.read()
tag, actor = os.environ.get("TAG",""), os.environ.get("ACTOR","")
since, until = os.environ.get("SINCE",""), os.environ.get("UNTIL","")
store_type, archived = os.environ.get("STORE_TYPE",""), os.environ.get("ARCHIVED","0") == "1"
task = (os.environ.get("TASK","") or "").strip().lower().replace(" ", "-")
task = "".join(c for c in task if c.isalnum() or c in "-.").strip("-")

def tags_of(e):
    t = e.get("tags") or []
    return t if isinstance(t, list) else [str(t)]

def keep(e):
    ts = str(e.get("timestamp",""))[:10]
    if since and ts < since: return False
    if until and ts > until: return False
    tg = tags_of(e)
    if tag and not any(tag in (t or "") for t in tg): return False
    if actor and actor not in (e.get("agents") or []) and e.get("source","") != actor: return False
    # A VOID IS NOT FACT. A retracted or superseded episode stays in the record and
    # never comes back from recall — that is the whole point of correcting it. An
    # archived one is read on purpose, never by accident.
    if not archived and any(str(t).startswith("archived:") for t in tg): return False
    if any(str(t).startswith("void:") for t in tg): return False
    if store_type and f"store:{store_type}" not in [str(t) for t in tg]: return False
    if task and f"task:{task}" not in [str(t) for t in tg]: return False
    return True

rows = []
if payload.strip():
    try:
        d = json.loads(payload)
        if isinstance(d, dict) and isinstance(d.get("results"), list):
            rs = d["results"]
        elif isinstance(d, list):
            rs = d
        else:
            raise ValueError("missing results")
    except (ValueError, TypeError):
        print("error: well bridge returned an invalid recall response", file=sys.stderr)
        sys.exit(1)
    for r in rs:
        e = r.get("episode", r)
        if keep(e): rows.append((r.get("score", 0), e))
used_local = not rows
if not rows and os.environ.get("MIMIR_REQUIRE_BRIDGE") != "1":
    # THE BRIDGE'S ANSWER IS NOT THE STORE. An episode written seconds earlier is in
    # the file (grep proves it) and absent from the semantic index, so an empty bridge
    # answer must fall through to the store — otherwise "nothing recorded" and "not
    # indexed yet" become the same lie to a keeper. The fallback ranks by WORD overlap,
    # not by a raw substring: a keeper asks in words, and "well gate questions" must
    # find "the well's gate asks three questions".
    import re
    stop = set("the a an and or of in on at to for with by is are was be it its this that".split())
    words = [w for w in re.findall(r"[a-z0-9][a-z0-9_-]{2,}", q.lower()) if w not in stop]
    scored = []
    for line in open(well, encoding="utf-8", errors="ignore"):
        if not line.strip().startswith("{"): continue
        try: e = json.loads(line)
        except Exception: continue
        if not keep(e): continue
        c = (e.get("content") or "").lower()
        if q.lower() in c:
            scored.append((1.0, e)); continue
        hit = sum(1 for w in words if w in c)
        if hit: scored.append((0.5 * hit / max(1, len(words)), e))
    scored.sort(key=lambda x: x[0])
    rows = scored[-k:]
# Best first, whichever door answered: the bridge ranks descending and the local
# fallback ascends, so the printer owns the order rather than trusting either.
rows.sort(key=lambda r: r[0] if isinstance(r[0], (int, float)) else 0.0, reverse=True)
rows = rows[:k]
if not rows and os.environ.get("WHERE") == "local":
    print("error: well bridge unavailable and no matching local log entries", file=sys.stderr)
    sys.exit(1)
print(f"recall[{len(rows)}]{{score,source,store,title}}:")
if used_local and os.environ.get("MIMIR_REQUIRE_BRIDGE") != "1":
    reason = "bridge returned no matches" if os.environ.get("WHERE") == "bridge" else "bridge unavailable"
    print(f"retrieval: local log ({reason})")
else:
    print("retrieval: bridge")
for sc, e in rows:
    t = (e.get("content","").split("\n")[0] or "").replace('"', "").strip()[:90]
    src = (e.get("agents") or [e.get("source","well")])[0] if isinstance(e.get("agents"), list) else e.get("source","well")
    st = next((str(x).split(":",1)[1] for x in tags_of(e) if str(x).startswith("store:")), "episodic")
    print(f'  {sc},"{src}","{st}","{t}"')
PYR
)" "$WELL" "$Q" "$K" <<<"$1"
}

case "$CMD" in
  health)
    if bridge_up; then
      "$PY" "$POLICY" memory --bridge "$BRIDGE" --json | "$PY" -c '
import json, sys
try:
    row = json.load(sys.stdin)
    print("well[1]{state,entries,bridge,healthy}:")
    print("  \"WARM\",%s,\"online\",\"%s\"" %
          (row["episodes"], str(row["healthy"]).lower()))
    print("why: " + row["why"])
except (ValueError, KeyError):
    print("error: bridge memory health unavailable")
    sys.exit(1)
'
    else
      if [ "${MIMIR_REQUIRE_BRIDGE:-0}" = 1 ]; then
        printf 'error: the selected well bridge is unavailable\n' >&2; exit 1
      fi
      printf 'well[1]{state,entries,bridge}:\n  "COLD",%s,"offline"\n' "$(well_count)"
    fi
    ;;

  start|stop|status)
    # The bridge is the well's door, so its verbs are the well's verbs. Eir's
    # mends call `mimir.sh start`; until now that was a command that did not exist,
    # so a "mend" returned 2 and changed nothing (found 2026-10-26, plan 136).
    exec "$SCRIPT_DIR/../bridge/mimir-bridge.sh" "--$CMD"
    ;;

  memory)
    # THE ONE HEALTH ROW (plan 136): how big the memory is, and when it was last
    # watered, last drunk from, last written as a day, last pruned. `--check` is
    # what Eir's `memory` surface asks — exit 1 means the memory itself is failing.
    # Every flag is passed through: --line (one terse row for Eir), --json, --check
    # (exit 1 when the memory itself is failing). A filter this door does not
    # implement is REFUSED, never silently dropped — so say "no" to the unknown.
    for a in "$@"; do
      case "$a" in --line|--json|--check) ;;
        *) printf 'error: unknown flag %s\nhelp: mimir.sh memory [--line] [--json] [--check]\n' "$a" >&2; exit 2 ;;
      esac
    done
    if bridge_up; then
      out="$("$PY" "$POLICY" memory --bridge "$BRIDGE" "$@")"; rc=$?
    else
      out="$(ENGRAM_DB="$STORE" "$PY" "$POLICY" memory "$@")"; rc=$?
    fi
    printf '%s\n' "$out"
    exit "$rc"
    ;;

  recall)
    Q="${1-}"; [ $# -gt 0 ] && shift
    K=5; MODE=hybrid; TAG=""; ACTOR=""; SINCE=""; UNTIL=""; STORE_TYPE=""; ARCHIVED=0; TASK=""
    # A FILTER THE DOOR DOES NOT IMPLEMENT IS REFUSED, NEVER IGNORED. Until today
    # `recall … --tags domain:snotra` was accepted and silently dropped, so a keeper
    # asking for its own memory was handed the whole house's episodes and told the
    # answer was scoped (measured 2026-10-24; plan 129 §21, the well's three gaps).
    while [ $# -gt 0 ]; do
      case "$1" in
        --k) K=${2-5}; shift 2 ;;
        --mode) MODE=${2-hybrid}; shift 2 ;;
        --tag|--tags) TAG=${2-}; shift 2 ;;
        --actor) ACTOR=${2-}; shift 2 ;;
        --since) SINCE=${2-}; shift 2 ;;
        --until) UNTIL=${2-}; shift 2 ;;
        --store|--type) STORE_TYPE=${2-}; shift 2 ;;
        --task) TASK=${2-}; shift 2 ;;
        --archived) ARCHIVED=1; shift ;;
        -h|--help) sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'error: unknown flag %s\nhelp: recall <query> [--k N] [--mode hybrid|cosine|spreading] [--tag T] [--store TYPE] [--task T] [--actor A] [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--archived]\n' "$1" >&2; exit 2 ;;
      esac
    done
    [ -n "$Q" ] || { printf 'error: recall needs a query\nhelp: bin/records/mimir.sh recall "<query>"\n' >&2; exit 2; }
    case "$K" in
      ""|*[!0-9]*) printf 'error: --k must be an integer from 1 to 1000\n' >&2; exit 2 ;;
    esac
    [ "$K" -ge 1 ] 2>/dev/null && [ "$K" -le 1000 ] 2>/dev/null || { printf 'error: --k must be an integer from 1 to 1000\n' >&2; exit 2; }
    case "$STORE_TYPE" in
      ""|episodic|semantic|procedural) ;;
      *) printf 'error: --store must be episodic|semantic|procedural (got %s)\n' "$STORE_TYPE" >&2; exit 2 ;;
    esac

    out=""
    if bridge_up; then
      qs="q=$(printf '%s' "$Q" | urlenc)&k=$K&mode=$MODE"
      [ -n "$TAG" ] && qs="$qs&tag=$(printf '%s' "$TAG" | urlenc)"
      [ -n "$STORE_TYPE" ] && qs="$qs&store=$STORE_TYPE"
      [ -n "$SINCE" ] && qs="$qs&since=$(printf '%s' "$SINCE" | urlenc)"
      [ -n "$UNTIL" ] && qs="$qs&until=$(printf '%s' "$UNTIL" | urlenc)"
      [ -n "$ACTOR" ] && qs="$qs&agent_id=$(printf '%s' "$ACTOR" | urlenc)"
      [ -n "$TASK" ] && qs="$qs&task=$(printf '%s' "$TASK" | urlenc)"
      [ "$ARCHIVED" = "1" ] && qs="$qs&include_archived=1"
      out=$(curl -fsS --max-time 8 "$BRIDGE/recall?$qs" 2>/dev/null) || out=""
    fi
    if [ "${MIMIR_REQUIRE_BRIDGE:-0}" = 1 ] && [ -z "$out" ]; then
      printf 'error: the selected well bridge did not answer recall\n' >&2; exit 1
    fi
    _recall_print "$out" "$([ -n "$out" ] && echo bridge || echo local)" || exit $?
    # The well records a RECALL as well as a write: a memory that is never drunk
    # from is a shelf, and the health row must be able to see the difference.
    exit 0
    ;;

  observe)
    TEXT="${1-}"; [ $# -gt 0 ] && shift
    TAGS="runtime"; SRC="brokk"; TASK=""; TYPE=""; PRIVACY="internal"; RETENTION="keep"
    SCOPE="house"; CONFIDENCE=""; SALIENCE=""; SHAPE=""; FORCE=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --tags|--tag) TAGS=${2-}; shift 2 ;;
        --source) SRC=${2-}; shift 2 ;;
        --task) TASK=${2-}; shift 2 ;;
        --store|--type) TYPE=${2-}; shift 2 ;;
        --privacy) PRIVACY=${2-internal}; shift 2 ;;
        --retention) RETENTION=${2-keep}; shift 2 ;;
        --scope) SCOPE=${2-house}; shift 2 ;;
        --confidence) CONFIDENCE=${2-}; shift 2 ;;
        --salience) SALIENCE=${2-}; shift 2 ;;
        --shape) SHAPE=${2-}; shift 2 ;;
        --force) FORCE=1; shift ;;
        *) shift ;;
      esac
    done
    [ -n "$TEXT" ] || { printf 'error: observe needs text\nhelp: bin/records/mimir.sh observe "<text>"\n' >&2; exit 2; }

    REQ=$(TEXT="$TEXT" TAGS="$TAGS" SRC="$SRC" TASK="$TASK" TYPE="$TYPE" PRIVACY="$PRIVACY" \
          RETENTION="$RETENTION" SCOPE="$SCOPE" CONFIDENCE="$CONFIDENCE" SALIENCE="$SALIENCE" \
          SHAPE="$SHAPE" FORCE="$FORCE" "$PY" -c '
import json, os
e = os.environ
req = {"content": e["TEXT"], "source": e["SRC"] or "brokk",
       "tags": [t for t in (e["TAGS"] or "").split(",") if t.strip()]}
for key, env in (("task","TASK"), ("store","TYPE"), ("privacy","PRIVACY"),
                 ("retention","RETENTION"), ("scope","SCOPE"), ("shape","SHAPE")):
    if e.get(env): req[key] = e[env]
for key, env in (("confidence","CONFIDENCE"), ("salience","SALIENCE")):
    if e.get(env):
        try: req[key] = float(e[env])
        except ValueError: pass
if e.get("FORCE"): req["force"] = True
print(json.dumps(req))')

    if bridge_up; then
      answer=$(curl -fsS --max-time 60 -X POST -H 'content-type: application/json' \
                   -d "$REQ" "$BRIDGE/observe" 2>/dev/null) || answer=""
      if [ -n "$answer" ]; then
        ANSWER="$answer" "$PY" -c '
import json, os, sys
raw = os.environ.get("ANSWER") or ""
try: d = json.loads(raw)
except Exception: print("observed[1]{stored,bridge}:\n  ?,offline"); sys.exit(0)
g = d.get("gate") or {}
if d.get("stored"):
    print("observed[1]{stored,store,id,salience}:")
    print("  \"true\",\"%s\",\"%s\",%s" % (d.get("store"), d.get("id"), d.get("salience")))
    print("tags: " + ", ".join(d.get("tags") or []))
    if d.get("chain"): print("chain: " + json.dumps(d["chain"]))
else:
    print("gate[1]{stored,why}:")
    print("  \"false\",\"%s\"" % g.get("why", "dropped"))
    if g.get("duplicate_of"): print("duplicate_of: " + str(g["duplicate_of"]))
sys.exit(0 if d.get("stored") else 3)'
        exit $?
      fi
    fi

    if [ "${MIMIR_REQUIRE_BRIDGE:-0}" = 1 ]; then
      printf 'error: the selected well bridge did not accept observe\n' >&2; exit 1
    fi
    # OFFLINE: the gate still decides, and a kept lesson still reaches the record —
    # the append log, which is the well's truth. It is re-seeded into the index when
    # the bridge returns, so a bridge outage costs indexing time, never a lesson.
    decision=$(MIMIR_POLICY="$POLICY" gate_json "$REQ")
    keep=$(printf '%s' "$decision" | "$PY" -c 'import json,sys;d=json.load(sys.stdin);print("yes" if d.get("keep") else "no")' 2>/dev/null || echo no)
    if [ "$keep" != "yes" ]; then
      printf 'gate[1]{stored,why}:\n  "false","%s"\n' \
        "$(printf '%s' "$decision" | "$PY" -c 'import json,sys;print(json.load(sys.stdin).get("why","dropped"))' 2>/dev/null || echo 'dropped')"
      exit 3
    fi
    # The decision rides in the environment, not on stdin: stdin carries the script.
    DECISION="$decision" "$PY" - "$WELL" <<'PY'
import datetime as _dt
import json, hashlib, os, sys
d = json.loads(os.environ["DECISION"])
content = d["content"]
rec = {"timestamp": _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
       "source": d["meta"]["source"], "actors": [d["meta"]["source"]],
       "tags": d["tags"], "content": content,
       "salience": d["salience"], "importance": d["salience"],
       "agent_id": d["meta"]["source"], "hash": hashlib.sha256(content.encode()).hexdigest(),
       "store": d["store"], "provenance": d["provenance"],
       "quarantined": d["quarantined"], "gate": d["meta"].get("gate")}
with open(sys.argv[1], "a", encoding="utf-8") as fh:
    fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
print("observed[1]{stored,store,salience,bridge}:")
print("  \"true\",\"%s\",%s,\"local\"" % (d["store"], d["salience"]))
print("tags: " + ", ".join(d["tags"]))
print("re-seed into the index when the bridge is up: bin/records/mimir-log.sh reseed")
PY
    exit 0
    ;;

  correct|retract)
    ID="${1-}"; [ $# -gt 0 ] && shift
    [ -n "$ID" ] || { printf 'error: %s needs the episode id\nhelp: bin/records/mimir.sh %s <episode-id> [<text>] [--why "..."]\n' "$CMD" "$CMD" >&2; exit 2; }
    SRC="brokk"; WHY=""; TEXT=""; TAGS=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --source) SRC=${2-brokk}; shift 2 ;;
        --why) WHY=${2-}; shift 2 ;;
        --tags) TAGS=${2-}; shift 2 ;;
        -*) shift ;;
        *) TEXT="${TEXT:+$TEXT }$1"; shift ;;
      esac
    done
    bridge_up || { printf 'error: the bridge must be up to chain a correction — it is what annotates the original\ntry: bin/bridge/mimir-bridge.sh --start\n' >&2; exit 1; }
    if [ "$CMD" = "correct" ]; then
      [ -n "$TEXT" ] || { printf 'error: correct needs the corrected text\nhelp: bin/records/mimir.sh correct <episode-id> "<what is true now>"\n' >&2; exit 2; }
      REQ=$(TEXT="$TEXT" ID="$ID" SRC="$SRC" TAGS="$TAGS" "$PY" -c 'import json,os;e=os.environ;print(json.dumps({"original_id":e["ID"],"content":e["TEXT"],"source":e["SRC"],"tags":[t for t in (e["TAGS"] or "").split(",") if t.strip()]}))')
      path=correct
    else
      REQ=$(ID="$ID" SRC="$SRC" WHY="$WHY" "$PY" -c 'import json,os;e=os.environ;print(json.dumps({"original_id":e["ID"],"why":e["WHY"],"source":e["SRC"]}))')
      path=retract
    fi
    ANSWER=$(curl -fsS --max-time 60 -X POST -H 'content-type: application/json' -d "$REQ" "$BRIDGE/$path" 2>/dev/null) || ANSWER=""
    [ -n "$ANSWER" ] || { printf 'error: the bridge did not answer — is it up?\nhelp: bin/bridge/mimir-bridge.sh --status\n' >&2; exit 1; }
    ANSWER="$ANSWER" CMD="$CMD" ID="$ID" "$PY" -c '
import json, os, sys
d = json.loads(os.environ["ANSWER"])
if d.get("stored"):
    print("correction[1]{kind,original,replacement,store}:")
    print("  \"%s\",\"%s\",\"%s\",\"%s\"" % (os.environ["CMD"], os.environ["ID"], d.get("id"), d.get("store")))
    print("chain: " + json.dumps(d.get("chain") or {}))
    print("the original stays in the record, voided — never erased (Rule 20)")
else:
    print("gate[1]{stored,why}:")
    print("  \"false\",\"%s\"" % (d.get("gate") or {}).get("why", "dropped"))
    sys.exit(3)'
    ;;

  why)
    ID="${1-}"
    [ -n "$ID" ] || { printf 'error: why needs an episode id\n' >&2; exit 2; }
    bridge_up || { printf 'error: the bridge must be up to read a chain\n' >&2; exit 1; }
    curl -fsS --max-time 5 "$BRIDGE/episode?id=$(printf '%s' "$ID" | urlenc)" 2>/dev/null | "$PY" -c '
import json, sys
d = json.load(sys.stdin)
e = d.get("episode") or d
print("episode[1]{id,store,voided,archived,agent}:")
print("  \"%s\",\"%s\",\"%s\",\"%s\",\"%s\"" % (e.get("id"), e.get("store"),
      str(e.get("voided")).lower(), str(e.get("archived")).lower(), e.get("agent_id")))
print("tags: " + ", ".join(e.get("tags") or []))
c = e.get("chain") or {}
for key in ("voided_by", "replaced_by", "retracted_by", "consolidated_by"):
    if c.get(key): print("%s: %s" % (key, ", ".join(c[key])))
if e.get("voided"): print("this episode is VOID — a later entry corrects it; it stays in the record")
print("---")
print((e.get("content") or "")[:1200])'
    ;;

  grade)
    # Continuous forgetting. Report by default; `--apply` decays, annotates, moves.
    APPLY=""; for a in "$@"; do case "$a" in --apply) APPLY=1 ;; esac; done
    # Decay lives in the engine, so grade under the bridge's own interpreter when
    # it is there — never a second guess about which python owns the store.
    BPY="$("$SCRIPT_DIR/../bridge/mimir-bridge.sh" --python 2>/dev/null || true)"
    [ -n "$BPY" ] && command -v "$BPY" >/dev/null 2>&1 && PY="$BPY"
    ENGRAM_DB="$STORE" "$PY" "$POLICY" grade ${APPLY:+--apply}
    ;;

  policy)
    MIMIR_POLICY="$POLICY" "$PY" "$POLICY" "$@"
    ;;

  timeline)
    ENTITY=""; while [ $# -gt 0 ]; do case "$1" in --entity) ENTITY=${2-}; shift 2 ;; *) shift ;; esac; done
    if bridge_up && [ -n "$ENTITY" ]; then
      curl -fsS --max-time 5 "$BRIDGE/timeline?entity=$(printf '%s' "$ENTITY" | urlenc)" 2>/dev/null && exit 0
    fi
    python3 - "$WELL" <<'PY'
import json,sys
rows=[]
for line in open(sys.argv[1], encoding='utf-8', errors='ignore'):
    if not line.strip().startswith('{'): continue
    try: e=json.loads(line)
    except: continue
    rows.append(e)
print(f"timeline[{min(len(rows),20)}]{{ts,source,title}}:")
for e in rows[-20:][::-1]:
    t=(e.get('content','').split('\n')[0] or '').replace('#','').strip()[:80]
    print(f"  \"{e.get('timestamp','')}\",\"{e.get('source','well')}\",\"{t}\"")
PY
    ;;

  *)
    printf 'error: unknown command %s\nhelp: bin/records/mimir.sh [health|memory|recall|observe|correct|retract|why|grade|timeline|policy|--version]\n' "$CMD" >&2
    exit 2 ;;
esac
