#!/usr/bin/env bash
# defaults-guard.sh — ONE PLACE KNOWS WHERE THINGS LIVE.
#
# A lock, not a wish. Ten scripts once carried their own home default; the tenth was
# found by hand a week later, which is the whole argument for this ward. There is one
# resolver (`bin/vault/hoard-lib.sh`) and one default, and no other file may restate them.
#
# It reads CODE, not prose: a runbook may quote a path, an executable may not guess
# one. A line may be waived in writing with `allow-home-default:` and a reason, which
# turns an accident into a decision.
#
# Three classes, one ward: a guessed default in code, a file that uses the home
# without resolving it, and a tracked symlink whose target is an absolute path.
#
# Usage:
#   defaults-guard.sh check [path...]   # the ward (default: bin/ .agents/ tools/ scripts/ src/)
#   defaults-guard.sh --version
#
# Exit: 0 clean · 1 a finding · 2 usage.
set -u

VERSION="1.1.0"
_root() {
  local d; d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [ "$d" != "/" ]; do
    [ -d "$d/.pi" ] && [ -d "$d/RULES" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
}
ROOT="$(_root)"

case "${1-}" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  check) shift ;;
  "") set -- check ;;
  *) printf 'error: unknown action %s\nhelp: defaults-guard.sh [check] [path...]\n' "${1-}" >&2; exit 2 ;;
esac

# The ONE definition site. Everything else must call it.
ALLOWLIST="bin/vault/hoard-lib.sh bin/gates/guards/defaults-guard.sh src/ymir_runtime/paths.py"

# A home guessed, a second root, or a synced-home name. Written as parts so this
# ward does not fire on itself. The seat rule is general on purpose: ANY absolute
# path naming a machine's own home is drift, not only one spelled with a known
# directory under it. System prefixes (/opt/homebrew, /usr/local/cuda) are the
# portable core's business and are deliberately NOT matched — Rule 05 owns them.
PAT="\\\$HOME/Doc""uments/|Doc""uments/ymirhome|/opt/ym""ir|/ho""me/[A-Za-z0-9_.-]+/|/Us""ers/[A-Za-z0-9_.-]+/"

# Test fixtures MUST name a synthetic home — that is how a path assertion is made
# at all — so a test is exempt from the literal rule. It is still linted.
NOT_CODE="--exclude=*.test.* --exclude=*.spec.* --exclude-dir=tests --exclude-dir=test --exclude-dir=__tests__"

TARGETS=("$@")
[ "${#TARGETS[@]}" -gt 0 ] || TARGETS=("$ROOT/bin" "$ROOT/.agents" "$ROOT/tools" "$ROOT/scripts" "$ROOT/src" "$ROOT/.pi")

findings=0
printf 'defaults-guard[3]{finding,file,line,text}:\n'
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  file="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"
  rel="${file#"$ROOT"/}"
  skip=0
  for a in $ALLOWLIST; do [ "$rel" = "$a" ] && skip=1; done
  [ "$skip" = 1 ] && continue
  text="${rest#*:}"
  case "$text" in *allow-home-default:*) continue ;; esac
  # A COMMENT is not a default. A runbook, a usage line or a header may quote a path;
  # only something that executes can guess one.
  trim="${text#"${text%%[![:space:]]*}"}"
  case "$trim" in '#'*|'//'*|'*'*) continue ;; esac
  printf '  "a home guessed","%s","%s","%s"\n' "$rel" "$line" "$(printf '%s' "$text" | cut -c1-72)"
  findings=$((findings + 1))
done < <(grep -rnE "$PAT" "${TARGETS[@]}" 2>/dev/null \
           --include='*.sh' --include='*.bash' --include='*.py' --include='*.js' \
           --include='*.mjs' --include='*.cjs' --include='*.ts' \
           $NOT_CODE --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=.yggdrasil || true)

if [ "$findings" -eq 0 ]; then
  printf '  "none","","","every path resolves through the one resolver"\n'
fi

