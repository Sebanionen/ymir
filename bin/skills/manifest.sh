#!/usr/bin/env bash
# manifest.sh — a skill declares itself; the index is DERIVED from the declarations.
#
# WHY THIS EXISTS (plan 184 §7, the Allfather's word: *"we need to also fix the logic
# of how the library in the skills are stored"*). Today a skill's meaning is carried by
# the DIRECTORY it happens to sit in: `.agents/skills/` means "ships", `.skills-local/`
# means "this machine", the home shelf means "the operator's own", and a skill inside an
# app is not a shelf at all — so it is invisible to the finder. Three faults follow:
#
#   1. visibility cannot be DECLARED — to not share one you must MOVE it; to share a
#      private one you must COPY it (and then it drifts);
#   2. the index is hand-kept and can LIE — a skill with no `description:` is unfindable,
#      and an app-owned skill is never listed at all;
#   3. duplication is SILENT — a name on two shelves resolves by shelf order, not by what
#      the house intends.
#
# The law that fixes it: ONE directory = one skill = one `skill.yaml` beside `SKILL.md`;
# the library is the set of declarations; the index is generated from them. A directory
# without a manifest FAILS BY NAME, and a manifest without a SKILL.md fails too — nothing
# is quietly skipped, because a quiet skip is how a skill becomes invisible.
#
# A manifest is FLAT yaml, one key per line (no nesting but the list form):
#
#   name: the-weaver            # required, kebab-case, must equal the directory name
#   kind: craft                 # required: craft · machine · personal · app
#   owner: house                # required: who may edit it
#   description: One line.      # required, EXACTLY one line — it is what skills_search returns
#   visibility: public          # required: public · share-method · private
#   version: 1.0.0              # required, semver
#   templates:                  # optional: the generic shapes worth sharing
#     - plan.md
#   requires:                   # optional: other skills this one names
#     - the-elder
#   shadows: other-skill        # optional: this skill OVERRIDES that name …
#   shadows_reason: why         # … and a reason is required with it
#
# Usage:
#   manifest.sh validate <dir>...        # judge the named skill directories
#   manifest.sh scan [root...]           # walk the shelves (or the roots given) and judge
#   manifest.sh index [--out PATH] [--check]
#   manifest.sh --migrate [root...]      # write a skill.yaml from existing front matter
#
# Roots default to the four shelves plus every app's own craft:
#   <repo>/.agents/skills · <repo>/.agents/skills-local · <home>/.agents/skills
#   ~/.pi/agent/skills · <repo>/apps/*/{skills,cookbooks}
#
# `--migrate` writes ONLY `skill.yaml` files: no file is moved, renamed or rewritten in
# the same pass, so the migration is reviewable as a diff (plan 184 §9 rule 6).
#
# Exit: 0 clean · 1 findings · 2 usage.
set -uo pipefail
VERSION="1.0.0"

