#!/usr/bin/env bash
# doc-sweep.sh — the shelf-sweeper (plan 63): find the operator's documents, inside
# the home and outside it, and PROPOSE where each one belongs. Then, and only then,
# move what a human has read and signed for.
#
#   doc-sweep.sh scan [root ...]        REPORT ONLY — classifies, proposes, writes nothing else
#   doc-sweep.sh apply --plan <file>    moves ONLY the MOVE lines of that plan; idempotent
#   doc-sweep.sh verify [--plan <file>] re-checks BY NAME that every applied file is where the plan said
#
# The laws, and they are the work:
#   * Nothing moves without a word. `scan` writes no file but its report; `apply` reads the
#     PLAN for what to move, never the filesystem. There is no --force and no --all, and
#     there is no "put it somewhere sensible".
#   * The repo stays clean: every destination must resolve inside the home, read through
#     the ONE resolver (bin/vault/hoard-lib.sh) — never a literal path, never $HOME/Documents.
#   * Never delete. A symlink, a socket and a binary are REPORTED; a duplicate is reported
#     as a duplicate; nothing is ever resolved by removing one.
#   * A machine never files into the plan ledger: a plan-shaped document is PROPOSED there.
#   * Staging is by NAME, always — this script stages nothing, and its report names every
#     path it would touch so a human can `git add` them one by one.
#
# Classification, by evidence, in this order: a path naming a known project in
# hodd/identity/projects.yaml → that project's shelf; a plan-shaped or numbered-plan
# document → the plan ledger, PROPOSED only; a note carrying a known domain
# (marketing · personal · work · meetings) → hodd/life/<domain>/; anything else is
# reported as UNPLACEABLE, with the reason it could not be placed. An unplaceable file
# is never dumped into docs/.
#
# Before those four classes, one ward: an item that is not a document — a symlink, a
# socket, a device, a binary, an archive, a credential by name, an operating-system
# folder, the vault itself — is REPORTED and never moved, whatever its name looks like.
#
# The report IS a plan file. Every line is one of
#   MOVE    <from>  ->  <to>   because: <reason>
#   PROPOSE <from>  ->  <to>   because: <reason>     (a machine proposes; only a word moves)
#   REPORT  <from>                        because: <reason>     (never moved, by law)
# so `bin/gates/doc-sweep.sh scan "$root" > plan.txt` hands the operator a plan, and
# `bin/gates/doc-sweep.sh apply --plan plan.txt` moves exactly the MOVE lines in it.
#
# Env:
#   YMIR_HOME / YMIR_HOARD / YMIR_STATE_DIR  the resolver's answers (bin/vault/hoard-lib.sh)
#   DOC_SWEEP_ROOT      the default root (default: the folder the home sits in)
#   DOC_SWEEP_DEPTH     how deep a root is walked (default 1)
#   DOC_SWEEP_CLASSES   a human-curated map, read when present (tab-separated):
#                         <shell-glob>  <destination-inside-the-home>  <reason>
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"

# ── the ONE resolver (Rule 07: configuration is never hardcoded) ───────────────
if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  # The resolver lives at bin/vault/hoard-lib.sh — the walk below looked for `hoard-lib.sh` at each
  # ancestor ROOT and so never found it after the move into bin/vault/ (measured 2026-11-02: the gate
  # refused with "bin/vault/hoard-lib.sh is missing" while the file sat exactly there). Look in the
  # canonical place first, then fall back to the walk.
  if [ -r "$ROOT/bin/vault/hoard-lib.sh" ]; then
    . "$ROOT/bin/vault/hoard-lib.sh"; YMIR_HOARD_LIB_LOADED=1
  else
    _yh="$SCRIPT_DIR"
    for _i in 1 2 3 4 5; do
      [ -n "$_yh" ] || break
      if [ -r "$_yh/bin/vault/hoard-lib.sh" ]; then . "$_yh/bin/vault/hoard-lib.sh"; YMIR_HOARD_LIB_LOADED=1; break; fi
      if [ -r "$_yh/hoard-lib.sh" ]; then . "$_yh/hoard-lib.sh"; YMIR_HOARD_LIB_LOADED=1; break; fi
      _yh="$(cd "$_yh/.." 2>/dev/null && pwd)"
    done
    unset _yh _i
  fi
