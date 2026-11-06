#!/usr/bin/env bash
# test_event_trigger.sh — a smithy may be started by a person, the clock, or an
# event, and NOTHING else may start it by surprise.
#
# The three laws this proves, plus the refusals that make them worth anything:
#
#   1. a config with no `trigger:` is MANUAL — absence is not a default that runs
#   2. an event no smithy claims is REFUSED BY NAME — never silence, never a zero
#   3. `--install-cron` is IDEMPOTENT — a second run writes nothing
#
# and the refusals: a cron row with no role gate, an expression the scheduler
# cannot express, a mode that is not one of the three, a half-armed trigger, and
# a withdrawn trigger whose row must not keep firing.
#
# Usage: test_event_trigger.sh
# Exit: 0 all pass · 1 a failure.
set -u
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/../../.." && pwd)
DOOR="$ROOT/bin/time/event-trigger.sh"
RESOLVER="$ROOT/bin/time/event-trigger-resolve.py"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export BROKK_STATE_OVERRIDE="$TMP/state"
export SMIDJA_REPO_ROOT="$TMP/project"
export SMIDJA_CONFIGS=""
mkdir -p "$SMIDJA_REPO_ROOT" "$BROKK_STATE_OVERRIDE" "$TMP/conf" "$TMP/chain" "$TMP/requests"
printf '#!/usr/bin/env -S uv run\nprint("chain")\n' >"$TMP/chain/smidja_probe.py"
printf 'do the nightly thing\n' >"$TMP/requests/nightly.md"

pass=0; fail=0
ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; return 0; }

# want <0|1> <why> <cmd...> — SMIDJA_CONFIGS is already exported by the caller
want() {
  local wantrc=$1 why=$2; shift 2
  local rc=0
  "$@" >"$TMP/out" 2>"$TMP/err" || rc=$?
  if [ "$rc" = "$wantrc" ]; then ok "$why"; else
    bad "$why" "expected rc=$wantrc got rc=$rc · out=$(head -3 "$TMP/out" | tr '\n' ' ') err=$(head -3 "$TMP/err" | tr '\n' ' ')"
  fi
}
scan_of() { export SMIDJA_CONFIGS=$1; python3 "$RESOLVER" scan; }

# a smithy whose config says nothing about triggers
cat >"$TMP/conf/quiet.yaml" <<'YAML'
defaults:
  coding_agent: pi
agents:
  - name: scout
YAML

# one the clock may start, one an event may start
cat >"$TMP/conf/nightly.yaml" <<YAML
trigger:
  mode: cron
  role: dev
  cron: "0 6 * * *"
  chain: $TMP/chain/smidja_probe.py
  prompt: $TMP/requests/nightly.md
YAML
cat >"$TMP/conf/audit.yaml" <<YAML
trigger:
  mode: event
  event: nightly-audit
  chain: $TMP/chain/smidja_probe.py
  prompt: $TMP/requests/nightly.md
YAML

printf 'event-trigger, the smithy s start line\n'

# ── 1 · absence is manual ─────────────────────────────────────────────────────
export SMIDJA_CONFIGS="$TMP/conf/quiet.yaml"
want 0 "a config with no trigger: is scanned, not skipped" python3 "$RESOLVER" scan
[ "$(cut -f3 "$TMP/out")" = "manual" ] && ok "the mode column says manual" \
  || bad "the mode column says manual" "$(cut -f3 "$TMP/out")"

want 0 "--list reports a person as the trigger" "$DOOR" --list
grep -q '"a person"' "$TMP/out" && ok "--list names the human" || bad "--list names the human" "$(cat "$TMP/out")"

want 1 "a manual smithy is not started by an event" "$DOOR" nightly-audit --dry-run
grep -q 'no smithy claims this event' "$TMP/err" && ok "the refusal is a named refusal" \
  || bad "the refusal is a named refusal" "$(cat "$TMP/err")"

# ── 2 · an unclaimed event is refused by name ─────────────────────────────────
export SMIDJA_CONFIGS="$TMP/conf/audit.yaml"
want 1 "an event no smithy claims is refused" "$DOOR" deploy-friday --dry-run
grep -q 'deploy-friday' "$TMP/err" && ok "the refusal names the event asked for" \
  || bad "the refusal names the event asked for" "$(cat "$TMP/err")"
