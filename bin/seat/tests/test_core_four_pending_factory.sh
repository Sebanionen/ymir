#!/usr/bin/env bash
# The ward for the three near-loop doors: core four, pending, and the factory preset.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
ok=0; fail=0
t() { local n=$1; shift; if "$@" >/tmp/.t.$$ 2>&1; then ok=$((ok+1)); printf 'ok   %s\n' "$n"; else fail=$((fail+1)); printf 'FAIL %s\n' "$n"; head -3 /tmp/.t.$$; fi; }

t "core-four names four dials" bash -c "bash $root/bin/seat/core-four.sh | grep -q 'core_four\[4\]'"
t "core-four json parses" bash -c "bash $root/bin/seat/core-four.sh --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert {\"model\",\"context\",\"prompt\",\"tools\"} <= set(d)'"
t "pending counts what waits" bash -c "bash $root/bin/seat/pending.sh | grep -qE 'pending\[[0-9]+\]'"
t "pending json parses" bash -c "bash $root/bin/seat/pending.sh --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert \"items\" in d'"
t "factory copies, never guesses" bash -c "T=\$(mktemp -d); bash $root/bin/desktop/factory-new.sh smoke --out \$T >/dev/null && grep -q 'name: smoke' \$T/smoke.yaml"
t "factory refuses a second write" bash -c "T=\$(mktemp -d); bash $root/bin/desktop/factory-new.sh smoke --out \$T >/dev/null; ! bash $root/bin/desktop/factory-new.sh smoke --out \$T"
t "factory refuses a bad name" bash -c "! bash $root/bin/desktop/factory-new.sh 'Bad Name' --out /tmp"
t "context reads the live session" bash -c "bash $root/bin/seat/context.sh | grep -q 'context\[8\]'"
t "context json parses and matches the window" bash -c "bash $root/bin/seat/context.sh --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"window\"]>0 and d[\"context_used\"]>0 and 0<=d[\"percent\"]<=100, d'"
t "context verdict is one of four" bash -c "bash $root/bin/seat/context.sh --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"verdict\"] in (\"room to work\",\"past the auto threshold\",\"near the window — compact now\") or d[\"verdict\"].startswith(\"TRUNCATED\"), d[\"verdict\"]'"
t "context refuses an unreadable session" bash -c "! bash $root/bin/seat/context.sh --session /nope.jsonl"
t "working-now is counted" bash -c "bash $root/bin/seat/core-four.sh --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"working_now\"][\"panes\"]>=0'"
t "factory refuses an unfilled door list" bash -c "T=\$(mktemp -d); bash $root/bin/desktop/factory-new.sh smoke --out \$T >/dev/null; ! bash $root/bin/desktop/factory-check.sh \$T/smoke.yaml"
t "factory-check names the refusal" bash -c "T=\$(mktemp -d); bash $root/bin/desktop/factory-new.sh smoke --out \$T >/dev/null; bash $root/bin/desktop/factory-check.sh \$T/smoke.yaml 2>&1 | grep -q 'unfilled placeholder'"
printf 'near-loop doors: %s ok / %s fail\n' "$ok" "$fail"
rm -f /tmp/.t.$$
[ "$fail" = 0 ]