fi
command -v ymir_home_root >/dev/null 2>&1 || {
  printf 'doc-sweep: bin/vault/hoard-lib.sh is missing — the home is never guessed\n' >&2; exit 2; }
ymir_home_root YMIR_HOME
hoard_root HOARD
hoard_state_dir STATE
LEDGER_DIR="$STATE/doc-sweep"
APPLIED="$LEDGER_DIR/applied.jsonl"
[ -d "$YMIR_HOME" ] || { printf 'doc-sweep: the home does not exist: %s\n' "$YMIR_HOME" >&2; exit 2; }
HOME_ABS="$(realpath -m -- "$YMIR_HOME" 2>/dev/null || printf '%s' "$YMIR_HOME")"

die() { printf 'doc-sweep: %s\n' "$1" >&2; exit 2; }
usage() { sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-2}"; }

# ── small helpers ─────────────────────────────────────────────────────────────
sha() {  # <path> — the file's digest, or the tree digest of a directory
  local p=$1
  if command -v sha256sum >/dev/null 2>&1; then
    if [ -f "$p" ] && [ ! -L "$p" ]; then sha256sum -- "$p" 2>/dev/null | cut -d' ' -f1; return 0; fi
    if [ -d "$p" ] && [ ! -L "$p" ]; then
      find "$p" -mindepth 1 -printf '%y %s %P\n' 2>/dev/null | LC_ALL=C sort | sha256sum | cut -d' ' -f1; return 0
    fi
  fi
  printf 'unknown'
}
tokens_of() { printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '\n' | grep -v '^$' || true; }
DOC_BIN='*.zip *.tar *.gz *.tgz *.bz2 *.xz *.7z *.rar *.jar *.whl *.exe *.dll *.so *.dylib *.bin *.iso *.srm *.pyc *.o *.a *.deb *.rpm *.appimage *.db *.sqlite'
# A document may be a container: a .pdf and a .odt are documents, and a .c is source.
# So the mime guess is not asked about them - only about everything else.
DOC_CONTAINER='*.pdf *.odt *.odp *.ods *.doc *.docx *.xls *.xlsx *.ppt *.pptx *.epub *.djvu *.rtf *.png *.jpg *.jpeg *.gif *.webp *.tif *.tiff *.heic *.mp3 *.mp4 *.wav'
is_document() {  # a .c is source and a .zip is neither; a .pdf and a .odt are documents
  local p=$1 b
  b=$(printf '%s' "$p" | tr 'A-Z' 'a-z')
  # a case pattern does not word-split, so the list is walked as words
  for e in $DOC_CONTAINER; do case "$b" in $e) return 0 ;; esac; done
  for e in $DOC_BIN; do case "$b" in $e) return 1 ;; esac; done
  [ -f "$p" ] || return 0
  LC_ALL=C grep -Iq . -- "$p" 2>/dev/null
}
strip_ext() { local b=${1##*/}; printf '%s' "${b%.*}"; }

# ── the registry: known projects and the realm each one belongs to ─────────────
REGISTRY=""      # lines: <id><TAB><realm>
registry() {
  local f="$HOARD/identity/projects.yaml"
  [ -r "$f" ] || return 1
  awk '
    function trim(s){ sub(/^[ \t]+/,"",s); sub(/[ \t]+$/,"",s); return s }
    function emit(){ if(cur!="") printf "%s\t%s\n", cur, (r==""?"work":r) }
    /^[ \t]*#/ { next }
    /^[ \t]*-[ \t]*id[ \t]*:/ { emit(); r=""; line=$0; sub(/^[^:]*:[ \t]*/,"",line); cur=trim(line); gsub(/[\042\047]/,"",cur); next }
    /^[ \t]*(realm|workspace)[ \t]*:/ { line=$0; sub(/^[^:]*:[ \t]*/,"",line); r=trim(line); gsub(/[\042\047]/,"",r); next }
    END { emit() }
  ' "$f"
}
match_project() {  # <path> — prints "<id>\t<realm>" when the PATH names a known project
  # Evidence must be a WHOLE name: the id's words must sit NEXT TO EACH OTHER in the
  # path. A loose word match is how every file under a home called `ymirhome` claimed
  # the project `ymir-home` — the folder the path merely passes through is not evidence.
  local p=$1 toks id realm
  toks="$(tokens_of "$p" | tr '\n' ' ')"
  while IFS=$'\t' read -r id realm; do
    [ -n "$id" ] || continue
    if awk -v want="$id" -v have="$toks" 'BEGIN{
      n=split(want, w, "-"); m=split(have, h, " ");
      for (i = 1; i + n - 1 <= m; i++) {
        ok = 1
        for (j = 1; j <= n; j++) if (h[i + j - 1] != w[j]) { ok = 0; break }
        if (ok) exit 0
      }
      exit 1
    }'; then
      printf '%s\t%s\n' "$id" "$realm"
      return 0
    fi
  done <<<"$REGISTRY"
  return 1
}
project_shelf() {  # <id> <realm> — the project's own shelf, created-path included
  local id=$1 realm=$2
  local base="$YMIR_HOME/svartalfaheim/$realm/projects/$id"
  if [ -d "$base/docs" ]; then printf '%s/docs' "$base"
  elif [ -d "$base" ]; then printf '%s' "$base"
  else printf '%s/docs' "$base"; fi
}


# ── classification ────────────────────────────────────────────────────────────
# sets: CLASS  DEST  REASON  VERB
CLASS=""; DEST=""; REASON=""; VERB="MOVE"
set_class() {  # <class> <destination> <reason> — the verb follows the class, never a flag
  CLASS=$1; DEST=${2-}; REASON=$3
  # The verb FOLLOWS the class, so the summary's count and the body's verb can
  # never disagree — they were: the summary said `unplaceable,64` while the body
  # printed `REPORT`, and a reader could not tell whether the 64 were a different
  # set from the 8 (2026-10-01). Every class that is not a move or a proposal now
  # says REPORT, and the summary says `report` for all of them.
  case "$1" in
    move)    VERB=MOVE ;;
    propose) VERB=PROPOSE ;;
    *)       VERB=REPORT ;;
  esac
}

