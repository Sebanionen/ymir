#!/usr/bin/env bash
# garmr-bite.sh — GARMR'S TEETH. The hound may contain, within a written allowlist.
#
# Plan 98 §"the bite". Detection without containment leaves the door open while the Allfather
# sleeps; containment without law turns a guard into the hole. So a bite is:
#
#   · PRE-APPROVED   — it must match a rule in the rules file; an unmatched finding is a BARK
#   · RECORDED FIRST — a Rune with the intent, the target and the UN-BITE command is carved
#                      BEFORE the act, and the result after (a bite that cannot be written down
#                      is not taken)
#   · REVERSIBLE     — every bite names its undo; if the undo is unknown, no bite
#   · NEVER THE OPERATOR'S HANDS — not his terminal session, not an open vault, not a unit-less
#                      process he started, not a model mid-generation
#   · ANNOUNCED      — Gná carries it at CRITICAL with the un-bite in the message
#   · LOCAL ONLY     — nothing leaves the machine. A blocked destination is a door WE closed,
#                      never a counter-strike
#
# The switch (GARMR_BITE, from the guardian config) is the Allfather's:
#   off      bark only — today's behaviour, the safe default on a new machine
#   report   bark AND say what it would bite (the shipping default)
#   contain  perform the allowlisted bite
#   hard     contain, and stop the unit that caused it
#
# Usage:
#   garmr-bite.sh status                     # the switch, the allowlist, the last bites
#   garmr-bite.sh allowlist                  # exactly what may be bitten, and how it is undone
#   garmr-bite.sh plan [--findings FILE]     # what it WOULD bite now (no side effects, ever)
#   garmr-bite.sh contain [--dry-run]        # perform the allowlisted bites allowed by the switch
#   garmr-bite.sh advise [--findings FILE]   # the model ADVISES one allowlisted bite; the rules dispose
#   (hound.model: on in guardian.yaml puts the advisor in the RESPONSE path for an uncovered CRITICAL)
#   garmr-bite.sh undo <rune-checksum|id>    # run the recorded un-bite for one bite
#
# Exit: 0 ok · 1 a refusal or a fault · 2 usage · 3 the switch forbids acting
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=bin/vault/hoard-lib.sh
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
VERSION="1.0.0"

advise_cfg() {  # <key> <default> — read the advisor's road from the guardian config
  python3 - "$GUARDIAN" "$1" "$2" <<'PY'
import sys
try:
    import yaml
    d = yaml.safe_load(open(sys.argv[1])) or {}
except Exception:
    print(sys.argv[3]); raise SystemExit(0)
raw = (d.get("hound") or {}).get(sys.argv[2], sys.argv[3])
if isinstance(raw, bool):
    print("true" if raw else "false")
else:
    print(str(raw))
PY
}

home_or_die() {
  local h=""
  declare -f ymir_home_root >/dev/null 2>&1 && ymir_home_root h 2>/dev/null
  [ -n "$h" ] || h="${YMIR_HOME:-}"
  [ -n "$h" ] || { printf 'bite[1]{error}: "the hoard is unresolved — set YMIR_HOME"\n' >&2; exit 2; }
  printf '%s' "$h"
}
H="$(home_or_die)"
RULES="$H/config/garmr-rules.yaml"
GUARDIAN="$H/config/guardian.yaml"
STATE="${GARMR_STATE_DIR:-$H/state/garmr}"
mkdir -p "$STATE" 2>/dev/null || true

case "${1-}" in -v|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help|"") sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac

# ── the switch ────────────────────────────────────────────────────────────────
bite_mode() {
  if [ -n "${GARMR_BITE:-}" ]; then printf '%s' "$GARMR_BITE"; return; fi
  python3 - "$GUARDIAN" <<'PY'
import sys, os
try:
    import yaml
    d = yaml.safe_load(open(sys.argv[1])) or {}
except Exception:
    print("report"); raise SystemExit(0)
raw = (d.get("hound") or {}).get("bite", d.get("bite", "report"))
# YAML 1.1 turns bare `off`/`no`/`false` into a BOOLEAN — a switch that silently reads as False is
# the worst kind of safety bug, so both are mapped, and the example config quotes the value.
if raw is False or (isinstance(raw, str) and raw.strip().lower() in ("off", "no", "false")):
    print("off"); raise SystemExit(0)
m = str(raw or "report").strip().lower()
print(m if m in ("off", "report", "contain", "hard") else "report")
PY
}
MODE="$(bite_mode)"

