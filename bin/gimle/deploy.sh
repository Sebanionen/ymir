#!/usr/bin/env bash
# deploy.sh — put a merged tree on the desk host, and prove which commit is running.
#
#   bin/gimle/deploy.sh            deploy the merged tree, restart the three units, verify each door
#   bin/gimle/deploy.sh --check    report the running commit against origin/main; change nothing
#   bin/gimle/deploy.sh --help
#
# The Gimlé suite runs on one machine (the heart). Until this door existed, deploying it meant a
# human copying files with scp — which is how the desk on the heart came to be newer than the tree,
# with .bak- files for history (2026-11-02). A deployment is not a version: this makes the running
# code a checkout of the merged tree, so `git log` answers "what is deployed" and the answer is
# checkable from either end.
#
# The same verb on every role (RULES/25): if the checkout and the units are on THIS machine, the work
# happens locally; otherwise it goes over ssh to the host named by GIMLE_DESK_SSH. A seat that has
# neither says SKIP with the reason — it never guesses, and it never pretends a copy is a checkout.
#
# Configuration (all resolved, never hardcoded — RULES/07):
#   $YMIR_HOME/config/gimle-desktop.env   GIMLE_DESK_SSH · GIMLE_DESK_DIR (the desk's run directory)
#   GIMLE_SRC_DIR    the merged-tree checkout   (default <run parent>/src/ymir)
#   GIMLE_RUN_DIR    the desk's run directory   (default GIMLE_DESK_DIR, else the local default)
#   GIMLE_BRANCH     the branch to deploy       (default main)
#   GIMLE_UNITS      the units to restart       (default "gimle-desk gimle-mcp gimle-share")
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
home=""
declare -f ymir_home_root >/dev/null 2>&1 && ymir_home_root home 2>/dev/null
[ -n "$home" ] || home="${YMIR_HOME:-}"

conf="${home:+$home/config/gimle-desktop.env}"
[ -n "$conf" ] && [ -r "$conf" ] && . "$conf"

# GIMLE_DESK_DIR in gimle-desktop.env names the desk's DATA shelf (the projector writes there), not the
# run directory, so it is deliberately not reused here — the run directory is resolved on the machine
# that runs the units, below, where $HOME means that machine's home and not this seat's.
RUN_DIR="${GIMLE_RUN_DIR:-}"
SRC_DIR="${GIMLE_SRC_DIR:-}"
BRANCH="${GIMLE_BRANCH:-main}"
UNITS="${GIMLE_UNITS:-gimle-desk gimle-mcp gimle-share}"
FILES="desk.py mcp-read.py plane_reader.py share-scene.py"

action="deploy"
case "${1:-}" in
  -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --check) action="check" ;;
  ""|--deploy) ;;
  *) printf 'error: unknown action %s\nhelp: deploy.sh [--check]\n' "$1" >&2; exit 2 ;;
esac

# ── where the work happens ────────────────────────────────────────────────────
# Local when the checkout is here AND this seat runs the units; otherwise the door to the heart.
run() {  # run a command here, or over the door
  if [ "$where" = "local" ]; then bash -c "$1"; else ssh -o BatchMode=yes "$target" "$1"; fi
}

if command -v systemctl >/dev/null 2>&1 &&
   systemctl --user list-unit-files 2>/dev/null | grep -q '^gimle-desk\.service'; then
  where="local"; target=""
elif [ -n "${GIMLE_DESK_SSH:-}" ]; then
  where="door"; target="$GIMLE_DESK_SSH"
else
  printf 'SKIP\tthe desk is neither here nor reachable\ta seat that does not run the units needs GIMLE_DESK_SSH in %s\n' \
    "${conf:-$home/config/gimle-desktop.env}"
  exit 0
fi

# The paths are resolved on the machine that runs the units, so $HOME is that machine's home.
[ -n "$RUN_DIR" ] || RUN_DIR=$(run 'printf %s "$HOME/gimle/desk"' | tr -d '[:space:]')
[ -n "$SRC_DIR" ] || SRC_DIR=$(run 'printf %s "$HOME/gimle/src/ymir"' | tr -d '[:space:]')