classify() {  # <abs-path>
  local p=$1
  local base="${p##*/}" stem toks domain d

  # the vault's own machine shelves are never swept
  case "$p" in
    "$HOARD"/secrets|"$HOARD"/secrets/*|"$HOARD"/state|"$HOARD"/state/*|"$HOARD"/data|"$HOARD"/data/*|"$YMIR_HOME"/state|"$YMIR_HOME"/state/*|"$YMIR_HOME"/.git|"$YMIR_HOME"/.git/*)
      set_class report "" "a machine record under the vault's own shelf — reported, never swept"; return ;;
    "$YMIR_HOME"/.git|"$YMIR_HOME"/.git/*)
      set_class report "" "the vault's own git — reported, never swept"; return ;;
  esac
  case "$base" in
    .git|.gitignore|.DS_Store|Thumbs.db|.directory)
      set_class report "" "a version-control or desktop artefact, not a document"; return ;;
    Desktop|Desktop*|Downloads|documents|.Trash|.Trash-*|Music|Pictures|Videos|Public|Templates)
      set_class report "" "an operating-system folder, not a document"; return ;;
    ymirhome|ymirhome.*)
      set_class report "" "the vault itself (or a husk of it) — reported, never swept, never removed"; return ;;
  esac

  # ── ward zero: an item that is not a document is REPORTED, whatever it is named
  if [ -L "$p" ]; then set_class report "" "a symlink — reported, never moved"; return; fi
  if [ -S "$p" ]; then set_class report "" "a socket — reported, never moved"; return; fi
  if [ -p "$p" ] || [ -b "$p" ] || [ -c "$p" ]; then
    set_class report "" "a device or fifo — reported, never moved"; return; fi
  case "$(printf '%s' "$base" | tr 'A-Z' 'a-z')" in
    *token*|*secret*|*password*|*passwd*|*credential*|*api[_-]key*|*recovery-key*|ghp_*|sk-*)
      set_class hold "" "a credential by name — the vault's secrets shelf owns these; the sweeper never moves one"; return ;;
  esac
  if ! is_document "$p"; then
    set_class report "" "not a document (binary or archive) — reported, never moved"; return
  fi

  # ── the human's own map, when he has written one
  if [ -n "${DOC_SWEEP_CLASSES:-}" ] && [ -r "$DOC_SWEEP_CLASSES" ]; then
    while IFS=$'\t' read -r g dest why; do
      [ -n "${g:-}" ] || continue
      case "$g" in '#'*) continue ;; esac
      # shellcheck disable=SC2254
      case "$p" in $g) set_class move "$YMIR_HOME/${dest#/}" "${why:-named by the class map}"; return ;; esac
    done <"$DOC_SWEEP_CLASSES"
  fi

  # ── 1. a path naming a KNOWN PROJECT → that project's shelf
  if REGISTRY="$(registry)"; then
    local pid prealm
    if pid="$(match_project "$p")"; then
      prealm="$(printf '%s' "$pid" | cut -f2)"
      pid="$(printf '%s' "$pid" | cut -f1)"
      d="$(project_shelf "$pid" "$prealm")"
      set_class move "$d/$base" "names the known project ${pid%%$'\t'*} in hodd/identity/projects.yaml (realm $prealm)"
      return
    fi
  fi

  # ── 2. a plan-shaped or numbered-plan document → the plan ledger, PROPOSED only
  stem="$(strip_ext "$base")"
  # a leading date is a date, not a plan number: strip it before the plan test
  nodate="$(printf '%s' "$stem" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}[-_ ]*//')"
  case "$base" in
    plans|plans/*|*/plans/*|*/plans)
      set_class propose "$ledger_default/$base" "sits under a plans/ shelf"; return ;;
  esac
  if [ -n "$nodate" ] && printf '%s' "$nodate" | grep -Eq '^[0-9]{1,4}[-_]'; then
    set_class propose "$ledger_default/$base" "numbered like a plan in the ledger (NN-some-title)"; return
  fi
  if printf '%s' "$nodate" | grep -Eqi 'plan|roadmap|road-map|road map|proposal|strategy|masterplan'; then
    set_class propose "$ledger_default/$base" "plan-shaped by name — a machine PROPOSES the ledger, never files into it"; return
  fi

  # ── 3. a note carrying a KNOWN DOMAIN → hodd/life/<domain>/
  toks="$(tokens_of "$p")"
  for domain in marketing personal work meetings; do
    if printf '%s\n' "$toks" | grep -qx -- "$domain"; then
      set_class move "$YMIR_HOME/hodd/life/$domain/$base" "carries the known domain '$domain' → hodd/life/$domain/"
      return
    fi
  done

  # ── 4. everything else: UNPLACEABLE, with the reason it could not be placed
  if [ -d "$p" ]; then
    set_class unplaceable "" "a directory, and no evidence places it: it names no known project, no domain and no plan"
    return
  fi
  case "$base" in
    *.c|*.h|*.cc|*.cpp|*.hpp|*.py|*.js|*.ts|*.tsx|*.rs|*.go|*.java|*.sh|*.rb|*.swift|*.kt|*.json|*.yaml|*.yml|*.toml|*.ini)
      set_class unplaceable "" "source or config, not a document — and source belongs with its project, which is a proposal, not a guess" ;;
    *.txt|*.md|*.text)
      if printf '%s' "$stem" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
        set_class unplaceable "" "a dated note with NO domain in its name — name the domain (marketing · personal · work · meetings) and it files itself"
      else
        set_class unplaceable "" "no evidence places it: it names no known project, no known domain and nothing plan-shaped"
      fi ;;
    *.pdf|*.odt|*.docx|*.doc|*.rtf|*.html|*.htm|*.csv|*.org|*.epub)
      set_class unplaceable "" "a document, but nothing names where it belongs — a human names the shelf" ;;
    *)
      set_class unplaceable "" "no evidence places it: no known project, no known domain, nothing plan-shaped" ;;
  esac
}