# Is the model in the response path?  `hound.model: on` in guardian.yaml, or GARMR_ADVISOR_MODEL=on.
# Even then it may only choose from the six and only for a finding a written rule did not cover.
model_mode() {
  if [ -n "${GARMR_ADVISOR_MODEL:-}" ]; then printf '%s' "$GARMR_ADVISOR_MODEL"; return; fi
  python3 - "$GUARDIAN" <<'PY'
import sys
try:
    import yaml
    d = yaml.safe_load(open(sys.argv[1])) or {}
except Exception:
    print("off"); raise SystemExit(0)
raw = (d.get("hound") or {}).get("model", "off")
print("on" if str(raw).strip().lower() in ("on", "true", "yes", "1") else "off")
PY
}
MODEL_MODE="$(model_mode)"

# ── the allowlist (the six bites plan 98 permits, and nothing else) ────────────
allowlist() {
  cat <<'EOF'
bite_allowlist[6]{bite,rule_class,un_bite}:
  "egress-block","egress-unapproved","nft delete rule — the exact rule is in the rune"
  "listener-close","listener-unknown","ufw delete the recorded rule (the rule text is in the rune)"
  "stop-unit","unit-anomaly","systemctl start <unit> — the unit itself is untouched"
  "kill-process","process-no-unit","the owner restarts it; the command line is in the rune"
  "quarantine-file","file-unmanifested","mv back to the recorded original path"
  "revoke-token","token-no-approval","REFUSED automatically: a token is reissued through its door, never un-revoked in place"
EOF
}

# ── decision: findings × rules → planned bites ────────────────────────────────
# Reads findings.jsonl (one JSON object per line) and prints one plan line per admissible bite.
plan() {
  local findings="$1"
  python3 - "$findings" "$RULES" <<'PY'
import sys, json, os

findings, rules_path = sys.argv[1], sys.argv[2]

def load_rules(path):
    try:
        import yaml
        d = yaml.safe_load(open(path)) or {}
    except Exception:
        return {}
    return d

rules = load_rules(rules_path)
enabled = {str(r).lower() for r in (rules.get("enabled") or [])}
peers = {str(p) for p in (rules.get("peers") or [])}
ports = {int(p) for p in (rules.get("allowed_ports") or []) if str(p).isdigit()}
paths_ok = tuple(rules.get("allowed_paths") or ["/usr/", os.path.expanduser("~/.local/bin/")])
operated = set(str(p) for p in (rules.get("operator_pids") or []))

def emit(bite, cls, target, undo, why):
    if cls not in enabled:
        return
    print("\t".join([bite, cls, target, undo, why]))

for line in open(findings, encoding="utf-8") if os.path.exists(findings) else []:
    line = line.strip()
    if not line:
        continue
    try:
        f = json.loads(line)
    except Exception:
        continue
    cls = str(f.get("class") or f.get("rule") or "").lower()
    sev = str(f.get("severity") or "").upper()
    if sev not in ("HIGH", "CRITICAL"):
        continue
    if cls == "egress-unapproved":
        dst = f.get("dst") or f.get("destination") or ""
        if dst and dst not in peers:
            emit("egress-block", cls, dst, f"nft delete rule inet garmr out_egress ip daddr {dst}", "egress to a host that is not a named peer")
    elif cls == "listener-unknown":
        port = f.get("port")
        if port and int(port) not in ports:
            emit("listener-close", cls, str(port), f"ufw allow {port}/tcp   # restore ONLY if the Allfather names this door", "a listener that is in no door list")
    elif cls == "process-no-unit":
        pid = str(f.get("pid") or "")
        if pid and pid not in operated:
            emit("kill-process", cls, pid, f"# restart by its owner: {f.get('comm','?')}", "a process with no unit, from a writable path")
    elif cls == "file-unmanifested":
        path = str(f.get("path") or "")
        if path and not path.startswith(paths_ok):
            emit("quarantine-file", cls, path, f"mv {os.path.join(os.path.expanduser('~/.local/state/ymir/quarantine'))}/{os.path.basename(path)} {path}", "a file that ran without being in the manifest")
    elif cls == "unit-anomaly":
        unit = str(f.get("unit") or "")
        if unit:
            emit("stop-unit", cls, unit, f"systemctl start {unit}", "a unit that started behaving oddly")
    elif cls == "token-no-approval":
        emit("revoke-token", cls, str(f.get("token_id") or "?"), "# reissue through the normal door; never un-revoke in place", "a token that appeared with no approval record")
PY
}