_root() {
  local d; d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [ "$d" != "/" ]; do
    [ -d "$d/.pi" ] && [ -d "$d/RULES" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
}
ROOT="$(_root)"

# shellcheck disable=SC1091
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
HOME_ROOT=""
if command -v ymir_home_root >/dev/null 2>&1; then ymir_home_root HOME_ROOT; fi

FINDINGS=0
SKILLS_SEEN=0
ROW_FILE=""
row() { printf '  "%s","%s","%s","%s"\n' "$1" "$2" "$3" "$4"; FINDINGS=$((FINDINGS + 1)); }
note() { printf 'note: %s\n' "$*" >&2; }

# ── the flat-yaml reader ────────────────────────────────────────────────────────
# A manifest is deliberately too simple to need a parser: one `key: value` per line,
# lists as `  - item`. These three readers are the whole language.

yget() { # <file> <key> — the value of a top-level key, unquoted, trimmed
  local f="$1" k="$2" line
  [ -r "$f" ] || return 1
  line="$(grep -m1 -E "^${k}:" "$f" 2>/dev/null)" || return 1
  line="${line#*:}"
  line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  # an inline ` #…` is a comment; a value that needs a literal # is quoted.
  line="$(printf '%s' "$line" | sed -E 's/[[:space:]]+#.*$//')"
  case "$line" in
    \"*\") line="${line#\"}"; line="${line%\"}" ;;
    \'*\') line="${line#\'}"; line="${line%\'}" ;;
  esac
  printf '%s' "$line"
}

ycont() { # <file> <key> — how many EXTRA lines the key's value spans (0 = one line)
  # A value wraps in one of two ways, and both are the same fault: an indented continuation
  # (`  two lines…`), or a bare line where a key should be. Either way the value is no longer
  # one line, and `skills_search` would return a search row with a newline in it.
  awk -v k="$2" '
    $0 ~ "^" k ":" { on=1; next }
    on && /^[[:space:]]*$/ { next }
    on && /^[A-Za-z_][A-Za-z0-9_]*:/ { exit }
    on { n++; next }
    END { print n+0 }
  ' "$1"
}

ylist() { # <file> <key> — the items of a list key, one per line
  awk -v k="$2" '
    $0 ~ "^" k ":" {
      rest = $0; sub("^" k ":[[:space:]]*", "", rest)
      if (rest ~ /^\[.*\]$/) { gsub(/[][]/, "", rest); n = split(rest, a, ","); for (i=1;i<=n;i++) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[i]); if (a[i] != "") print a[i] }; exit }
      on = 1; next
    }
    on && /^[[:space:]]*-[[:space:]]*/ { sub(/^[[:space:]]*-[[:space:]]*/, ""); gsub(/^[[:space:]]+|[[:space:]]+$/, ""); gsub(/^["\x27]|["\x27]$/, ""); if ($0 != "") print; next }
    on && /^[[:space:]]*$/ { next }
    on { exit }
  ' "$1"
}

front_matter() { # <SKILL.md> <key> — a front-matter value, for --migrate only
  awk -v k="$2" '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    NR > 1 && $0 ~ "^" k ":" { sub("^" k ":[[:space:]]*", ""); gsub(/^["\x27]|["\x27]$/, ""); print; exit }
  ' "$1"
}

# ── the judgement ────────────────────────────────────────────────────────────────
KIND_OK=" craft machine personal app "
VIS_OK=" public share-method private "

judge_skill() { # <dir> <shelf-label> — 0 when the skill is legal, 1 when it is not
  local dir="$1" shelf="$2" base name kind owner desc vis ver sp
  base="$(basename "$dir")"
  local before="$FINDINGS"
  SKILLS_SEEN=$((SKILLS_SEEN + 1))

  if [ ! -f "$dir/SKILL.md" ] && [ ! -f "$dir/skill.yaml" ]; then
    row "FAIL" "$base" "$shelf" "a directory with neither SKILL.md nor skill.yaml — every directory on a skills shelf is a skill, or it is a stray"
    return 1
  fi
  if [ ! -f "$dir/skill.yaml" ]; then
    row "FAIL" "$base" "$shelf" "SKILL.md has no skill.yaml — a skill must declare itself (manifests are the law, plan 184 §7)"
    return 1
  fi
  if [ ! -f "$dir/SKILL.md" ]; then
    row "FAIL" "$base" "$shelf" "skill.yaml has no SKILL.md — a declaration with nothing to declare"
    return 1
  fi

  name="$(yget "$dir/skill.yaml" name)"
  kind="$(yget "$dir/skill.yaml" kind)"
  owner="$(yget "$dir/skill.yaml" owner)"
  desc="$(yget "$dir/skill.yaml" description)"
  vis="$(yget "$dir/skill.yaml" visibility)"
  ver="$(yget "$dir/skill.yaml" version)"

  # An override is DECLARED, never positional: `shadows: <name>` plus a reason. A skill that
  # declares it overrides another by name, so its own directory may carry a different name —
  # that is the one sanctioned exception to "name equals directory".
  local shadows reason
  shadows="$(yget "$dir/skill.yaml" shadows)"
  reason="$(yget "$dir/skill.yaml" shadows_reason)"

  [ -n "$name" ] || { row "FAIL" "$base" "$shelf" "skill.yaml has no name"; }
  if [ -n "$name" ]; then
    if ! printf '%s' "$name" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'; then
      row "FAIL" "$base" "$shelf" "name '$name' is not kebab-case"
    fi
    if [ "$name" != "$base" ] && [ -z "$shadows" ]; then
      row "FAIL" "$base" "$shelf" "name '$name' does not match its directory '$base' — one directory, one skill, one name"
    fi
  fi
  [ -n "$kind" ] || row "FAIL" "$base" "$shelf" "skill.yaml has no kind (craft · machine · personal · app)"
  if [ -n "$kind" ] && [ "${KIND_OK#* $kind }" = "${KIND_OK}" ]; then
    row "FAIL" "$base" "$shelf" "kind '$kind' is not one of craft · machine · personal · app"
  fi
  [ -n "$owner" ] || row "FAIL" "$base" "$shelf" "skill.yaml has no owner"
  [ -n "$ver" ] || row "FAIL" "$base" "$shelf" "skill.yaml has no version"
  if [ -n "$ver" ] && ! printf '%s' "$ver" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([-+][A-Za-z0-9.]+)?$'; then
    row "FAIL" "$base" "$shelf" "version '$ver' is not semver (MAJOR.MINOR.PATCH)"
  fi
  [ -n "$vis" ] || row "FAIL" "$base" "$shelf" "skill.yaml has no visibility (public · share-method · private)"
  if [ -n "$vis" ] && [ "${VIS_OK#* $vis }" = "${VIS_OK}" ]; then
    row "FAIL" "$base" "$shelf" "visibility '$vis' is not one of public · share-method · private"
  fi

  # `description` is what skills_search returns, so it is the ONE field that must never
  # be empty and never wrap: a two-line description is a search row with a newline in it.
  if [ -z "$desc" ]; then
    row "FAIL" "$base" "$shelf" "description is required and is one line — it is what skills_search returns"
  else
    sp="$(ycont "$dir/skill.yaml" description)"
    if [ "${sp:-0}" -gt 0 ]; then
      row "FAIL" "$base" "$shelf" "description wraps over $((sp + 1)) lines — it must be exactly one line"
    fi
    if [ "${#desc}" -gt 200 ]; then
      row "FAIL" "$base" "$shelf" "description is ${#desc} characters — one line, at most 200, so a search row stays a row"
    fi
    if [ "$(grep -c -E '^description:' "$dir/skill.yaml")" -gt 1 ]; then
      row "FAIL" "$base" "$shelf" "description appears twice"
    fi
  fi

  if [ -n "$shadows" ] && [ -z "$reason" ]; then
    row "FAIL" "$base" "$shelf" "shadows: $shadows with no shadows_reason — an override must say why it exists"
  fi

  [ "$FINDINGS" -eq "$before" ]
}

