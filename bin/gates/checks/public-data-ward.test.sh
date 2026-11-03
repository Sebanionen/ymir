#!/usr/bin/env bash
# public-data-ward.test.sh — prove the RULES/04 ward BITES.
#
#   bin/gates/checks/public-data-ward.test.sh
#
# A ward never seen to refuse is decoration — and this one has form: until 2026-11-03 the guard that
# forbids personal data carried the operator's own name as two literal alternatives, while its third
# alternative (`$HOME`, inside a single-quoted string) never expanded and matched nothing at all. So
# this test plants one case per class and requires the refusal, and it requires the WARD ITSELF to
# carry no declared word, because RULES/04 says naming them in the guard re-creates the leak.
#
# Exit: 0 every case behaved · 1 a case did not.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GUARD="$ROOT/bin/gates/guards/public-guard.py"
WORDS=""
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
h=""; declare -f ymir_home_root >/dev/null 2>&1 && ymir_home_root h
[ -n "$h" ] && [ -r "$h/hodd/security/operator-words.txt" ] && WORDS="$h/hodd/security/operator-words.txt"

fail=0
say() { printf '%s\n' "$*"; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
plant() {  # <case> <line> <class word the finding must carry>
  printf '%s\n' "$2" >"$tmp/case.md"
  if YMIR_HOME="$tmp/nohome" python3 "$GUARD" "$tmp/case.md" 2>/dev/null | grep -q "$3"; then
    say "  ok    $1"
  else
    say "  FAIL  $1 — the ward did not refuse it"; fail=1
  fi
}

plant "a private host address" "the heart listens on 192.168.44.9"                "private address"
plant "a tailnet host"         "reach it at heartbox.tailnet.ts.net"              "tailnet host"
plant "a personal mailbox"     "write to someone.smith@gmail.com"                 "personal mailbox"
# A GUARD CONTAINS THE SHAPES IT LOOKS FOR — so the shape is BUILT here, never written: a literal
# fake token in a tracked file is refused by secret-guard (and rightly: it cannot tell mine from a
# real one), and a test that cannot be committed is a test that does not run.
fake="ghp_$(printf 'a%.0s' $(seq 1 36))"
plant "a credential shape"     "token = $fake"  "credential shape"

if [ -n "$WORDS" ]; then
  leaked=0
  while IFS= read -r w; do
    case "$w" in ''|'#'*) continue ;; esac
    if grep -qi -- "$w" "$GUARD" "$ROOT/bin/gates/guards/public-data-guard.sh" 2>/dev/null; then
      leaked=1
    fi
  done <"$WORDS"
  if [ "$leaked" = 0 ]; then say "  ok    the ward carries no declared operator word"
  else say "  FAIL  the ward names a declared operator word — that IS the leak (RULES/04)"; fail=1; fi
else
  say "  skip  no operator-words.txt on this machine — the name class was not proved here"
fi

printf 'the seat is <host>; state lives at $HOME/state; a demo address is someone@example.com\n' >"$tmp/clean.md"
if YMIR_HOME="$tmp/nohome" python3 "$GUARD" "$tmp/clean.md" >/dev/null 2>&1; then
  say "  ok    a template with placeholders passes"
else
  say "  FAIL  a clean template was refused — a ward that cries wolf gets switched off"; fail=1
fi

[ "$fail" = 0 ] && say "public-data-ward: all cases behaved" || say "public-data-ward: FAILED"
exit "$fail"