# ── the counter: the model ADVISES, the rules DISPOSE ─────────────────────────
# The Allfather's clarification: use the model to stop an attack — to close a door. That is the
# lawful counter (containment inside our own house), and the model's place in it is narrow on
# purpose:
#   · it may choose ONLY from the six allowlisted bites, and "none";
#   · it never executes anything — the deterministic layer performs the bite, with its undo;
#   · it sees METADATA ONLY (class · severity · pid · port · path · dst), never the payload,
#     because text from an attacker in front of a model is a way to make the defender close the
#     door the attacker wants closed;
#   · an answer outside the allowlist is discarded — a model that cannot answer in the allowlist
#     is not an advisor, it is a risk.
# GARMR_ADVISOR_CMD makes the advisor injectable (tests stub it; a seat with no model sets it empty).
advise() {
  local findings="$1"
  # The road: online first (fast, and strong enough to triage at 3 a.m.), then the Allfather's own
  # 35B. `hound.advisor_online: true` must be set for the online road — an advisor is one thing, but
  # a machine that ships its own topology to a vendor by default is another.
  local primary fallback online cmd
  # The advisor's model is RESOLVED for this seat (RULES/25, plan 206 §11): a model id in a
  # shipped script is a promise the next machine cannot keep. The literal survives only as the
  # last resort when the resolver itself cannot answer.
  _am="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/model/agent-model.sh"
  _resolved=""
  [ -x "$_am" ] && _resolved="$(bash "$_am" forseti --tier strong --plain 2>/dev/null || true)"
  primary="${GARMR_ADVISOR_MODEL_NAME:-$(advise_cfg model_name "${_resolved:-opencode-go/deepseek-v4.1-flash}")}"
  fallback="${GARMR_ADVISOR_MODEL_FALLBACK:-$(advise_cfg model_fallback llama-swap/qwen3.6-35b-a3b@q4_k_xl-mtp)}"
  online="${GARMR_ADVISOR_ONLINE:-$(advise_cfg advisor_online false)}"
  if [ -n "${GARMR_ADVISOR_CMD:-}" ]; then
    cmd="$GARMR_ADVISOR_CMD"
  elif [ "$online" = "true" ]; then
    cmd="pi -p --no-session --no-tools --model $primary"
  else
    cmd="pi -p --no-session --no-tools --model $fallback"
  fi
  if [ -z "$cmd" ]; then
    printf 'bite[1]{advisor,result}:\n  "none","GARMR_ADVISOR_CMD is empty — the hound decides by rule alone (the safe default)"\n'
    return 0
  fi
  local meta answer coarse=0
  [ "$online" = "true" ] && [ -z "${GARMR_ADVISOR_CMD:-}" ] && coarse=1
  meta=$(python3 - "$findings" <<'PY'
import sys, json, os
out = []
for line in open(sys.argv[1], encoding="utf-8") if os.path.exists(sys.argv[1]) else []:
    line = line.strip()
    if not line: continue
    try: f = json.loads(line)
    except Exception: continue
    coarse = os.environ.get("GARMR_COARSE", "0") == "1"
    keep = {k: f.get(k) for k in ("class", "severity", "pid", "port", "comm", "path", "dst", "unit", "token_id") if f.get(k) is not None}
    if coarse:
        # A vendor does not need our topology: keep the SHAPE of the finding, not the map.
        if "path" in keep:
            keep["path"] = "<path:" + os.path.basename(str(keep["path"])) + ">"
        if "dst" in keep:
            parts = str(keep["dst"]).split(".")
            keep["dst"] = ".".join(parts[:2]) + ".*.*" if len(parts) == 4 else "<host>"
        if "unit" in keep:
            keep["unit"] = "<unit>"
    out.append(keep)
print(json.dumps(out))
PY
)
  [ -n "$meta" ] || return 0
  raw=""
  answer=$(printf '%s\n' "You are the hound's advisor, not its hand. From the findings below, choose AT MOST ONE bite and reply with ONE line: <bite> <target> — or exactly: none." "" "Allowed bites (nothing else exists): egress-block <dst> | listener-close <port> | stop-unit <unit> | kill-process <pid> | quarantine-file <path> | none" "" "Findings (metadata only): $meta" | timeout 120 sh -c "$cmd" 2>/dev/null | grep -Eio '^(egress-block|listener-close|stop-unit|kill-process|quarantine-file|revoke-token|none)[^\n]*' | head -1)
  raw=$(printf '%s\n' "Findings (metadata only): $meta" | timeout 120 sh -c "$cmd" 2>/dev/null | head -c 2000)
  if [ -z "$answer" ] && [ -z "${GARMR_ADVISOR_CMD:-}" ] && [ "$primary" != "$fallback" ]; then
    answer=$(printf '%s\n' "One line only: <bite> <target>, or none. Allowed: egress-block <dst> | listener-close <port> | stop-unit <unit> | kill-process <pid> | quarantine-file <path> | none." "" "Findings (metadata only): $meta" | timeout 180 pi -p --no-session --no-tools --model "$fallback" 2>/dev/null | grep -Eio '^(egress-block|listener-close|stop-unit|kill-process|quarantine-file|none)[^\n]*' | head -1)
    [ -n "$answer" ] && printf 'bite[1]{advisor,road}:\n  "fallback","the online road answered nothing — the local 35B triaged instead"\n'
  fi
  case "$answer" in
    none*) printf 'bite[1]{advisor,result}:\n  "none","the advisor declined — nothing is bitten on advice alone"\n'; return 0 ;;
    "")
      if [ -n "$(printf '%s' "$raw" | tr -d '[:space:]')" ]; then
        printf 'bite[1]{advisor,result}:\n  "discarded","the advisor answered outside the allowlist — an answer we cannot place is not advice"\n'
      else
        printf 'bite[1]{advisor,result}:\n  "none","the advisor produced nothing — the hound decides by rule alone"\n'
      fi
      return 0 ;;
    egress-block*|listener-close*|stop-unit*|kill-process*|quarantine-file*)
      printf 'bite[2]{advisor,proposal,note}:\n  "%s","still needs a WRITTEN RULE — the advisor proposes, the rules dispose"\n' "$answer" ;;
    *) printf 'bite[1]{advisor,result}:\n  "discarded","an answer outside the allowlist is not an advisor"\n' ;;
  esac
}


