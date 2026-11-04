#!/usr/bin/env bash
# plan-ledger-fresh.test.sh — Rule 45 at the plan ledger: a number is never taken from a stale home.
#
# The fault this locks down (2026-11-04): a seat seven commits behind origin asked for the next
# number, was handed 182, and wrote a plan — while another machine had already taken 182. Two plans,
# one number. plan.sh numbered from a directory listing and never fetched.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ok=0; bad=0
pass() { printf 'ok %s\n' "$1"; ok=$((ok+1)); }
fail() { printf 'not ok %s\n' "$1"; bad=$((bad+1)); }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export YMIR_OFFLINE=0
unset YMIR_ALLOW_STALE_LEDGER

# ── a bare remote, a home, and a second machine ───────────────────────────────
git init -q --bare --initial-branch=main "$TMP/origin.git"
git init -q --initial-branch=main "$TMP/home"
LEDGER="$TMP/home/svartalfaheim/work/projects/ymir/plans"
mkdir -p "$LEDGER"
printf '# plans\n\n| # | plan | state |\n|---|---|---|\n| 1 | [one](1-one.md) | opened |\n' > "$LEDGER/README.md"
printf '# Plan 1 - one\n' > "$LEDGER/1-one.md"
git -C "$TMP/home" add -A && git -C "$TMP/home" commit -qm "seed" 
git -C "$TMP/home" remote add origin "$TMP/origin.git"
git -C "$TMP/home" push -q -u origin main

# the OTHER machine takes number 2 and pushes it
git clone -q "$TMP/origin.git" "$TMP/other"
printf '# Plan 2 - two\n' > "$TMP/other/svartalfaheim/work/projects/ymir/plans/2-two.md"
printf '| 2 | [two](2-two.md) | opened |\n' >> "$TMP/other/svartalfaheim/work/projects/ymir/plans/README.md"
git -C "$TMP/other" add -A && git -C "$TMP/other" commit -qm "plan 2" && git -C "$TMP/other" push -q

plan() { YMIR_HOME="$TMP/home" bash "$ROOT/bin/records/plan.sh" "$@"; }

# ── 1 · reading is free while behind ──────────────────────────────────────────
out="$(plan next 2>&1)"; rc=$?
[ $rc -eq 0 ] && pass "next reports while behind (exit 0)" || fail "next refused a read (rc=$rc: $out)"

# ── 2 · TAKING a number refuses on a stale ledger ─────────────────────────────
out="$(plan new alpha --title "Alpha" 2>&1)"; rc=$?
if [ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'REFUSED'; then
  pass "new refuses from a stale ledger and says REFUSED"
else
  fail "new did not refuse from a stale ledger (rc=$rc: $out)"
fi
printf '%s' "$out" | grep -q 'pull --ff-only' \
  && pass "the refusal names the repair" || fail "the refusal names no repair"
[ -e "$LEDGER/3-alpha.md" ] && fail "a plan file was written despite the refusal" || pass "no file was written"

# ── 3 · the loud override is loud, and it works ───────────────────────────────
out="$(YMIR_ALLOW_STALE_LEDGER=1 plan new alpha --title "Alpha" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && printf '%s' "$out" | grep -qi 'warning'; then
  pass "the override works and warns"
else
  fail "the override did not work or did not warn (rc=$rc: $out)"
fi
rm -f "$LEDGER/2-alpha.md"   # the override took 2 — the very number the other machine held

# ── 4 · after a fast-forward the next number is the true one ─────────────────
git -C "$TMP/home" checkout -q -- . 2>/dev/null; git -C "$TMP/home" pull -q --ff-only
out="$(plan new beta --title "Beta" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && [ -e "$LEDGER/3-beta.md" ]; then
  pass "after --ff-only the ledger takes the true next number (3)"
else
  fail "fresh ledger did not allocate 3 (rc=$rc: $out)"
fi

# ── 5 · a home with no remote is a stated skip, not a refusal ────────────────
git -C "$TMP/home" remote remove origin
out="$(plan new gamma --title "Gamma" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && printf '%s' "$out" | grep -qi 'unverified'; then
  pass "no remote → clean skip that says UNVERIFIED"
else
  fail "no remote was not a stated skip (rc=$rc: $out)"
fi

printf '\n%s ok, %s failed\n' "$ok" "$bad"
[ "$bad" -eq 0 ]
