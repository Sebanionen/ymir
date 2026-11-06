#!/usr/bin/env bash
# intake-gate.sh — is this message signal, or noise? One decision call, three described options.
#
#   echo "<message>" | bin/notify/intake-gate.sh [--door jev-kev-4b] [--json]
#
# HYPE (loud, uncheckable) · FACTS (true, not actionable now) · SIGNAL (it changes a decision
# we are about to make). Options are DESCRIBED: measured twice on this box — bare labels gave
# confidence 0.47, descriptions 0.998. Below the cut-off the verdict is ADVISORY: it reorders
# what the operator reads; it never deletes.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
DOOR="jev-kev-4b"; TEXT=""; JSON="0"
while [ $# -gt 0 ]; do case "$1" in
  --door) DOOR="${2-}"; shift 2 ;;
  --text) TEXT="${2-}"; shift 2 ;;
  --json) JSON="1"; shift ;;
  *) shift ;;
esac; done
[ -n "$TEXT" ] || TEXT="$(cat)"
[ -n "${TEXT// }" ] || { printf 'intake-gate: nothing to judge\n' >&2; exit 2; }

KEY="$(bash "$ROOT/bin/vault/hodd.sh" emit secrets/platform.env 2>/dev/null | sed -n 's/^export LLAMA_SWAP_API_KEY=//p' | head -1 | tr -d '"'"'"'' )"
URL="$(bash "$ROOT/bin/model/jev-doors.sh" url "$DOOR" 2>/dev/null)"
[ -n "$URL" ] || { printf 'intake-gate: no door for %s — bin/model/jev-doors.sh list\n' "$DOOR" >&2; exit 2; }

TEXT="$TEXT" URL="$URL" KEY="$KEY" JSON_OUT="$JSON" python3 - <<'PY'
import json, os, urllib.request

text = os.environ["TEXT"][:4000]
url = os.environ["URL"]; key = os.environ["KEY"]

# FEW-SHOT IN THE STATE — the finding from plan 201 §7.3: the verdict moves with the
# criteria wording more than with the message, so the examples carry our idiom.
FEW_SHOT = (
    "Six examples of how this house classifies a message, two per label:\n"
    "A. 'the well bridge is down on :4602 — restart it' -> signal\n"
    "B. 'Reygan accepted the meeting invitation for Tuesday at 9' -> facts\n"
    "C. 'a new model claims 10x better coding, no benchmarks published' -> hype\n"
    "D. 'Sebastian asks whether the door is up — he is blocked' -> signal\n"
    "E. 'a vendor published benchmarks showing their model is faster' -> facts\n"
    "F. 'this changes everything, everyone is switching, nobody has measured it' -> hype\n"
    "signal = an action somebody here must take TODAY. facts = true, nothing to do.\n"
    "hype = uncheckable, or a claim with no evidence.\n"
    "Classify the message below with one of those three words.\n"
)
state = FEW_SHOT + text

questions = {
    "kind": {"type": "choice",
             "instructions": "How should an engineering house treat this message?",
             "criteria": {
                 "signal": "it names an action one of us must take TODAY in this house: something is broken, someone is blocked, or a decision cannot wait",
                 "facts": "it is true and checkable, but there is nothing for us to do about it today",
                 "hype": "it cannot be checked, or its source has no record, or it is a claim with no evidence"}},
    "urgent": {"type": "noul", "instructions": "Does this need a human today?"},
}
req = urllib.request.Request(url, data=json.dumps({"state": state, "questions": questions}).encode(),
                             headers={"content-type": "application/json", "authorization": "Bearer " + key})
try:
    with urllib.request.urlopen(req, timeout=30) as r:
        d = json.load(r)
except Exception as e:
    print("intake-gate: the door did not answer —", e); raise SystemExit(3)
a = d.get("answers") or {}
k = a.get("kind") or {}; u = a.get("urgent") or {}
choice = k.get("choice", "?"); probs = k.get("probabilities") or {}; conf = float(k.get("confidence") or 0)
urg = float(u.get("noul") or 0)
if os.environ.get("JSON_OUT") == "1":
    print(json.dumps({"kind": choice, "probabilities": probs, "confidence": conf,
                      "urgent": urg, "advisory": conf < 0.7}, indent=1))
else:
    p = ", ".join("%s %.3f" % (x, v) for x, v in sorted(probs.items(), key=lambda t: -t[1]))
    adv = "yes — below 0.70, a human decides" if conf < 0.7 else "no"
    print("intake[4]{kind,confidence,urgent,advisory}:")
    print('  "%s","%.3f","%.3f","%s"' % (choice, conf, urg, adv))
    print("// " + p)
PY
