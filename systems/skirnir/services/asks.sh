#!/usr/bin/env bash
# asks.sh — the ledger of questions Skírnir could not answer, and the road that closes the loop.
#
#   asks.sh add --who "Isabella Jakobsson (@isalorain)" --chat 4242 --channel telegram-dm \
#               --question "what is the OptiCat deadline" [--context "…"]   → prints the id
#   asks.sh list [--open|--all]                                            → TOON rows
#   asks.sh get <id>                                                       → the record
#   asks.sh deliver <id> --text "…"                                        → send his answer to the asker
#   asks.sh close <id> [--why "…"]
#
# WHY THIS EXISTS: an escalation that only travels one way is dead work. The Allfather answers in his
# own DM and the person who asked never hears it — measured 2026-10-22. Every ask is a record here,
# so it can be answered, reminded about, and reported.
#
# State: $YMIR_HOME/hodd/state/assistant/asks.json (runtime, never the repo).
# Delivery: the assistant's OWN bot, to the asker's chat, labelled as his answer. Nothing else sends.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo root, found by walking up to the tree that holds .pi and RULES — never counted in
# "../", because this shelf was moved once (bin/assistant/ -> systems/skirnir/, plan 149) and
# 25 scripts kept the old depth, so every $ROOT/bin/... pointed into systems/ instead (2026-11-02).
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)"
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
ymir_home_root HOME_R 2>/dev/null || true
[ -n "${HOME_R:-}" ] || { printf 'asks: the hoard is unresolved\n' >&2; exit 2; }
STATE="$HOME_R/hodd/state/assistant"
FILE="$STATE/asks.json"
mkdir -p "$STATE" 2>/dev/null || true

cmd="${1:-list}"; shift || true
WHO=""; CHAT=""; CHANNEL=""; QUESTION=""; CONTEXT=""; TEXT=""; WHY=""; ID=""; FILTER="open"
while [ $# -gt 0 ]; do
  case "$1" in
    --who) WHO="${2:-}"; shift 2 ;;
    --chat) CHAT="${2:-}"; shift 2 ;;
    --channel) CHANNEL="${2:-}"; shift 2 ;;
    --question) QUESTION="${2:-}"; shift 2 ;;
    --context) CONTEXT="${2:-}"; shift 2 ;;
    --text) TEXT="${2:-}"; shift 2 ;;
    --why) WHY="${2:-}"; shift 2 ;;
    --open) FILTER="open"; shift ;;
    --all) FILTER="all"; shift ;;
    -*) shift ;;
    *) ID="$1"; shift ;;
  esac
done

export HOME_R="$HOME_R" ROOT_DIR="$ROOT" ASKS_FILE="$FILE" ASKS_CMD="$cmd" ASKS_ID="$ID" ASKS_WHO="$WHO" ASKS_CHAT="$CHAT" \
       ASKS_CHANNEL="$CHANNEL" ASKS_QUESTION="$QUESTION" ASKS_CONTEXT="$CONTEXT" \
       ASKS_TEXT="$TEXT" ASKS_WHY="$WHY" ASKS_FILTER="$FILTER" ASKS_STATE="$STATE"
python3 - <<'PY'
import hashlib, json, os, subprocess, sys, time

path = os.environ["ASKS_FILE"]
try:
    data = json.load(open(path))
except Exception:
    data = {"asks": []}
asks = data.setdefault("asks", [])
cmd = os.environ["ASKS_CMD"]

def save():
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(data, fh, indent=1)
    os.replace(tmp, path)

def find(i):
    for a in asks:
        if a.get("id") == i:
            return a
    return None

if cmd == "add":
    q = os.environ["ASKS_QUESTION"].strip()
    if not q:
        sys.exit(2)
    ident = "ask-" + hashlib.sha256(f"{q}|{os.environ['ASKS_CHAT']}|{time.time()}".encode()).hexdigest()[:10]
    asks.append({"id": ident, "at": time.time(), "who": os.environ["ASKS_WHO"] or "someone",
                 "chat": os.environ["ASKS_CHAT"], "channel": os.environ["ASKS_CHANNEL"],
                 "question": q, "context": os.environ["ASKS_CONTEXT"], "status": "open",
                 "reminded": 0, "answered_at": None, "answer": None})
    save()
    print(ident)

elif cmd == "list":
    want = os.environ["ASKS_FILTER"]
    rows = [a for a in asks if want == "all" or a.get("status") == "open"]
    rows.sort(key=lambda a: a.get("at", 0))
    print(f'asks[{{n}}]{{id,who,status,age_h,question}}')
    print(f"asks{len(rows)}")
    for a in rows:
        age = round((time.time() - float(a.get("at", 0))) / 3600, 1)
        print(f'  "{a["id"]}","{a.get("who","")}","{a.get("status","")}","{age}","{a.get("question","")[:90]}"')

