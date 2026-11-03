#!/usr/bin/env bash
# secret-guard.sh — refuse to commit obvious secrets or private env files.
#
#   bin/gates/guards/secret-guard.sh            # scan the staged change (used as pre-commit)
#   bin/gates/guards/secret-guard.sh --install  # wire it into .git/hooks/pre-commit
#   bin/gates/guards/secret-guard.sh --all      # scan every tracked file once
#
# Exit 1 on any hit, so a commit is blocked before a secret leaves the machine.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"

PATTERNS='(AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(ghp|gho|ghs|ghr)_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]+|AIza[0-9A-Za-z_-]{35}|(CLOUDFLARE_API_TOKEN|OPENCODE_GO_API_KEY|GITHUB_TOKEN|OPENAI_API_KEY|ANTHROPIC_API_KEY)[[:space:]]*=[[:space:]]*[A-Za-z0-9_./+=-]{8,})'

# Paths deliberately exempt (test fixtures with fake secret-shaped strings),
# one glob per line in .secret-guardignore.
IGNORE="$ROOT/.secret-guardignore"
is_ignored() {
  [ -r "$IGNORE" ] || return 1
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in \#*) continue ;; esac
    case "$1" in $p) return 0 ;; esac
  done <"$IGNORE"
  return 1
}

case "${1:-}" in
  -v|-V|--version) printf '1.0.0\n'; exit 0 ;;
  -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --install)
    # `git rev-parse --git-path hooks` resolves the hooks dir for a clone AND for a worktree,
    # where `$ROOT/.git` is a FILE — an installer that assumed a directory could seat no ward at
    # all in the place all the work happens (found 2026-11-03, installing from a worktree).
    hook="$(cd "$ROOT" && git rev-parse --git-path hooks 2>/dev/null || printf '%s/.git/hooks' "$ROOT")/pre-commit"
    case "$hook" in /*) ;; *) hook="$ROOT/$hook" ;; esac   # git may answer absolute or relative
    mkdir -p "$(dirname "$hook")" || exit 1
    # ROOT IS RESOLVED AT RUN TIME. A hook written with this machine's absolute path dies the
    # day that tree is reclaimed — and it takes every ward in it with the hook (the pre-push
    # hook was taught this on 2026-10-20; the pre-commit one still baked a path until now).
    cat >"$hook" <<'HOOK'
#!/usr/bin/env bash
# pre-commit — the wards that judge a STAGED change. Installed by bin/gates/guards/secret-guard.sh --install.
set -u
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
G="$ROOT/bin/gates/guards"
for w in public-guard docs-guard private-guard vault-guard confidential-guard; do
  [ -x "$G/$w.sh" ] && { "$G/$w.sh" "$@" || exit 1; }
done
# Rule 11 — never delete, only move (RULES/11). A guarded deletion is logged, never silent.
[ -x "$ROOT/bin/no-delete-guard.sh" ] && { "$ROOT/bin/no-delete-guard.sh" --staged || exit 1; }
exec "$G/secret-guard.sh" "$@"
HOOK
    chmod +x "$hook"
    printf 'secret-guard[1]{action,path}:\n  "install","%s"\n' "$hook"
    exit 0 ;;
esac

scan_list() {
  local hit=0 f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    is_ignored "$f" && continue
    # A GUARD CONTAINS THE SHAPES IT LOOKS FOR. The guards shelf is where the patterns live,
    # so moving one made it newly staged and it flagged ITSELF — a false positive produced by a
    # rename. The detection shapes are the work; nothing in here is a credential.
    case "$f" in
      bin/gates/guards/*|bin/backend/fm-vendor-auth-probe.sh) continue ;;
    esac
    case "$f" in
      .env.local|*/.env.local|*.env.local|.env.realm|*/.env.realm)
        printf 'secret-guard: private env file: %s\n' "$f" >&2; hit=1; continue ;;
    esac
    if git -C "$ROOT" show ":$f" 2>/dev/null | sed 's/AKIAIOSFODNN7EXAMPLE//g' | grep -Eq "$PATTERNS"; then
      printf 'secret-guard: possible secret in %s\n' "$f" >&2; hit=1
    fi
  done
  return "$hit"
}

if [ "${1:-}" = "--all" ]; then
  scan_list < <(git -C "$ROOT" ls-files)
else
  scan_list < <(git -C "$ROOT" diff --cached --name-only --diff-filter=ACM)
fi || { printf 'secret-guard: blocked — remove the secret or move it to a .example file\n' >&2; exit 1; }
exit 0