grep -q 'nightly-audit' "$TMP/err" && ok "the refusal lists the events that ARE claimed" \
  || bad "the refusal lists the events that ARE claimed" "$(cat "$TMP/err")"

want 0 "a claimed event picks its smithy" "$DOOR" nightly-audit --dry-run
grep -q 'would-run' "$TMP/out" && ok "the claim resolves to a command" || bad "would-run appears" "$(cat "$TMP/out")"
grep -q "$TMP/conf/audit.yaml" "$TMP/out" && ok "the claiming config is named" \
  || bad "the claiming config is named" "$(cat "$TMP/out")"

cp "$TMP/conf/audit.yaml" "$TMP/conf/audit2.yaml"
export SMIDJA_CONFIGS="$TMP/conf/audit.yaml:$TMP/conf/audit2.yaml"
want 0 "two claimants are two launches" "$DOOR" nightly-audit --dry-run
case "$(head -1 "$TMP/out")" in
  trigger\[2\]*) ok "both claimants are reported" ;;
  *) bad "both claimants are reported" "$(head -1 "$TMP/out")" ;;
esac
rm -f "$TMP/conf/audit2.yaml"

# ── 3 · --install-cron is idempotent ─────────────────────────────────────────
CRON="$TMP/cron.yaml"
printf '# the operator own schedule\n@heart 07:00 bin/time/nornir-job-daily-briefing.sh\n' >"$CRON"
export SMIDJA_CONFIGS="$TMP/conf/nightly.yaml"
want 0 "install-cron writes the row" "$DOOR" --install-cron --cron-file "$CRON"
grep -q 'event-trigger.sh --run' "$CRON" && ok "the row calls this door" || bad "the row calls this door" "$(cat "$CRON")"
grep -q '^@dev 06:00 ' "$CRON" && ok "the row carries the declared role and shape" \
  || bad "the row carries the declared role and shape" "$(cat "$CRON")"
grep -q 'nornir-job-daily-briefing' "$CRON" && ok "the operator's own rows survive" \
  || bad "the operator's own rows survive" "$(cat "$CRON")"
cp "$CRON" "$TMP/cron.first"

want 0 "a second install-cron is a clean pass" "$DOOR" --install-cron --cron-file "$CRON"
grep -q 'unchanged' "$TMP/out" && ok "the second run says unchanged" || bad "the second run says unchanged" "$(cat "$TMP/out")"
cmp -s "$CRON" "$TMP/cron.first" && ok "the file is byte-identical after a second run" \
  || bad "the file is byte-identical after a second run" "$(diff "$TMP/cron.first" "$CRON" | head -5)"
[ "$(grep -c 'event-trigger.sh --run' "$CRON")" = 1 ] && ok "exactly one row, not two" \
  || bad "exactly one row, not two" "$(grep -c 'event-trigger.sh --run' "$CRON")"

# a trigger that is turned off must not keep firing
export SMIDJA_CONFIGS="$TMP/conf/quiet.yaml"
want 0 "withdrawing the trigger is a clean pass" "$DOOR" --install-cron --cron-file "$CRON"
grep -q 'event-trigger.sh --run' "$CRON" && bad "a withdrawn trigger leaves no row" "$(cat "$CRON")" \
  || ok "a withdrawn trigger leaves no row"
grep -q 'nornir-job-daily-briefing' "$CRON" && ok "the operator's rows survive the withdrawal" \
  || bad "the operator's rows survive the withdrawal" "$(cat "$CRON")"

# ── the refusals that make the above worth anything ──────────────────────────
no_role="$TMP/conf/norole.yaml"
cat >"$no_role" <<YAML
trigger:
  mode: cron
  cron: "0 6 * * *"
  chain: $TMP/chain/smidja_probe.py
  prompt: $TMP/requests/nightly.md
YAML
export SMIDJA_CONFIGS="$no_role"
want 1 "cron with no role gate is refused, never installed ungated" "$DOOR" --install-cron --cron-file "$CRON"
{ cat "$TMP/out" "$TMP/err"; } | grep -q 'names no role' && ok "the refusal says why" \
  || bad "the refusal says why" "$(cat "$TMP/out")"