# ── the response fallback: an uncovered CRITICAL is put to the advisor ───────
# This is the Allfather's whole idea, and it is fenced: the advisor may propose one allowlisted
# bite; the deterministic layer still checks that the class is ARMED and still refuses without a
# written rule — the rule set stays the policy, and the model only says which armed door to close.
advisor_fallback() {
  local findings="$1"
  [ "$MODEL_MODE" = "on" ] || return 0
  local uncovered
  uncovered=$(python3 - "$findings" "$RULES" <<'PY'
import sys, json, os
findings, rules = sys.argv[1], sys.argv[2]
try:
    import yaml; d = yaml.safe_load(open(rules)) or {}
except Exception: d = {}
armed = {str(c).lower() for c in (d.get("enabled") or [])}
out = []
for line in open(findings, encoding="utf-8") if os.path.exists(findings) else []:
    line=line.strip()
    if not line: continue
    try: f=json.loads(line)
    except Exception: continue
    if str(f.get("severity","")).upper() == "CRITICAL" and str(f.get("class","")).lower() not in armed:
        out.append(f)
print(json.dumps(out))
PY
)
  [ "$uncovered" = "[]" ] || [ -z "$uncovered" ] && return 0
  local advice
  advice=$(advise "$findings" 2>/dev/null | sed -n 's/.*"\([a-z-]* [^"]*\)","still needs.*/\1/p')
  [ -n "$advice" ] || return 0
  local bite; bite=${advice%% *}
  if printf '%s\n' "$(allowlist | sed -n 's/^  "\([a-z-]*\)".*/\1/p')" | grep -qx "$bite"; then
    printf 'bite[2]{advisor,suggestion}:\n  "%s","REFUSED to act: the class is not armed in the rules file. Arm it in garmr-rules.yaml and the next pass will bite. An unarmed class is a bark, by law 1."\n' "$advice"
  fi
}

