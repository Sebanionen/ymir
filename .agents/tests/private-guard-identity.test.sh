#!/usr/bin/env bash
# private-guard-identity — assert the ward FAILS on personal data.
#
# Rule 04 (appended 2026-10-01): a person's identity and topology are personal
# data whether or not they are a secret. The wards previously scanned only
# credential VALUES (secret-guard) and private PATHS (private-guard); nothing
# scanned content for identity, so operator data reached a public remote with
# every gate green.
#
# A test that cannot fail on the leak is not a test. This one plants the leak.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$ROOT/bin/gates/guards/private-guard.sh"
rc=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; rc=1; }

[ -x "$GUARD" ] || { bad "guard present and executable"; exit 1; }
ok "guard present and executable"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Plant each class of personal data as a tracked file and demand a block.
plant() {
  local label="$1" content="$2" f
  f="probe-$3.md"
  printf '%s\n' "$content" >"$ROOT/$f"
  git -C "$ROOT" add -- "$f" 2>/dev/null
  if out="$(bash "$GUARD" 2>&1)"; then
    bad "blocks $label"
    printf '     guard passed a file containing %s\n' "$label" >&2
  else
    case "$out" in
      *"identity/topology"*) ok "blocks $label" ;;
      *) bad "blocks $label (wrong reason — the path rule, not the identity rule)"
         printf '     %s\n' "$out" | head -3 >&2 ;;
    esac
  fi
  git -C "$ROOT" rm -f --cached "$f" >/dev/null 2>&1
  rm -f "$ROOT/$f"
}

plant "an operator home path"   'log in as /home/realoperator/x'      home
plant "a tailnet hostname"      'the heart is h1.<host>.tailnet.ts.net'         tailnet
plant "a CGNAT address"         'bind 100.64.0.1'               cgnat

# The blessed public way must PASS: a placeholder teaches without naming.
f="probe-public.md"
printf '%s\n' 'state lives at $HOME/state; the seat is <host>; the card is <gpu>.' >"$ROOT/$f"
git -C "$ROOT" add -- "$f" 2>/dev/null
if bash "$GUARD" >/dev/null 2>&1; then
  ok "allows the public placeholder form"
else
  bad "allows the public placeholder form"
fi
git -C "$ROOT" rm -f --cached "$f" >/dev/null 2>&1
rm -f "$ROOT/$f"

# A synthetic fixture is not a person.
f="probe.test.sh"
printf '%s\n' '#!/bin/sh' 'dir=/home/alice/project' >"$ROOT/$f"
git -C "$ROOT" add -- "$f" 2>/dev/null
if bash "$GUARD" >/dev/null 2>&1; then
  ok "exempts synthetic test fixtures"
else
  bad "exempts synthetic test fixtures"
fi
git -C "$ROOT" rm -f --cached "$f" >/dev/null 2>&1
rm -f "$ROOT/$f"

# The tenant-doc rule judges a company SHELF or a tenant DOCUMENT — never the bare word.
# Measured 2026-10-11: the old pattern matched the bare word with any extension, so it bit
# `bin/vault/confidential.sh` (Rule 16's own door) and `docs/features/confidential-session.md`
# (Rule 14's public feature doc) and held the compliance row red.
mkdir -p "$ROOT/qprobe/wiki"
for probe in 'qprobe/confidential.sh:#!/bin/sh|# the confidential-session door (Rule 16)' \
             'qprobe/confidential-session.md:# the user-facing how-to for Rule 16' ; do
  f="${probe%%:*}"
  printf '%s\n' "${probe#*:}" >"$ROOT/$f"
  git -C "$ROOT" add -- "$f" 2>/dev/null
  if bash "$GUARD" >/dev/null 2>&1; then
    ok "allows a fair file: $f"
  else
    bad "allows a fair file: $f (the bare word is not company knowledge)"
  fi
  git -C "$ROOT" rm -f --cached "$f" >/dev/null 2>&1
  rm -f "$ROOT/$f"
done

# ...and still bites the tenant SHAPE: a company shelf, and a document named for one.
for probe in 'qprobe/wiki/notes.md:a company shelf' \
             'qprobe/strategy-2026.md:a tenant document' ; do
  f="${probe%%:*}" label="${probe#*:}"
  printf '%s\n' "$label" >"$ROOT/$f"
  git -C "$ROOT" add -- "$f" 2>/dev/null
  if out="$(bash "$GUARD" 2>&1)"; then
    bad "blocks $label ($f)"
  else
    case "$out" in
      *"tenant/company document"*) ok "blocks $label ($f)" ;;
      *) bad "blocks $label — wrong reason"
         printf '     %s\n' "$out" | head -2 >&2 ;;
    esac
  fi
  git -C "$ROOT" rm -f --cached "$f" >/dev/null 2>&1
  rm -f "$ROOT/$f"
done
rmdir "$ROOT/qprobe/wiki" "$ROOT/qprobe" 2>/dev/null

# The guard itself must never name the operator.
if grep -Eq 'tailefab|zwrtzk|100\.69\.' "$GUARD" 2>/dev/null; then
  bad "the guard names no operator value"
else
  ok "the guard names no operator value"
fi

exit "$rc"