# ── scan ──────────────────────────────────────────────────────────────────────
cmd_scan() {
  local depth="${DOC_SWEEP_DEPTH:-1}" roots=() r
  while [ $# -gt 0 ]; do
    case "$1" in
      --depth) shift; depth="${1-1}"; [ -n "$depth" ] || die "--depth needs a number" ;;
      -h|--help) usage 0 ;;
      --) shift; while [ $# -gt 0 ]; do roots+=("$1"); shift; done; break ;;
      -*) die "unknown flag for scan: $1" ;;
      *) roots+=("$1") ;;
    esac
    shift
  done
  [ "${#roots[@]}" -gt 0 ] || roots=("${DOC_SWEEP_ROOT:-$(dirname -- "$HOME_ABS")}")
  case "$depth" in ''|*[!0-9]*) die "--depth takes a whole number" ;; esac
  [ "$depth" -ge 1 ] || die "--depth is at least 1"

  REGISTRY="$(registry || true)"
  # The ledger is DISCOVERED, never derived. The ymir project's registry row names
  # the realm it WORKS in (`work`), but the canonical plan ledger lives under a
  # different realm (`whynotproductions`) — so deriving the destination from the
  # project's realm proposed a path that does not exist (2026-10-01). If exactly
  # one ledger is present, that is the ledger; only when none is found do we fall
  # back to the registry, and then we SAY the fallback was used.
  ledger_default=""
  ledger_note=""
  local found=0 cand
  for cand in "$YMIR_HOME"/svartalfaheim/*/projects/ymir/plans; do
    [ -d "$cand" ] || continue
    found=$((found + 1))
    ledger_default="$cand"
  done
  if [ "$found" -eq 1 ]; then
    ledger_note="discovered"
  elif [ "$found" -gt 1 ]; then
    ledger_default=""
    ledger_note="ambiguous ($found ledgers present — name one with --ledger)"
  else
    if [ -n "$REGISTRY" ]; then
      local yrealm; yrealm="$(printf '%s\n' "$REGISTRY" | awk -F'\t' '$1=="ymir-platform"{print $2; exit}')"
      ledger_default="$YMIR_HOME/svartalfaheim/${yrealm:-work}/projects/ymir/plans"
    fi
    [ -n "$ledger_default" ] || ledger_default="$YMIR_HOME/svartalfaheim/work/projects/ymir/plans"
    ledger_note="derived from the registry — no ledger found on disk"
  fi

  local -a items=()
  for r in "${roots[@]}"; do
    [ -e "$r" ] || { printf 'doc-sweep: no such root: %s\n' "$r" >&2; continue; }
    while IFS= read -r p; do [ -n "$p" ] && items+=("$p"); done \
      < <(find "$r" -mindepth 1 -maxdepth "$depth" 2>/dev/null | LC_ALL=C sort)
  done

  local -A counts=() seen=()
  local p c class dest reason verb digest
  local n=0
  local -a lines=()
  for p in "${items[@]}"; do
    n=$((n + 1))
    classify "$p"
    class=$CLASS; dest=$DEST; reason=$REASON; verb=$VERB

    # a duplicate is reported as a duplicate, never resolved by removing one
    if [ -f "$p" ] && [ ! -L "$p" ]; then
      digest="$(sha "$p")"
      if [ -n "${seen[$digest]:-}" ] && [ "${seen[$digest]}" != "$p" ]; then
        class=duplicate; verb=REPORT
        reason="the same bytes as ${seen[$digest]} — a duplicate is reported, never resolved by removing one"
      else
        seen[$digest]="$p"
      fi
    fi

    # an item already standing on its own shelf is a no-op, and says so
    if [ "$verb" = MOVE ] && [ -n "$dest" ]; then
      if [ "$(dirname -- "$dest")" = "$(dirname -- "$p")" ] || [ "$dest" = "$p" ] || [ "${dest#"$p"/}" != "$dest" ]; then
        class=in-place; verb=REPORT
        reason="already on its shelf [$(dirname -- "$dest")] — nothing to move"
      fi
    fi

    counts[$class]=$(( ${counts[$class]:-0} + 1 ))
    case "$verb" in
      MOVE)    lines+=("MOVE    $p  ->  $dest   because: $reason") ;;
      PROPOSE) lines+=("PROPOSE $p  ->  $dest   because: $reason") ;;
      *)       lines+=("REPORT  $p                      because: $reason") ;;
    esac
  done

  printf 'doc_sweep[%s]{class,count}:\n' "$n"
  local k tally=0
  # Every non-move, non-proposal class prints the verb REPORT, so the summary is
  # keyed the same way: `unplaceable` was a summary-only word, and a reader could
  # not tell whether it was the same set as `report` (it was not).
  # Fold the summary-only word into the verb the body actually prints, BEFORE the
  # loop, so one key is printed once and the tally balances. `unplaceable` was a
  # summary-only class: the body printed REPORT for those 64, so the summary and
  # the body were speaking different vocabularies for the same set (2026-10-01).
  if [ -n "${counts[unplaceable]+x}" ]; then
    counts[report]=$(( ${counts[report]:-0} + ${counts[unplaceable]:-0} ))
    unset 'counts[unplaceable]'
  fi
  for k in move propose report hold duplicate in-place; do
    [ -n "${counts[$k]+x}" ] || continue
    printf '  "%s",%s\n' "$k" "${counts[$k]}"
    tally=$((tally + ${counts[$k]}))
  done
  if [ "$tally" -ne "$n" ]; then
    printf 'doc-sweep: the report covers %s of %s items - refusing to call that a sweep\n' "$tally" "$n" >&2
    exit 1
  fi
  printf 'home: %s\n' "$YMIR_HOME"
  printf 'roots: %s\n' "${roots[*]}"
  printf 'ledger: %s\n' "${ledger_default:-<none — pass --ledger>}"
  [ -n "$ledger_note" ] && printf 'ledger_source: %s\n' "$ledger_note"
  printf 'depth: %s\n' "$depth"
  printf '# doc-sweep report — REPORT ONLY. Nothing was moved, and nothing will be until a human runs:\n'
  printf '#   bash bin/gates/doc-sweep.sh apply --plan <this-file>\n'
  printf '# PROPOSE lines are proposals: a machine never files into the plan ledger.\n'
  printf '\n'
  printf '%s\n' "${lines[@]}"
}

# ── apply ─────────────────────────────────────────────────────────────────────
# Reads the plan for WHAT TO MOVE. Never the filesystem.
parse_plan() {  # <file> — "<verb>\t<from>\t<to>\t<reason>" per line
  local f=$1
  [ -r "$f" ] || die "no such plan file: $f"
  awk '
    function trim(s){ sub(/^[ \t]+/,"",s); sub(/[ \t]+$/,"",s); return s }
    { line=$0; sub(/\r$/,"",line); if (line ~ /^[ \t]*#/ || line ~ /^[ \t]*$/) next
      if (line !~ /^(MOVE|PROPOSE|REPORT)[ \t]/) next
      verb=line; sub(/[ \t].*$/,"",verb)
      rest=trim(substr(line, length(verb)+1))
      a=index(rest,"->")
      if (verb == "REPORT") { from=rest; to=""; why=""
        sub(/[ \t]+because:.*$/,"",from); printf "REPORT\t%s\t\t\n", trim(from); next }
      if (a == 0) { printf "BAD\t%s\t\tno -> in the line\n", line; next }
      from=trim(substr(rest,1,a-1)); to=trim(substr(rest,a+2))
      b=index(to,"because:")
      if (b == 0) { printf "BAD\t%s\t\tno because: in the line\n", line; next }
      why=trim(substr(to,b+8)); to=trim(substr(to,1,b-1))
      if (from=="" || to=="") { printf "BAD\t%s\t\tan empty path\n", line; next }
      printf "%s\t%s\t%s\t%s\n", verb, from, to, why
    }' "$f"
}

cmd_apply() {
  local plan="" state_dir_opt=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --plan) shift; plan="${1-}"; [ -n "$plan" ] || die "--plan needs a file" ;;
      -h|--help) usage 0 ;;
      *) die "apply takes only --plan <file> — there is no --force and no --all" ;;
    esac
    shift
  done
  [ -n "$plan" ] || die "apply needs --plan <file>: the plan is the word that moves a file"

  local -a mv_from=() mv_to=() mv_why=() bad=()
  local verb from to why n=0
  while IFS=$'\t' read -r verb from to why; do
    [ -n "${verb:-}" ] || continue
    case "$verb" in
      REPORT|PROPOSE) continue ;;
      BAD) bad+=("plan line ${n}: ${to:-unparseable}"); continue ;;
    esac
    n=$((n + 1))
    mv_from+=("$from"); mv_to+=("$to"); mv_why+=("$why")
  done < <(parse_plan "$plan")

  if [ "${#bad[@]}" -gt 0 ]; then
    local b; for b in "${bad[@]}"; do printf 'doc-sweep: refusing the plan — %s\n' "$b" >&2; done
    printf 'doc-sweep: a line the plan cannot be read from is a line a human must fix. Nothing moved.\n' >&2
    exit 1
  fi
  if [ "$n" -eq 0 ]; then
    printf 'doc-sweep: the plan carries no MOVE lines — nothing to do, and nothing was done.\n'
    return 0
  fi

  # ── pre-flight EVERY line before ANY move: a partly applied plan is worse than none
  local -a do_from=() do_to=() do_why=() noop_from=()
  local i=0 abs par_abs from_exists to_exists
  while [ "$i" -lt "$n" ]; do
    from="${mv_from[$i]}"; to="${mv_to[$i]}"; why="${mv_why[$i]}"; i=$((i + 1))

    abs="$(realpath -m -- "$to" 2>/dev/null || printf '%s' "$to")"
    case "$abs" in
      "$HOME_ABS"|"$HOME_ABS"/*) ;;
      *)
        bad+=("${from} -> ${to}: the destination is OUTSIDE the home [${HOME_ABS}] — this repo is public, the home is the vault; nothing outside it is ever written")
        continue ;;
    esac
    par_abs="$(realpath -m -- "$(dirname -- "$to")" 2>/dev/null || printf '%s' "$(dirname -- "$to")")"
    [ "$par_abs" = "$(dirname -- "$to")" ] || {
      bad+=("${from} -> ${to}: a parent of the destination is a symlink — a move must not travel through one"); continue; }

    if [ -L "$from" ] || [ -S "$from" ] || [ -p "$from" ] || [ -b "$from" ] || [ -c "$from" ]; then
      bad+=("${from}: a symlink, socket or device is REPORTED, never moved — a plan may not move one"); continue
    fi
    if [ -e "$from" ] && ! is_document "$from"; then
      bad+=("${from}: not a document (binary or archive) — reported, never moved"); continue
    fi
    case "$(printf '%s' "${from##*/}" | tr 'A-Z' 'a-z')" in
      *token*|*secret*|*password*|*passwd*|*credential*|*recovery-key*|ghp_*)
        bad+=("${from}: a credential by name — the sweeper never moves one"); continue ;;
    esac
    case "$to" in
      */secrets/*|*/secrets|*/.git/*|*/.git)
        bad+=("${from} -> ${to}: the destination is a secrets or git shelf — the sweeper never writes there"); continue ;;
    esac

    from_exists=0; to_exists=0
    [ -e "$from" ] || [ -L "$from" ] && from_exists=1
    [ -e "$to" ] && to_exists=1

    if [ "$from_exists" = 0 ]; then
      if [ "$to_exists" = 1 ]; then
        noop_from+=("$from")          # already applied — the idempotent second run
      else
        bad+=("${from}: the source is gone and the destination does not exist — the plan and the tree disagree")
      fi
      continue
    fi
    if [ "$to_exists" = 1 ]; then
      bad+=("${from} -> ${to}: the destination already exists — a plan line that would overwrite is refused; nothing is ever overwritten")
      continue
    fi
    do_from+=("$from"); do_to+=("$to"); do_why+=("$why")
  done

  if [ "${#bad[@]}" -gt 0 ]; then
    local b; for b in "${bad[@]}"; do printf 'doc-sweep: refused — %s\n' "$b" >&2; done
    printf 'doc-sweep: %s line(s) refused. The whole plan is refused: a half-applied plan is worse than none. Nothing moved.\n' "${#bad[@]}" >&2
    exit 1
  fi

  local moved=0 already=0
  for o in ${noop_from[@]+"${noop_from[@]}"}; do
    printf 'noop   %s  (already at its destination — a second apply changes nothing)\n' "$o"; already=$((already + 1))
  done
  i=0
  while [ "$i" -lt "${#do_from[@]}" ]; do
    from="${do_from[$i]}"; to="${do_to[$i]}"; why="${do_why[$i]}"; i=$((i + 1))
    mkdir -p -- "$(dirname -- "$to")" || { printf 'doc-sweep: cannot make %s\n' "$(dirname -- "$to")" >&2; exit 1; }
    mv -- "$from" "$to" || { printf 'doc-sweep: move failed: %s -> %s\n' "$from" "$to" >&2; exit 1; }
    mkdir -p -- "$LEDGER_DIR" 2>/dev/null
    printf '{"ts":"%s","from":"%s","to":"%s","kind":"%s","sha256":"%s","because":"%s"}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$from" "$to" \
      "$([ -d "$to" ] && printf dir || printf file)" "$(sha "$to")" "$why" >>"$APPLIED"
    printf 'moved  %s  ->  %s   because: %s\n' "$from" "$to" "$why"
    moved=$((moved + 1))
  done

  printf 'doc_sweep_apply[4]{moved,already,refused,ledger}:\n'
  printf '  %s,%s,0,"%s"\n' "$moved" "$already" "$APPLIED"
  if [ "$moved" -gt 0 ]; then
    printf '# stage by NAME — never `git add -A` (Rule 06). Every destination above is a path to add.\n'
  fi
}

