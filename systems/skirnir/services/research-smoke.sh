#!/usr/bin/env bash
# research-smoke.sh — Skírnir's research door, proved end to end in one run.
#
#   bin/assistant/research-smoke.sh [--query "…"] [--model <rail-alias>]
#
# What it proves, in order: the door reaches the REAL provider (Exa, the same one Pi's web_search
# uses), it returns sources with text and no links, it is fast enough to be a lookup, the engine
# routes a spoken/typed request to it, a stranger is refused, and a research answer never carries a
# private name. A clean skip when there is no network is a PASS (Rule 25) — this box is not always
# online and a smoke test must not lie about that.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo root, found by walking up to the tree that holds .pi and RULES — never counted in
# "../", because this shelf was moved once (bin/assistant/ -> systems/skirnir/, plan 149) and
# 25 scripts kept the old depth, so every $ROOT/bin/... pointed into systems/ instead (2026-11-02).
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)"
ENGINE="$SCRIPT_DIR/skirnir.py"
DOOR="$SCRIPT_DIR/research.py"
QUERY="OVK ventilation Boverket requirements"
MODEL="${SKIRNIR_MODEL:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --query) QUERY="${2:-}"; shift 2 ;;
    --model) MODEL="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

fails=0; skips=0; passes=0
pass() { printf '  PASS %s\n' "$1"; passes=$((passes+1)); }
fail() { printf '  FAIL %s — %s\n' "$1" "$2" >&2; fails=$((fails+1)); }
skip() { printf '  SKIP %s — %s\n' "$1" "$2"; skips=$((skips+1)); }
jget() { python3 -c 'import json,sys;d=json.load(sys.stdin);print(eval(sys.argv[1]))' "$1" 2>/dev/null; }

echo "research-smoke — the open web, end to end"

# ── the network, before anything else ───────────────────────────────────────────────────────────
if ! curl -s -o /dev/null --max-time 6 https://mcp.exa.ai/mcp 2>/dev/null; then
  skip "the door" "no network — the provider is unreachable from this box"
  echo
  printf 'research-smoke: skipped cleanly (%d skip, no failure)\n' "$skips"
  exit 0
fi

# ── 1 · the door itself ─────────────────────────────────────────────────────────────────────────
start=$(date +%s%N)
OUT="$(timeout 90 python3 "$DOOR" --query "$QUERY" --limit 3 --no-cache 2>/dev/null)"
elapsed=$(( ($(date +%s%N) - start) / 1000000 ))

[ -n "$OUT" ] && pass "the door answered" || fail "the door answered" "no output"

provider="$(printf '%s' "$OUT" | jget "d.get('provider','')")"
n="$(printf '%s' "$OUT" | jget "len(d.get('sources') or [])")"
case "$provider" in
  exa) pass "the provider is Exa — the same door Pi's web_search uses" ;;
  wikipedia-fallback) fail "the provider is Exa" "fell back to $provider — Exa was unreachable" ;;
  *) fail "the provider is Exa" "got '$provider'" ;;
esac

[ "${n:-0}" -ge 1 ] && pass "sources returned (${n})" || fail "sources returned" "none for '$QUERY'"

links="$(printf '%s' "$OUT" | python3 -c '
import json,sys,re
d=json.load(sys.stdin)
bad=[s for s in (d.get("sources") or []) if re.search(r"https?://|www\.|!\[", s.get("extract",""))]
print(len(bad))' 2>/dev/null)"
[ "${links:-1}" = "0" ] && pass "no link, image or URL in the fetched text" \
  || fail "no link in the fetched text" "$links source(s) carried one"

domains="$(printf '%s' "$OUT" | python3 -c '
import json,sys
d=json.load(sys.stdin)
print(",".join(sorted({s.get("domain","") for s in (d.get("sources") or []) if s.get("domain")})))' 2>/dev/null)"
[ -n "$domains" ] && pass "sources are named by host: ${domains}" || fail "sources named by host" "no domains"

[ "$elapsed" -lt 15000 ] && pass "a lookup, not a crawl — ${elapsed} ms for ${n} source(s)" \
  || fail "lookup latency" "${elapsed} ms is too slow for a request"