# ── roots ───────────────────────────────────────────────────────────────────────
default_roots() {
  local d
  for d in "$ROOT/.agents/skills" "$ROOT/.agents/skills-local" \
           "${HOME_ROOT:-}/.agents/skills" "$HOME/.pi/agent/skills"; do
    [ -n "$d" ] && [ -d "$d" ] && printf '%s\n' "$d"
  done
  # An application's own craft is a shelf too: it was invisible to the finder because no
  # shelf knew its name. Manifest-scanning knows no pack by name.
  for d in "$ROOT"/apps/*/skills "$ROOT"/apps/*/cookbooks; do
    [ -d "$d" ] && printf '%s\n' "$d"
  done
}

# Every skill directory under a root: any directory holding SKILL.md or skill.yaml, at any
# depth — a pack nested three levels deep is still a skill (the finder learned this on
# 2026-10-18; the scanner must not relearn it).
find_skill_dirs() { # <root>
  find "$1" -mindepth 1 \( -name SKILL.md -o -name skill.yaml \) -type f -print 2>/dev/null \
    | sed 's|/[^/]*$||' | sort -u
}

scan_roots() { # <root>...
  local root d name dirs=() seen_names="" dup_report=""
  local -A NAME_PATH=()
  for root in "$@"; do
    [ -d "$root" ] || { note "no skill shelf at $root — skipped"; continue; }
    dirs=()
    while IFS= read -r d; do [ -n "$d" ] && dirs+=("$d"); done < <(find_skill_dirs "$root")
    for d in "${dirs[@]}"; do
      judge_skill "$d" "$root"
      [ -f "$d/skill.yaml" ] || continue
      name="$(yget "$d/skill.yaml" name)"
      [ -n "$name" ] || name="$(basename "$d")"
      if [ -n "${NAME_PATH[$name]:-}" ]; then
        local a="${NAME_PATH[$name]}" b="$d"
        if declares_shadow "$b" "$name"; then
          printf '  "OVERRIDE","%s","%s","overrides %s — declared with shadows + reason"\n' "$name" "$b" "$a"
        elif declares_shadow "$a" "$name"; then
          printf '  "OVERRIDE","%s","%s","overrides %s — declared with shadows + reason"\n' "$name" "$a" "$b"
        else
          row "DUPLICATE" "$name" "$a" "name '$name' is declared twice ($a and $b) — one owner per name; an override declares shadows: $name + shadows_reason"
        fi
      else
        NAME_PATH[$name]="$d"
      fi
    done
  done
}