# ── verify ────────────────────────────────────────────────────────────────────
cmd_verify() {
  local plan="" from="$APPLIED"
  while [ $# -gt 0 ]; do
    case "$1" in
      --plan) shift; plan="${1-}"; [ -n "$plan" ] || die "--plan needs a file" ;;
      -h|--help) usage 0 ;;
      *) die "verify takes only --plan <file>" ;;
    esac
    shift
  done

  local -a v_to=() v_from=() v_sha=()
  if [ -n "$plan" ]; then
    [ -r "$plan" ] || die "no such plan file: $plan"
    local verb f t w
    while IFS=$'\t' read -r verb f t w; do
      [ "$verb" = MOVE ] || continue
      v_from+=("$f"); v_to+=("$t"); v_sha+=("")
    done < <(parse_plan "$plan")
  else
    [ -r "$from" ] || { printf 'doc-sweep: no ledger yet — nothing has ever been applied (%s)\n' "$from"; return 0; }
    local ts f t k s w
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      ts="$(printf '%s' "$line" | sed -n 's/.*"ts":"\([^"]*\)".*/\1/p')"
      f="$(printf '%s' "$line" | sed -n 's/.*"from":"\([^"]*\)".*/\1/p')"
      t="$(printf '%s' "$line" | sed -n 's/.*"to":"\([^"]*\)".*/\1/p')"
      s="$(printf '%s' "$line" | sed -n 's/.*"sha256":"\([^"]*\)".*/\1/p')"
      v_from+=("$f"); v_to+=("$t"); v_sha+=("$s")
    done <"$from"
  fi

  local total=${#v_to[@]} ok=0 fail=0 i=0 t s now
  for ((i = 0; i < total; i++)); do
    t="${v_to[$i]}"; s="${v_sha[$i]}"
    if [ ! -e "$t" ]; then
      printf '  "MISSING","%s","%s","not where the plan said"\n' "${v_from[$i]}" "$t"; fail=$((fail + 1)); continue
    fi
    if [ -n "$s" ] && [ "$s" != unknown ]; then
      now="$(sha "$t")"
      if [ "$now" != "$s" ]; then
        printf '  "CHANGED","%s","%s","recorded %s, now %s"\n' "${v_from[$i]}" "$t" "$s" "$now"; fail=$((fail + 1)); continue
      fi
      printf '  "OK","%s","%s","by name and by digest %s"\n' "${v_from[$i]}" "$t" "$s"; ok=$((ok + 1)); continue
    fi
    printf '  "OK","%s","%s","by name"\n' "${v_from[$i]}" "$t"; ok=$((ok + 1))
  done

  printf 'doc_sweep_verify[%s]{checked,ok,failed}:\n' "$total"
  printf '  %s,%s,%s\n' "$total" "$ok" "$fail"
  [ "$fail" -eq 0 ] || return 1
}

# ── main ──────────────────────────────────────────────────────────────────────
case "${1-}" in
  scan)   shift; cmd_scan "$@" ;;
  apply)  shift; cmd_apply "$@" ;;
  verify) shift; cmd_verify "$@" ;;
  -h|--help|help|"") usage "${1:+0}" ;;
  *) printf 'error: unknown verb %s\n' "$1" >&2; usage 2 ;;
esac