# ── the second class: a script that USES the home and never RESOLVES it ───────
# The literal rule above is structurally blind to this, and that blindness cost ten
# scripts on 2026-09-24: converged to be free of any default, and left unable to run,
# because a file can be entirely literal-free and still not know where anything is.
# The resolver must actually be CALLED.
printf '\ndefaults-guard[2]{finding,file,why}:\n'
unresolved=0
# A COMMENT IS NOT CODE. Widening this walk to tools/ and src/ (2026-10-02) surfaced
# nine findings, and every one was a `$YMIR_HOME` inside a `#`/`//` comment or a Python
# docstring — the ward was grepping prose as though it were an instruction. Comments are
# stripped before the question is asked, so a file that only *talks about* the home is
# clean, and a file that *reads* it without resolving it is still refused.
code_of() {
  # 1. line comments (shell / python / js / ts), then 2. triple-quoted blocks (python
  #    docstrings). Everything else is code and is printed. The first version of this
  #    stripper had NO else branch for a line with two ordinary quotes, so it silently
  #    ate every line containing `X="$SOMETHING"` — it hid a REAL offender while looking
  #    like it worked. A filter that drops what it cannot classify is worse than none.
  grep -vE '^[[:space:]]*(#|//|\*|/\*)' "$1" 2>/dev/null | awk '
    function flush(rest,   pre) {
      pre = substr(rest, 1, RSTART - 1)
      if (substr(rest, RSTART + 3) ~ /"""/) print pre
      else { print pre; inq = 1 }
    }
    BEGIN { inq = 0; q = "" }
    {
      if (inq) { if (index($0, q)) inq = 0; next }
      rest = $0
      if (match(rest, /"""/)) { flush(rest); q = "\"\"\""; next }
      if (match(rest, /\x27\x27\x27/)) { flush(rest); q = "\x27\x27\x27"; next }
      print
    }'
}
while IFS= read -r f; do
  code_of "$f" | grep -qE '\$\{?YMIR_HOME' || continue
  grep -q 'ymir_home_root' "$f" 2>/dev/null && continue
  # A REAL assignment resolves it by hand and is allowed (the migrations set the old name
  # on purpose). A SELF-assignment is a no-op from the literal pass and is not an answer.
  if grep -qE '^[[:space:]]*(export[[:space:]]+)?YMIR_HOME=' "$f" 2>/dev/null \
     && ! grep -qE '^[[:space:]]*(export[[:space:]]+)?YMIR_HOME="\$\{YMIR_HOME\}"[[:space:]]*$' "$f" 2>/dev/null; then
    continue
  fi
  printf '  "uses the home, never resolves it","%s","call ymir_home_root (bin/vault/hoard-lib.sh), or assign the home deliberately"\n' "${f#"$ROOT"/}"
  unresolved=$((unresolved + 1))
done < <(find "${TARGETS[@]}" -type f \( -name '*.sh' -o -name '*.bash' -o -name '*.py' \
           -o -name '*.ts' -o -name '*.mjs' -o -name '*.js' \) \
           -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/target/*' \
           -not -path '*/.yggdrasil/*' 2>/dev/null | sort)

if [ "$unresolved" -eq 0 ]; then
  printf '  "none","",""\n'
fi

# ── the third class: a TRACKED SYMLINK pointing at one machine's absolute path ──
# The two passes above read file CONTENT, so they are structurally blind to this:
# for a symlink the content IS the target, in the index, and no grep of the
# worktree ever sees it. This is how `state` shipped as a link to
# /home/<another seat>/Documents/ymirhome/state — a clone on every other machine
# inherited a dead link, and the seat that made it had the dir, so it was never
# noticed at home.
#
# The law is one line: a tracked link is RELATIVE and in-tree. Rule 02's harness
# links (../../.agents/agents/*.md, ../.agents/skills) and `config` -> .agents/config
# all satisfy it; an absolute target never can, because an absolute path can only
# ever be true on the machine it was written on.
printf '\ndefaults-guard[2]{finding,link,target}:\n'
links=0
while IFS= read -r link; do
  [ -n "$link" ] || continue
  target="$(git -C "$ROOT" show ":$link" 2>/dev/null)" || continue
  case "$target" in
    /*)
      printf '  "absolute symlink ships a machine path","%s","%s"\n' "$link" "$target"
      links=$((links + 1)) ;;
  esac
done < <(git -C "$ROOT" ls-files -s 2>/dev/null | awk '$1=="120000"{print $4}')

if [ "$links" -eq 0 ]; then
  printf '  "none","",""\n'
fi

if [ "$findings" -eq 0 ] && [ "$unresolved" -eq 0 ] && [ "$links" -eq 0 ]; then
  exit 0
fi
printf 'defaults-guard: %s default(s), %s unresolved, %s absolute symlink(s)\nhelp: call the resolver (bin/vault/hoard-lib.sh); never restate where things live, never use the home without resolving it, and never track a link to an absolute path\n' \
  "$findings" "$unresolved" "$links" >&2
exit 1