monthly="$TMP/conf/monthly.yaml"
cat >"$monthly" <<YAML
trigger:
  mode: cron
  role: dev
  cron: "0 6 1 * *"
  chain: $TMP/chain/smidja_probe.py
  prompt: $TMP/requests/nightly.md
YAML
export SMIDJA_CONFIGS="$monthly"
want 1 "a monthly cron expression is refused, not installed dead" "$DOOR" --install-cron --cron-file "$CRON"
grep -q 'cannot become a row' "$TMP/out" && ok "the refusal names the expression" \
  || bad "the refusal names the expression" "$(cat "$TMP/out")"

odd="$TMP/conf/odd.yaml"
printf 'trigger: sometimes\nagents:\n  - name: scout\n' >"$odd"
scan_of "$odd" >"$TMP/out"
grep -q 'is not one of manual|cron|event' "$TMP/out" && ok "an unknown mode is a named fault" \
  || bad "an unknown mode is a named fault" "$(cat "$TMP/out")"

halfway="$TMP/conf/halfway.yaml"
printf 'trigger:\n  mode: event\n' >"$halfway"
scan_of "$halfway" >"$TMP/out"
grep -q 'names no event' "$TMP/out" && ok "an event mode with no event is a named fault" \
  || bad "an event mode with no event is a named fault" "$(cat "$TMP/out")"

# a fault stops the door: it never launches the healthy half while guessing at the ill one
export SMIDJA_CONFIGS="$TMP/conf/audit.yaml:$halfway"
want 1 "a faulty config stops the whole door" "$DOOR" nightly-audit --dry-run
grep -q 'refusing to start anything' "$TMP/err" && ok "the door says it is refusing" \
  || bad "the door says it is refusing" "$(cat "$TMP/err")"

# ── the clock: a named zone is honoured, not assumed ─────────────────────────
export SMIDJA_CONFIGS="$TMP/conf/nightly.yaml"
want 0 "a row is written with no timezone named" "$DOOR" --install-cron --cron-file "$CRON" --create
grep -q '^@dev 06:00 ' "$CRON" && ok "an unnamed timezone is this seat's own clock" \
  || bad "an unnamed timezone is this seat's own clock" "$(cat "$CRON")"

utc="$TMP/conf/utc.yaml"
cat >"$utc" <<YAML
trigger:
  mode: cron
  role: dev
  cron: "0 6 * * *"
  timezone: UTC
  chain: $TMP/chain/smidja_probe.py
  prompt: $TMP/requests/nightly.md
YAML
export SMIDJA_CONFIGS="$utc"
want 0 "a named timezone still yields one row" "$DOOR" --install-cron --cron-file "$CRON" --create
want_shape=$(date -d "@$(TZ=UTC date -d 'today 06:00:00' +%s)" +%H:%M)
if [ "$want_shape" = "06:00" ]; then
  ok "this seat is UTC — 06:00 UTC is 06:00 here"
else
  grep -q "^@dev $want_shape " "$CRON" && ok "06:00 UTC is written as $want_shape on this seat's clock" \
    || bad "06:00 UTC is written as $want_shape on this seat's clock" "$(cat "$CRON")"
fi

# ── nothing is armed by the shipped default ──────────────────────────────────
export SMIDJA_CONFIGS=""
python3 "$RESOLVER" scan >"$TMP/scan" 2>&1
while IFS=$'\t' read -r _cfg _root mode _rest; do
  case "$mode" in
    cron|event) bad "the checkout ships an armed trigger: $_cfg" ;;
  esac
done <"$TMP/scan"
ok "no smithy in this checkout is armed by default"

# ── one shape, not two ────────────────────────────────────────────────────────
# A second file that restates `trigger:` is a second truth, and the two disagree
# the first time one of them is edited. Only a smithy config (the template
# included) may carry the block at column zero.
drift=""
while IFS= read -r path; do
  case "$path" in
    *smidja.config.yaml|*smidja_*_config/*) continue ;;
  esac
  grep -q '^trigger:' "$ROOT/$path" 2>/dev/null && drift="$drift $path"
done <<EOF
$(cd "$ROOT" && git ls-files '*.yaml' '*.yml' 2>/dev/null)
EOF
[ -z "$drift" ] && ok "no second trigger shape in the tree" \
  || bad "no second trigger shape in the tree" "also carries trigger:: $drift"

printf '\n%s passed · %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ] || exit 1
exit 0