declares_shadow() { # <dir> <name> — does this manifest declare that it overrides <name>?
  local dir="$1" name="$2"
  [ -f "$dir/skill.yaml" ] || return 1
  [ "$(yget "$dir/skill.yaml" shadows)" = "$name" ] || return 1
  [ -n "$(yget "$dir/skill.yaml" shadows_reason)" ]
}

# ── index ───────────────────────────────────────────────────────────────────────
write_index() { # <out> <root>...
  local out="$1"; shift
  local root d name desc kind owner vis ver
  local tmp; tmp="$(mktemp)" || exit 1
  {
    printf '# generated by bin/skills/manifest.sh index — from manifests only, never hand-edited\n'
    printf 'version: 1\n'
    printf 'generated: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    local rows=() 
    for root in "$@"; do
      [ -d "$root" ] || continue
      while IFS= read -r d; do
        [ -f "$d/skill.yaml" ] || continue
        name="$(yget "$d/skill.yaml" name)"; [ -n "$name" ] || name="$(basename "$d")"
        kind="$(yget "$d/skill.yaml" kind)"
        owner="$(yget "$d/skill.yaml" owner)"
        vis="$(yget "$d/skill.yaml" visibility)"
        ver="$(yget "$d/skill.yaml" version)"
        desc="$(yget "$d/skill.yaml" description)"
        rows+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' "$name" "$kind" "$owner" "$vis" "$ver" "${d#"$root"/}" "$desc")")
      done < <(find_skill_dirs "$root")
    done
    printf 'count: %s\n' "${#rows[@]}"
    printf 'skills:\n'
    if [ "${#rows[@]}" -gt 0 ]; then
      printf '%s\n' "${rows[@]}" | sort | while IFS=$'\t' read -r name kind owner vis ver rel desc; do
        printf '  - name: %s\n' "$name"
        printf '    kind: %s\n' "${kind:-unknown}"
        printf '    owner: %s\n' "${owner:-unknown}"
        printf '    visibility: %s\n' "${vis:-unknown}"
        printf '    version: %s\n' "${ver:-0.0.0}"
        printf '    path: %s\n' "$rel"
        printf '    description: %s\n' "${desc}" | sed 's/[[:space:]]*$//'
      done
    fi
  } > "$tmp"
  mv "$tmp" "$out" || exit 1
}

# ── actions ─────────────────────────────────────────────────────────────────────
ACTION="${1:-}"; [ $# -gt 0 ] && shift || true
ROOTS=(); OUT=""; CHECK=0

case "$ACTION" in
  -v|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help|help|"") sed -n '2,58p' "$0" | sed 's/^# \{0,1\}//'; [ -z "$ACTION" ] && exit 2; exit 0 ;;
  validate|scan|index|--migrate) ;;
  *) printf 'error: unknown action %s\nhelp: manifest.sh validate|scan|index|--migrate\n' "$ACTION" >&2; exit 2 ;;
esac

while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="${2:-}"; shift 2 ;;
    --out=*) OUT="${1#*=}"; shift ;;
    --root) ROOTS+=("${2:-}"); shift 2 ;;
    --root=*) ROOTS+=("${1#*=}"); shift ;;
    --check) CHECK=1; shift ;;
    -*) printf 'error: unknown flag %s\n' "$1" >&2; exit 2 ;;
    *) ROOTS+=("$1"); shift ;;
  esac
done

if [ "${#ROOTS[@]}" -eq 0 ]; then
  while IFS= read -r r; do [ -n "$r" ] && ROOTS+=("$r"); done < <(default_roots)
fi
if [ "${#ROOTS[@]}" -eq 0 ]; then
  printf 'manifest.sh: no skills shelf found — nothing to judge\n' >&2
  exit 2
fi

