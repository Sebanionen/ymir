#!/usr/bin/env bash
# pi-launcher.sh — the ONE launcher generator for a pi seat.
#
# Why this door exists (measured 2026-11-05, plan 190 §4.1): two launchers for
# one shape is how a worktree killed a worker. The spawner hand-built its pi
# command in one place, `bin/seat/herdr-run.sh` built another, and the one that
# lost the `-ne` flag inherited the seat's ABSOLUTE extension tree through
# ~/.pi/agent/settings.json AND discovered the worktree's own tree under the
# working directory — so pi registered every tool twice, refused to load a
# single extension, and three errands were born dead while the dispatcher
# printed `spawned` (RULES/13: one home per extension, two load paths seats
# nobody).
#
# The one shape, and every part of it is load-bearing:
#
#   pi -ne -e <worktree>/.pi/extensions/<each>/index.ts … -e npm:<pkg> … "<brief>"
#
#   -ne     discovery OFF — the worktree's tree must not be added a second time
#   -e      every extension named ONCE, resolved from the WORKTREE, never from
#           the primary checkout the seat's settings point at
#   npm:    the packages the seat's own settings declare — discovery would have
#           carried them, and turning discovery off must not lose them
#
# Print, never guess: `print` emits the command line, `write` emits the script
# the pane will run, `extensions` emits the resolved set for a reader. A caller
# that assembles its own command line is the bug this door removes.
#
# Usage:
#   pi-launcher.sh extensions <cwd>                     # -e … lines, one per line
#   pi-launcher.sh print <cwd> [--model M] [--thinking E] [--brief F]
#   pi-launcher.sh write <cwd> <out-script> [--model M] [--thinking E] [--brief F]
#
# `print`/`write` refuse when <cwd> holds no `.pi/extensions` tree: a pi seat
# with no extensions is not the house's seat, and a silent empty set is exactly
# how a worker was seated with none of the doors open.
#
# Exit: 0 ok · 1 the cwd is not a seat tree · 2 usage.
set -u
VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1-}" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help|"") sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

shell_quote() {  # <string> — single-quote for the shell that will read it
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# The worktree's own tree first, then the packages the seat declares. A
# directory extension is its index.ts (pi's layout, RULES/13); a flat file is
# itself. README.md and lib/ are not extensions.
ext_args() {  # <cwd>
  local cwd=$1 p b pkg
  for p in "$cwd"/.pi/extensions/*; do
    [ -e "$p" ] || continue
    b="$(basename "$p")"
    case "$b" in README.md|lib) continue ;; esac
    if [ -d "$p" ]; then
      [ -f "$p/index.ts" ] && printf -- '-e %s\n' "$(shell_quote "$p/index.ts")"
      [ -f "$p/index.js" ] && [ ! -f "$p/index.ts" ] && printf -- '-e %s\n' "$(shell_quote "$p/index.js")"
    elif [ -f "$p" ]; then
      case "$b" in *.ts|*.js) printf -- '-e %s\n' "$(shell_quote "$p")" ;; esac
    fi
  done
  # The packages in the seat's settings, carried explicitly because discovery is
  # off. `packages` is the only key that names an extension pi loads from npm.
  # YMIR_PI_SETTINGS names the file (default: the harness's own settings), so a
  # seat whose packages live elsewhere — and a test that must be deterministic —
  # can say where they are instead of inheriting one machine's list.
  local settings="${YMIR_PI_SETTINGS:-$HOME/.pi/agent/settings.json}"
  if [ -f "$settings" ]; then
    while IFS= read -r pkg; do
      [ -n "$pkg" ] || continue
      printf -- '-e %s\n' "$(shell_quote "$pkg")"
    done < <(PI_SETTINGS="$settings" python3 -c 'import json,os
try:
    d=json.load(open(os.environ["PI_SETTINGS"]))
except Exception:
    raise SystemExit(0)
for x in d.get("packages") or []:
    print(x)' 2>/dev/null)
  fi
}

count_exts() {  # <cwd> — how many pins the WORKTREE yields (0 = not a seat tree)
  # npm packages are the seat's settings, not this tree's doors: counting them
  # would let a worktree with no extensions of its own pass as a seat.
  ext_args "$1" | grep -cF "/.pi/extensions/" || true
}

build() {  # <cwd> <model> <thinking> <brief> — the command line, no `exec`
  local cwd=$1 model=$2 thinking=$3 brief=$4 out= line
  out="pi"
  [ -n "$model" ] && out="$out --model $(shell_quote "$model")"
  [ -n "$thinking" ] && out="$out --thinking $(shell_quote "$thinking")"
  out="$out -ne"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    out="$out $line"
  done < <(ext_args "$cwd")
  if [ -n "$brief" ]; then
    out="$out \"\$(cat $(shell_quote "$brief"))\""
  fi
  printf '%s' "$out"
}

CMD="${1-}"; shift || true
case "$CMD" in
  extensions)
    CWD="${1-}"; [ -n "$CWD" ] || { printf 'error: extensions needs a cwd\n' >&2; exit 2; }
    ext_args "$CWD"
    ;;
  print|write)
    CWD="${1-}"; shift || true
    OUT=""
    if [ "$CMD" = write ]; then OUT="${1-}"; shift || true; fi
    MODEL=""; THINKING=""; BRIEF=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --model) MODEL="${2-}"; shift 2 ;;
        --thinking) THINKING="${2-}"; shift 2 ;;
        --brief) BRIEF="${2-}"; shift 2 ;;
        *) printf 'error: unknown flag %s\n' "$1" >&2; exit 2 ;;
      esac
    done
    [ -n "$CWD" ] || { printf 'error: %s needs a cwd\n' "$CMD" >&2; exit 2; }
    [ "$CMD" = print ] || [ -n "$OUT" ] || { printf 'error: write needs an output script\n' >&2; exit 2; }
    N="$(count_exts "$CWD")"
    if [ "$N" -lt 1 ]; then
      printf 'pi-launcher: %s holds no .pi/extensions tree — a pi seat must name its extensions (RULES/13)\n' "$CWD" >&2
      exit 1
    fi
    LINE="$(build "$CWD" "$MODEL" "$THINKING" "$BRIEF")"
    if [ "$CMD" = print ]; then
      printf '%s\n' "$LINE"
    else
      {
        printf '#!/usr/bin/env bash\n'
        printf '# written by bin/seat/pi-launcher.sh — do not hand-edit\n'
        printf 'set -eu\n'
        printf 'cd %s\n' "$(shell_quote "$CWD")"
        printf 'exec %s\n' "$LINE"
      } >"$OUT"
      chmod +x "$OUT"
      printf '%s\n' "$OUT"
    fi
    ;;
  *)
    printf 'error: unknown command %s\nhelp: pi-launcher.sh extensions|print|write <cwd> …\n' "$CMD" >&2
    exit 2
    ;;
esac
