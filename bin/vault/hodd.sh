#!/usr/bin/env bash
# hodd.sh — the Allfather's private hoard: path, init, ls, load, tenant.
#
#   bin/vault/hodd.sh path                 # the Hoard root
#   bin/vault/hodd.sh init                 # create the layout
#   bin/vault/hodd.sh ls                   # what the Hoard holds (names, not contents)
#   bin/vault/hodd.sh load secrets/platform.env   # source a hoard env (quoted, safely)
#   eval "$(bin/vault/hodd.sh emit secrets/platform.env)"   # set them in YOUR shell
#   bin/vault/hodd.sh tenant acme          # source a tenant's .env (that tenant only)
#
# Secrets are REFERENCED by path — `$YMIR_HOARD`, else `$YMIR_HOME`, else
# `$HOME/Documents/ymirhome`. The hoard is NEVER inside the repo (Rule 04); the
# repo's `hodd/` keeps only the guard, the README and *.example scaffolds.
set -u
# The ONE resolver (Rule 07): env -> the recorded choice -> the one default.
if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  _yh="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
  for _i in 1 2 3 4 5; do
    [ -n "$_yh" ] || break
    if [ -r "$_yh/bin/vault/hoard-lib.sh" ]; then . "$_yh/bin/vault/hoard-lib.sh"; YMIR_HOARD_LIB_LOADED=1; break; fi
    if [ -r "$_yh/hoard-lib.sh" ]; then . "$_yh/hoard-lib.sh"; YMIR_HOARD_LIB_LOADED=1; break; fi
    _yh="$(cd "$_yh/.." 2>/dev/null && pwd)"
  done
  unset _yh _i
fi
if [ -z "${YMIR_HOME:-}" ] && command -v ymir_home_root >/dev/null 2>&1; then
  ymir_home_root YMIR_HOME
fi

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"
# shellcheck source=bin/vault/hoard-lib.sh
. "$SCRIPT_DIR/hoard-lib.sh"
hoard_root HOARD

case "${1-}" in -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help|"") sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
ACTION="${1:-path}"; shift || true

# Source a KEY=value file with proper quoting, so values containing spaces
# survive (a plain `source` silently drops those lines).
load_env() {
  local f=$1 tmp
  [ -r "$f" ] || { printf 'error: not readable: %s\n' "$f" >&2; return 1; }
  tmp="$(mktemp)"
  python3 - "$f" >"$tmp" <<'PY'
import re, shlex, sys
for line in open(sys.argv[1]):
    m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)=(.*)$', line.rstrip("\n"))
    if m:
        print(f"export {m.group(1)}={shlex.quote(m.group(2))}")
PY
  set -a; . "$tmp"; set +a
  rm -f "$tmp"
  printf 'hodd[1]{action,file}:\n  "load","%s"\n' "$f"
}

# Resolve a secrets path: if the plaintext is absent but an .age sibling and the
# hoard key exist, decrypt to stdout. Prints a path to a readable file (a temp
# when decrypted) via the result var. Secrets stay encrypted at rest; the agent
# never reads ciphertext directly — it asks for the resolved path.
resolve_secret() {  # <file> <result-var>
  local f=$1 var=$2 tmp key
  # THE SEALED COPY IS THE SOURCE OF TRUTH. `bin/vault/hodd-set.sh` writes the .age and
  # NOTHING else, so a plaintext left beside it goes stale in silence — measured
  # 2026-11-05: three keys were written into platform.env.age (the mail grant) and every
  # reader still saw the 74-key plaintext, so `gna` reported "credentials missing" while
  # the vault held them, and the mail import failed on every run.
  #
  # So: a readable .age that DECRYPTS wins. The plaintext is the fallback, and the older
  # rule still holds inside it — an EMPTY plaintext never shadows the vault (2026-09-23).
  if [ -r "$f.age" ]; then
    key="$HOARD/secrets/age.key"
    if [ -r "$key" ] && command -v age >/dev/null 2>&1; then
      tmp="$(mktemp)"; chmod 600 "$tmp"
      if age -d -i "$key" "$f.age" >"$tmp" 2>/dev/null && [ -s "$tmp" ]; then
        printf -v "$var" '%s' "$tmp"; return 0
      fi
      rm -f "$tmp"
    fi
  fi
  if [ -s "$f" ]; then printf -v "$var" '%s' "$f"; return 0; fi
  if [ -r "$f.age" ]; then
    key="$HOARD/secrets/age.key"
    command -v age >/dev/null 2>&1 || { printf 'error: %s is encrypted but age is not installed\nhelp: sudo pacman -S age\n' "$f.age" >&2; return 1; }
    [ -r "$key" ] || { printf 'error: encrypted %s but no key at %s\n' "$f.age" "$key" >&2; return 1; }
    tmp="$(mktemp)"; chmod 600 "$tmp"
    age -d -i "$key" "$f.age" >"$tmp" 2>/dev/null || { rm -f "$tmp"; printf 'error: cannot decrypt %s\n' "$f.age" >&2; return 1; }
    printf -v "$var" '%s' "$tmp"; return 0
  fi
  printf 'error: not readable: %s (and no %s.age)\n' "$f" "$f" >&2; return 1
}
case "$ACTION" in
  path)  printf '%s\n' "$HOARD" ;;
  init)
    mkdir -p "$HOARD"/{secrets,docs,tenants,identity} || exit 1
    printf 'hodd[1]{action,path}:\n  "init","%s"\n' "$HOARD" ;;
  ls)
    printf 'hodd[4]{section,path,files}:\n'
    for d in secrets docs tenants identity; do
      n="$(find "$HOARD/$d" -type f 2>/dev/null | wc -l | tr -d ' ')"
      printf '  "%s","%s",%s\n' "$d" "$HOARD/$d" "$n"
    done ;;
  load)
    f="${1:-}"; [ -n "$f" ] || { printf 'error: load needs a path under the Hoard\n' >&2; exit 2; }
    case "$f" in /*) ;; *) f="$HOARD/$f" ;; esac
    resolve_secret "$f" rf || exit 1
    load_env "$rf"
    case "$rf" in "$f") ;; *) rm -f "$rf" ;; esac ;;
  emit)
    # Print `export KEY=value` lines (quoting-safe) for the CALLER to eval, so
    # `eval "$(bin/vault/hodd.sh emit <file>)"` sets the vars in the invoking shell.
    # Transparently decrypts an .age sibling when the plaintext is absent.
    f="${1:-}"; [ -n "$f" ] || { printf 'error: emit needs a path under the Hoard\n' >&2; exit 2; }
    case "$f" in /*) ;; *) f="$HOARD/$f" ;; esac
    resolve_secret "$f" rf || exit 1
    python3 - "$rf" <<'PY'
import re, shlex, sys
for line in open(sys.argv[1]):
    m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)=(.*)$', line.rstrip("\n"))
    if m:
        print(f"export {m.group(1)}={shlex.quote(m.group(2))}")
PY
    case "$rf" in "$f") ;; *) rm -f "$rf" ;; esac
    ;;
  tenant)
    t="${1:-}"; [ -n "$t" ] || { printf 'error: tenant needs a name\n' >&2; exit 2; }
    resolve_secret "$HOARD/tenants/$t/.env" rf || exit 1
    load_env "$rf"
    case "$rf" in "$HOARD/tenants/$t/.env") ;; *) rm -f "$rf" ;; esac ;;
  *) printf 'error: unknown action %s\nhelp: bin/vault/hodd.sh [path|init|ls|load|emit|tenant]\n' "$ACTION" >&2; exit 2 ;;
esac