case "$ACTION" in
  validate)
    printf 'manifest_skills[%s]{kind,skill,shelf,detail}:\n' "${#ROOTS[@]}"
    for d in "${ROOTS[@]}"; do
      if [ -d "$d" ]; then judge_skill "$d" "$(dirname "$d")"
      else row "FAIL" "$d" "" "not a directory"; fi
    done
    ;;
  scan)
    printf 'manifest_scan[%s]{kind,skill,shelf,detail}:\n' "${#ROOTS[@]}"
    scan_roots "${ROOTS[@]}"
    ;;
  index)
    OUT="${OUT:-${HOME_ROOT:+$HOME_ROOT/hodd/skills/index.yaml}}"
    [ -n "$OUT" ] || { printf 'manifest.sh: no --out and no home to write into\n' >&2; exit 2; }
    if [ "$CHECK" = 1 ]; then
      tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
      write_index "$tmp" "${ROOTS[@]}"
      # `generated:` is a timestamp: compared on its key, not its value.
      if [ -f "$OUT" ] && diff -q <(grep -v '^generated:' "$OUT") <(grep -v '^generated:' "$tmp") >/dev/null; then
        printf 'index_fresh[1]{path,count}:\n  "%s","%s"\n' "$OUT" "$(sed -n 's/^count: //p' "$tmp")"
        exit 0
      fi
      printf 'index_stale[1]{path,remedy}:\n  "%s","manifest.sh index --out %s"\n' "$OUT" "$OUT" >&2
      exit 1
    fi
    mkdir -p "$(dirname "$OUT")" 2>/dev/null || true
    write_index "$OUT" "${ROOTS[@]}"
    printf 'index_written[2]{path,count}:\n  "%s","%s"\n' "$OUT" "$(sed -n 's/^count: //p' "$OUT")"
    exit 0
    ;;
  --migrate)
    # Write ONLY skill.yaml files. Nothing is moved, renamed or rewritten: the migration
    # is a diff a person can read.
    printf 'manifest_migrate[%s]{skill,manifest,kind,visibility}:\n' "${#ROOTS[@]}"
    wrote=0; skipped=0
    for root in "${ROOTS[@]}"; do
      [ -d "$root" ] || continue
      while IFS= read -r d; do
        base="$(basename "$d")"
        [ -f "$d/SKILL.md" ] || continue
        if [ -f "$d/skill.yaml" ]; then skipped=$((skipped + 1)); continue; fi
        name="$(front_matter "$d/SKILL.md" name)"; [ -n "$name" ] || name="$base"
        desc="$(front_matter "$d/SKILL.md" description)"
        printf '%s' "$desc" | grep -q . || desc="$(printf '%s' "$name" | tr '-' ' ')"
        desc="$(printf '%s' "$desc" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g;s/^ //;s/ $//' | cut -c1-200)"
        # kind names WHERE it lives; visibility is the declaration that later replaces the
        # shelf's meaning. The one shelf that ships is public by definition; everything else
        # starts private and is SHARED by a declaration, never by living somewhere.
        case "$root" in
          */apps/*/skills|*/apps/*/cookbooks) kind="app"; vis="private" ;;
          */.agents/skills-local|*/.pi/agent/skills) kind="machine"; vis="private" ;;
          *) kind="craft"; vis="private" ;;
        esac
        [ "$root" = "$ROOT/.agents/skills" ] && vis="public"
        {
          printf '# written by bin/skills/manifest.sh --migrate — edit freely; the index is derived\n'
          printf 'name: %s\n' "$name"
          printf 'kind: %s\n' "$kind"
          printf 'owner: house\n'
          printf 'description: %s\n' "$desc"
          printf 'visibility: %s\n' "$vis"
          printf 'version: 0.1.0\n'
        } > "$d/skill.yaml"
        printf '  "%s","skill.yaml","%s","%s"\n' "$name" "$kind" "$vis"
        wrote=$((wrote + 1))
      done < <(find_skill_dirs "$root")
    done
    printf 'migrated: %s written · %s already declared\n' "$wrote" "$skipped"
    exit 0
    ;;
esac

printf 'manifest.sh: %s skill director%s judged · %s finding(s)\n' \
  "$SKILLS_SEEN" "$([ "$SKILLS_SEEN" = 1 ] && echo y || echo ies)" "$FINDINGS"
[ "$FINDINGS" -eq 0 ] || exit 1
exit 0