# ── the act, with the record first ────────────────────────────────────────────
runes() {  # <event> <message>
  bash "$ROOT/bin/records/runes-append.sh" garmr "$1" --message "$2" >/dev/null 2>&1 && return 0
  printf 'bite[1]{warn}: "the ledger refused the line — no bite is taken"\n' >&2
  return 1
}

contain() {
  local dry=$1 findings="${2:-$STATE/findings.jsonl}"
  local plan_out; plan_out="$(plan "$findings")"
  if [ -z "$plan_out" ]; then
    printf 'bite[1]{planned,acted}:\n  "nothing admissible","0"\n  "an unmatched finding is a BARK, never a bite"\n'
    return 0
  fi
  local n=0 acted=0
  while IFS=$'\t' read -r bite cls target undo why; do
    n=$((n + 1))
    case "$MODE" in
      off)    printf '  "%s","%s","%s","BARKED (switch: off)"\n' "$bite" "$cls" "$target" ;;
      report) printf '  "%s","%s","%s","WOULD BITE (switch: report) — undo: %s"\n' "$bite" "$cls" "$target" "$undo" ;;
      contain|hard)
        if [ "$dry" = "dry" ]; then
          printf '  "%s","%s","%s","WOULD BITE (dry-run) — undo: %s"\n' "$bite" "$cls" "$target" "$undo"
          continue
        fi
        # 1 · record the intent BEFORE the act — with the undo in the same line
        if ! runes garmr.bite-intent "bite=$bite class=$cls target=$target undo=[$undo] why=[$why] mode=$MODE"; then
          printf '  "%s","%s","%s","REFUSED: the intent could not be recorded"\n' "$bite" "$cls" "$target"; continue
        fi
        # 2 · the act — only the six allowlisted commands, never a pipeline
        result="taken"
        case "$bite" in
          egress-block)
            command -v nft >/dev/null || { result="refused: nft absent"; }
            [ "$result" = "taken" ] && { nft add rule inet garmr out_egress ip daddr "$target" drop 2>/dev/null || result="refused: nft needs root"; } ;;
          listener-close)
            command -v ufw >/dev/null || { result="refused: ufw absent"; }
            [ "$result" = "taken" ] && { ufw --force delete allow "$target/tcp" >/dev/null 2>&1 || result="refused: ufw needs root or no such rule"; } ;;
          stop-unit)
            systemctl stop "$target" >/dev/null 2>&1 && result="taken" || result="refused: systemctl needs root" ;;
          kill-process)
            kill -TERM "$target" 2>/dev/null && result="taken" || result="refused: no such pid" ;;
          quarantine-file)
            qdir="$HOME/.local/state/ymir/quarantine"; mkdir -p "$qdir"
            mv "$target" "$qdir/$(basename "$target")" 2>/dev/null && chmod 000 "$qdir/$(basename "$target")" 2>/dev/null && result="taken" || result="refused: cannot move"
            ;;
          revoke-token)
            result="refused: a token is reissued through its door, never un-revoked in place" ;;
          *) result="refused: not on the allowlist" ;;
        esac
        # 3 · record the result
        runes garmr.bite-result "bite=$bite target=$target result=$result undo=[$undo]"
        printf '  "%s","%s","%s","%s"\n' "$bite" "$cls" "$target" "$result"
        acted=$((acted + 1))
        ;;
    esac
  done <<<"$plan_out"
  printf 'bite[3]{switch,planned,acted}:\n  "%s",%s,%s\n' "$MODE" "$n" "$acted"
  [ "$MODE" = "off" ] && return 3
  return 0
}