elif cmd == "get":
    a = find(os.environ["ASKS_ID"])
    print(json.dumps(a, indent=1) if a else "null")

elif cmd == "close":
    a = find(os.environ["ASKS_ID"])
    if not a:
        sys.exit(3)
    a["status"] = "closed"
    a["closed_why"] = os.environ["ASKS_WHY"]
    a["answered_at"] = time.time()
    save()
    print(f'ask[1]{{id,status}}: "{a["id"]}","closed"')

elif cmd == "deliver":
    a = find(os.environ["ASKS_ID"])
    if not a:
        print("asks: no such ask", file=sys.stderr)
        sys.exit(3)
    text = os.environ["ASKS_TEXT"].strip()
    if not text:
        print("asks: nothing to deliver", file=sys.stderr)
        sys.exit(2)
    if a.get("status") == "answered":
        print("asks: already answered", file=sys.stderr)
        sys.exit(4)
    chat = str(a.get("chat") or "")
    if not chat:
        print("asks: the ask carries no chat id — cannot deliver", file=sys.stderr)
        sys.exit(5)
    root = os.environ["ROOT_DIR"] if os.environ.get("ROOT_DIR") else os.path.dirname(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    vault = os.path.join(root, "bin", "vault", "hodd.sh")
    def secret(name):
        out = subprocess.run(["bash", vault, "emit", "secrets/platform.env"],
                             capture_output=True, text=True, timeout=20).stdout
        for line in out.splitlines():
            line = line.strip()
            if line.startswith("export "):
                line = line[7:]
            if line.startswith(name + "="):
                return line.split("=", 1)[1].strip().strip("'\"")
        return ""
    token = secret("SKIRNIR_TELEGRAM_BOT_TOKEN")
    if not token:
        print("asks: no bot token in the vault", file=sys.stderr)
        sys.exit(6)
    body = (f"{text}\n\n— Skírnir, the Allfather's assistant. He asked me to pass this on.")
    res = subprocess.run(["curl", "-s", "-m", "20",
                          f"https://api.telegram.org/bot{token}/sendMessage",
                          "--data-urlencode", f"chat_id={chat}",
                          "--data-urlencode", f"text={body}",
                          "-d", "disable_web_page_preview=true"],
                         capture_output=True, text=True)
    if '"ok":true' not in (res.stdout or ""):
        print(f"asks: delivery failed — {res.stdout[:160]}", file=sys.stderr)
        sys.exit(7)
    a["status"] = "answered"
    a["answered_at"] = time.time()
    a["answer"] = text[:2000]
    save()
    # THE ANSWER IS KNOWLEDGE. He wrote it himself for a person who asked; the next person who asks
    # the same thing should not have to wait for him again. Approved because the words are his.
    try:
        import hashlib as _h
        ident_dir = os.path.join(os.environ.get("HOME_R", ""), "hodd", "identity", "assistant", "approved")
        if os.path.isdir(ident_dir):
            slug = "answered-" + _h.sha256((a.get("question", "") + text).encode()).hexdigest()[:10]
            claim = text.strip().replace("\n", " ")[:400]
            question = str(a.get("question", "")).strip().replace("\n", " ")[:200]
            with open(os.path.join(ident_dir, slug + ".md"), "w") as fh:
                fh.write("---\n"
                         "approved_by: the Allfather\n"
                         f"approved_at: {time.strftime('%Y-%m-%d')}\n"
                         "class: public\naudience: public\n"
                         f"learned_from: the Allfather, answering {a.get('who','someone')}\n"
                         f"learned_in: {chat}\n"
                         f"learned_at: {time.strftime('%Y-%m-%dT%H:%M:%S%z')}\n"
                         "---\n"
                         f"Asked “{question}”, the Allfather's answer was: {claim}\n")
            subprocess.run(["bash", os.path.join(os.environ.get("ROOT_DIR", ""),
                                                 "bin", "assistant", "kb-export.sh")],
                           check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            print(f"asks: learned it — {slug} (the answer is now an approved fact)")
    except Exception as exc:
        print(f"asks: delivered, but could not learn it: {type(exc).__name__}", file=sys.stderr)
    print(f'ask[1]{{id,who,status,chat}}: "{a["id"]}","{a.get("who","")}","answered","{chat}"')
else:
    print("usage: asks.sh add|list|get|close|deliver …", file=sys.stderr)
    sys.exit(2)
PY