# ── 1b · a repeat is not a new question ─────────────────────────────────────────────────────────
start=$(date +%s%N)
REP="$(timeout 90 python3 "$DOOR" --query "$QUERY" --limit 3 2>/dev/null)"
rep_elapsed=$(( ($(date +%s%N) - start) / 1000000 ))
rprovider="$(printf '%s' "$REP" | jget "d.get('provider','')")"
rn="$(printf '%s' "$REP" | jget "len(d.get('sources') or [])")"
case "$rprovider" in
  exa-cache) pass "a repeat is served from the cache — ${rep_elapsed} ms, no provider call" ;;
  exa) pass "the provider answered again (no cache on this home) — ${rep_elapsed} ms" ;;
  *) fail "a repeat is served from the cache" "provider '$rprovider'" ;;
esac
[ "${rn:-0}" -ge 1 ] && pass "the cached answer still carries its sources (${rn})" \
  || fail "cached sources" "none"

# ── 2 · the engine routes a request to the door ─────────────────────────────────────────────────
ask() { SKIRNIR_MODEL="$MODEL" python3 "$ENGINE" --tier "${2:-owner}" --channel "${3:-console}" \
        --text "$1" 2>/dev/null; }

R="$(ask 'look up what an OVK inspection requires in Sweden' owner)"
intent="$(printf '%s' "$R" | jget "d.get('intent','')")"
answer="$(printf '%s' "$R" | jget "d.get('answer','')")"
case "$intent" in
  research|research-empty) pass "the engine routed the request to the door (intent: $intent)" ;;
  *) fail "the engine routed the request" "intent '$intent'" ;;
esac
[ -n "$answer" ] && pass "he said something (${#answer} chars)" || fail "he said something" "empty answer"
case "$answer" in
  *http*|*"www."*|*"!["*) fail "the gate held" "a link reached the answer" ;;
  *) pass "no link reached the answer" ;;
esac
case "$answer" in
  *"open web"*|*Boverket*|*Wikipedia*) pass "he says where it came from" ;;
  *) fail "he says where it came from" "$answer" ;;
esac
case "$answer" in
  *"Craig Martin"*|*Andre*|*Isabella*|*Reygan*) fail "no private name rode along" "$answer" ;;
  *) pass "no private name rode along" ;;
esac

# ── 3 · the door is the Allfather's alone ───────────────────────────────────────────────────────
S="$(ask 'look up what an OVK inspection requires in Sweden' stranger)"
sintent="$(printf '%s' "$S" | jget "d.get('intent','')")"
sanswer="$(printf '%s' "$S" | jget "d.get('answer','')")"
case "$sanswer" in
  *"don't search"*) pass "a stranger is refused in words" ;;
  *) fail "a stranger is refused" "$sanswer" ;;
esac
case "$sanswer" in
  *Boverket*|*"certified inspector"*) fail "a stranger got web content" "$sanswer" ;;
  *) pass "a stranger gets no web content" ;;
esac

# ── 4 · the walls did not move: an unheld subject is still an honest no ────────────────────────
U="$(ask 'what is gimle' owner)"
uintent="$(printf '%s' "$U" | jget "d.get('intent','')")"
[ "$uintent" = "unknown" ] && pass "an unheld subject is still refused, not answered as another fact" \
  || fail "unheld subject" "intent '$uintent'"

# ── 5 · the mouth, if a model is named ─────────────────────────────────────────────────────────
if [ -n "$MODEL" ]; then
  M="$(SKIRNIR_MODEL="$MODEL" python3 "$ENGINE" --tier owner --channel console \
        --text 'look up what an OVK inspection requires in Sweden' 2>/dev/null)"
  manswer="$(printf '%s' "$M" | jget "d.get('answer','')")"
  case "$manswer" in
    "") fail "the model phrased the research answer" "empty" ;;
    *http*) fail "the model kept the gate" "a link appeared" ;;
    *) pass "the model phrased it and the gate still held" ;;
  esac
else
  skip "the model leg" "no SKIRNIR_MODEL named (templates only)"
fi

echo
if [ "$fails" -eq 0 ]; then
  printf 'research-smoke: green — %d pass, %d skip\n' "$passes" "$skips"
  exit 0
fi
printf 'research-smoke: %d failure(s)\n' "$fails" >&2
exit 1
