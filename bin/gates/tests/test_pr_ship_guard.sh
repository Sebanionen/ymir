#!/usr/bin/env bash
# test_pr_ship_guard.sh — proves the ship door judges the PR and not the branch.
#
# The cases are the whole law of plan 203 §14: a login in the smith registry is refused as a PR
# author and the refusal names the reviewer's door; another hand's login passes; a registry read
# from the hoard works as well as the env; and no registry at all is a clean skip that says so,
# never a silent pass (RULES/25).
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
guard="$here/../guards/pr-ship-guard.sh"
pass=0; fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

echo "test_pr_ship_guard"

out=""; rc=0
judge() { out="$(eval "$@" 2>&1)"; rc=$?; }

# 1 · a smith's login from the env registry — refused, and the remedy is named
judge "env YMIR_SMITH_IDENTITIES='smithbot,another-bot' bash '$guard' --author smithbot"
[ "$rc" = 1 ] && ok "a smith's login is refused (rc=1)" || bad "expected rc=1 for a smith login, got $rc"
case "$out" in *"the reviewer ships"*) ok "the refusal names the reviewer's door" ;;
  *) bad "the refusal did not name the reviewer's door" ;; esac
case "$out" in *"a smith's identity"*) ok "the refusal names the identity it refused" ;;
  *) bad "the refusal did not name the identity" ;; esac

# 2 · a reviewer's login — passes
judge "env YMIR_SMITH_IDENTITIES='smithbot' bash '$guard' --author zerwiz"
[ "$rc" = 0 ] && ok "another hand's login passes" || bad "expected rc=0 for a reviewer login, got $rc"

# 3 · the registry read from the hoard, with a comment line
tmproot="$(mktemp -d)"; mkdir -p "$tmproot/hodd/identity"
printf '# the smiths\nsmithbot   # the first one\n\n' > "$tmproot/hodd/identity/smiths.txt"
judge "env -u YMIR_SMITH_IDENTITIES YMIR_HOME='$tmproot' bash '$guard' --author smithbot"
[ "$rc" = 1 ] && ok "the hoard registry is read (comments and blanks ignored)" \
  || bad "the hoard registry was not read: rc=$rc"

# 4 · no registry anywhere — a clean skip that names its reason
judge "env -u YMIR_SMITH_IDENTITIES YMIR_HOME='$tmproot/empty' bash '$guard' --author smithbot"
[ "$rc" = 0 ] && ok "no registry is not a failure" || bad "no registry should skip, got rc=$rc"
case "$out" in *SKIP*"no smith registry"*) ok "the skip names its reason" ;;
  *) bad "the skip did not name its reason" ;; esac

rm -rf "$tmproot"

printf 'test_pr_ship_guard: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ] || exit 1