# ── check: what is running, against what is merged ────────────────────────────
running=$(run "git -C '$SRC_DIR' rev-parse --short HEAD 2>/dev/null" | tr -d '[:space:]')
have_checkout=$(run "test -d '$SRC_DIR/.git' && echo yes || echo no")

if [ "${have_checkout//[[:space:]]/}" != "yes" ]; then
  printf 'FAIL\tno merged-tree checkout on the %s\tthere is no %s — the running code is a copy, not a version\n' \
    "$where" "$SRC_DIR"
  printf 'help\tclone the tree once: git clone --branch %s <remote> %s\n' "$BRANCH" "$SRC_DIR"
  exit 1
fi

run "git -C '$SRC_DIR' fetch -q origin '$BRANCH'" || {
  printf 'FAIL\tthe checkout could not fetch\tgit -C %s fetch origin %s failed on the %s\n' "$SRC_DIR" "$BRANCH" "$where"
  exit 1
}
merged=$(run "git -C '$SRC_DIR' rev-parse --short 'origin/$BRANCH'" | tr -d '[:space:]')

if [ "$action" = "check" ]; then
  if [ "$running" = "$merged" ]; then
    printf 'deployed\t%s\t%s\tthe %s runs the merged tree\n' "$running" "$merged" "$where"
    exit 0
  fi
  printf 'STALE\trunning=%s merged=%s\tthe %s is behind origin/%s — run deploy.sh\n' \
    "$running" "$merged" "$where" "$BRANCH"
  exit 1
fi

# ── deploy: the merged tree becomes the running code ─────────────────────────
run "git -C '$SRC_DIR' checkout -q '$BRANCH' && git -C '$SRC_DIR' reset -q --hard 'origin/$BRANCH'" || {
  printf 'FAIL\tthe checkout could not be moved to origin/%s\tgit -C %s reset --hard origin/%s failed\n' \
    "$BRANCH" "$SRC_DIR" "$BRANCH"
  exit 1
}
now=$(run "git -C '$SRC_DIR' rev-parse --short HEAD" | tr -d '[:space:]')

# The run directory holds the private material (etc/, data/); only the code is linked, so a deploy
# can never overwrite a token or a record. Each link is verified before any unit is touched.
for f in $FILES; do
  out=$(run "ln -sfn '$SRC_DIR/bin/gimle/$f' '$RUN_DIR/$f' && readlink -f '$RUN_DIR/$f'")
  case "$out" in
    */bin/gimle/"$f") ;;
    *) printf 'FAIL\t%s did not link into the checkout\treadlink said: %s\n' "$f" "${out:-nothing}"; exit 1 ;;
  esac
done

# A file that will not parse is not deployed — the unit would start and die, which reads as "up".
for f in $FILES; do
  run "python3 -c 'import ast,sys;ast.parse(open(sys.argv[1]).read())' '$RUN_DIR/$f'" ||
    { printf 'FAIL\t%s does not parse\tthe link is in place but the unit was left alone\n' "$f"; exit 1; }
done

run "systemctl --user restart $UNITS" || {
  printf 'FAIL\tthe units did not restart\t%s\n' "$UNITS"; exit 1; }
sleep 3

# Every door is proved by what it answers, not by what systemd says it is.
fail=0
for probe in "8487 / gimle-desk" "8489 /health gimle-mcp" "8490 /health gimle-share"; do
  set -- $probe; port="$1"; path="$2"; unit="$3"
  code=$(run "curl -s -o /dev/null -w '%{http_code}' -m 6 http://127.0.0.1:$port$path" | tr -d '[:space:]')
  state=$(run "systemctl --user is-active $unit" | tr -d '[:space:]')
  printf '%-12s :%-5s http=%s unit=%s\n' "$unit" "$port" "${code:-000}" "${state:-unknown}"
  [ "$code" = "200" ] || fail=1
  [ "$state" = "active" ] || fail=1
done

if [ "$fail" -ne 0 ]; then
  printf 'FAIL\ta door did not answer after the deploy\tcommit %s is linked; check: systemctl --user status %s\n' \
    "$now" "$UNITS"
  exit 1
fi

printf 'deployed\t%s\t%s\tthree doors answered 200; the %s runs origin/%s\n' \
  "$now" "$SRC_DIR" "$where" "$BRANCH"