cmd_undo() {
  local id="${1-}"
  [ -n "$id" ] || { printf 'bite[1]{error}: "undo needs the checksum (or a unique prefix) of the bite-intent rune"\n' >&2; exit 2; }
  local ledger="$H/hodd/memory/runes_audit.md"
  [ -r "$ledger" ] || { printf 'bite[1]{error}: "no ledger at %s"\n' "$ledger" >&2; exit 1; }
  local line
  line=$(grep -F "$id" "$ledger" | grep -F "garmr.bite-intent" | tail -1)
  [ -n "$line" ] || { printf 'bite[1]{error}: "no bite-intent rune matches %s"\n' "$id" >&2; exit 1; }
  local undo
  undo=$(printf '%s' "$line" | sed -n 's/.*undo=\[\(.*\)\] why=.*/\1/p')
  [ -n "$undo" ] || { printf 'bite[1]{error}: "that rune carries no undo — it cannot be un-bitten automatically"\n' >&2; exit 1; }
  case "$undo" in \#*) printf 'bite[1]{manual}: "%s"\n' "${undo#\# }"; exit 0 ;; esac
  printf 'bite[1]{undo,command}:\n  "%s","%s"\n' "$id" "$undo"
  [ "${2-}" = "--yes" ] || { printf 'bite[1]{note}: "add --yes to run it"\n'; exit 0; }
  bash -c "$undo" 2>/dev/null && runes garmr.bite-undone "rune=$id cmd=[$undo]" && printf 'bite[1]{result}: "undone"\n'
}

cmd_status() {
  printf 'garmr_bite[4]{fact,value}:\n'
  printf '  "switch","%s"\n' "$MODE"
  printf '  "rules","%s"\n' "$([ -r "$RULES" ] && echo present || echo 'absent — every finding is a BARK')"
  local bites=0
  [ -r "$H/hodd/memory/runes_audit.md" ] && bites=$(grep -c 'garmr.bite-result' "$H/hodd/memory/runes_audit.md" 2>/dev/null || true)
  printf '  "bites taken","%s"\n' "${bites:-0}"
  printf '  "state dir","%s"\n' "$STATE"
  [ "$MODE" = "off" ] && printf '  "note","the hound barks only — nothing will be contained"\n'
  return 0
}

CMD="${1-}"; shift || true
case "$CMD" in
  status) cmd_status ;;
  allowlist) allowlist ;;
  plan) plan "${1:-$STATE/findings.jsonl}" | sed 's/^/  /' ;;
  contain)
    dry=""; findings="$STATE/findings.jsonl"
    while [ $# -gt 0 ]; do case "$1" in --dry-run) dry=dry; shift ;; --findings) findings=${2-}; shift 2 ;; *) shift ;; esac; done
    contain "$dry" "$findings"; rc=$?; advisor_fallback "$findings"; exit $rc ;;
  advise) advise "${1:-$STATE/findings.jsonl}" ;;
  undo) cmd_undo "$@" ;;
  *) printf 'bite[1]{error}: "unknown command: %s" · help: "garmr-bite.sh --help"\n' "$CMD" >&2; exit 2 ;;
esac
