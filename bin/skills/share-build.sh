#!/usr/bin/env bash
# share-build.sh — the built copy that may leave. Never the shelf itself.
#
# WHY (plan 184 §3, §9): a collaborator may borrow the craft, the method and the templates —
# and never our machines, our people, our recordings or our catalog. So what leaves is not a
# symlink into the library and not "the folder with the private bits deleted by hand": it is a
# BUILT tree under `published/`, produced from a declared share list, redacted, hashed, and
# refused by a ward when anything private survives.
#
#   share.yaml       DECLARED — one entry per skill that may leave, with a reason and a form
#   published/       BUILT    — `<skill>/SKILL.md`, `templates/`, `assets/`, `manifest.json`
#   manifest.json    PROOF    — name · version · sha256 · source_rev · redactions[]
#
# A share entry is flat, one record per `- name:`:
#
#   skills:
#     - name: hearth-keeping
#       reason: the shape of a fix note, which is what a collaborator keeps asking for
#       form: skill            # skill · method-only · templates-only
#
# The three forms, and what each may carry:
#   skill           the SKILL.md, its templates/ and its assets/ (redacted like the body)
#   method-only     the SKILL.md with its RESULTS sections cut (bench runs, measurements,
#                   inventories) — the doctrine survives, the runs do not
#   templates-only  the templates/ alone; SKILL.md is a stub carrying the declaration, so the
#                   door still answers `skills_get` with a front matter and no argument
#
# Redaction rewrites what the house can NAME: user paths, LAN/tailnet hosts and private
# addresses, the ports hung off them, the machine's own names, our people's names (from the
# deny list generated here), chat/user ids, and model ids from our catalog. What it cannot
# name, it cannot rewrite — and that is exactly why the ward exists: the ward REFUSES what the
# redactor could only suspect, so an unknown host is a build failure, never a leak.
#
# Usage:
#   share-build.sh                 # build published/ from share.yaml
#   share-build.sh --check         # build into a scratch tree and refuse on drift or a finding
#   share-build.sh --share FILE --out DIR --root DIR [--root DIR…]
#
# Env: SKILLS_SHARE_DIR (default <home>/hodd/skills-share) · SKILLS_SHARE_SKILLS (roots)
#
# Exit: 0 built/clean · 1 findings (drift, a ward hit, a bad share entry) · 2 usage.
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

SHARE_DIR="${SKILLS_SHARE_DIR:-${HOME_ROOT:+$HOME_ROOT/hodd/skills-share}}"
SHARE_FILE=""; OUT=""; CHECK=0; ROOTS=()

case "${1:-}" in
  -v|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help) sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
while [ $# -gt 0 ]; do
  case "$1" in
    --share) SHARE_FILE="${2:-}"; shift 2 ;;
    --share=*) SHARE_FILE="${1#*=}"; shift ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --out=*) OUT="${1#*=}"; shift ;;
    --root) ROOTS+=("${2:-}"); shift 2 ;;
    --root=*) ROOTS+=("${1#*=}"); shift ;;
    --check) CHECK=1; shift ;;
    *) printf 'error: unknown argument %s\nhelp: share-build.sh [--check] [--share FILE] [--out DIR] [--root DIR]\n' "$1" >&2; exit 2 ;;
  esac
done

[ -n "$SHARE_FILE" ] || SHARE_FILE="${SKILLS_SHARE_DIR:-$SHARE_DIR}/share.yaml"
[ -n "$SHARE_DIR" ] || SHARE_DIR="$(dirname "$SHARE_FILE")"
[ -n "$OUT" ] || OUT="$SHARE_DIR/published"

if [ "${#ROOTS[@]}" -eq 0 ]; then
  for d in "$ROOT/.agents/skills" "$ROOT/.agents/skills-local" \
           "${HOME_ROOT:-}/.agents/skills" "$HOME/.pi/agent/skills"; do
    [ -n "$d" ] && [ -d "$d" ] && ROOTS+=("$d")
  done
  for d in "$ROOT"/apps/*/skills "$ROOT"/apps/*/cookbooks; do
    [ -d "$d" ] && ROOTS+=("$d")
  done
fi

if [ ! -r "$SHARE_FILE" ]; then
  printf 'share-build[1]{finding,path}:\n  "no share list","%s"\n' "$SHARE_FILE"
  printf 'help: a build with nothing declared publishes nothing — write share.yaml first (name · reason · form)\n' >&2
  exit 1
fi

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
BUILD="$WORK/published"; mkdir -p "$BUILD"
FINDINGS=0
finding() { printf '  "%s","%s","%s"\n' "$1" "$2" "$3"; FINDINGS=$((FINDINGS + 1)); }

# ── the flat-yaml reader (one language with bin/skills/manifest.sh) ──────────────
yget() {
  local f="$1" k="$2" line
  line="$(grep -m1 -E "^[[:space:]]*${k}:" "$f" 2>/dev/null)" || return 1
  line="${line#*:}"
  line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]\+#.*$//')"
  case "$line" in \"*\") line="${line#\"}"; line="${line%\"}" ;; \'*\') line="${line#\'}"; line="${line%\'}" ;; esac
  printf '%s' "$line"
}

share_entries() { # <share.yaml> — one record per line: name<TAB>form<TAB>reason
  awk '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    function emit() { if (name != "") printf "%s\t%s\t%s\n", name, (form == "" ? "skill" : form), reason }
    /^[[:space:]]*-[[:space:]]*name:/ { emit(); name = $0; sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", name); name = trim(name); form = ""; reason = ""; next }
    /^[[:space:]]*name:/ && name == "" { name = $0; sub(/^[[:space:]]*name:[[:space:]]*/, "", name); name = trim(name); next }
    /^[[:space:]]*form:/ { form = $0; sub(/^[[:space:]]*form:[[:space:]]*/, "", form); form = trim(form); next }
    /^[[:space:]]*reason:/ { reason = $0; sub(/^[[:space:]]*reason:[[:space:]]*/, "", reason); reason = trim(reason); next }
    END { emit() }
  ' "$1" | sed 's/^[[:space:]]*//' | grep -v '^$'
}

skill_dir_for() { # <name> — the one directory that declares this name
  local name="$1" root d n hits=()
  for root in "${ROOTS[@]}"; do
    [ -d "$root" ] || continue
    while IFS= read -r d; do
      [ -f "$d/skill.yaml" ] || continue
      n="$(yget "$d/skill.yaml" name)"
      [ -n "$n" ] || n="$(basename "$d")"
      [ "$n" = "$name" ] || continue
      # A declared override wins over what it shadows; anything else is ambiguous.
      if [ -n "$(yget "$d/skill.yaml" shadows)" ]; then hits+=("$d"); else hits=("$d"); fi
    done < <(find "$root" -mindepth 1 -name skill.yaml -type f 2>/dev/null | sed 's|/[^/]*$||' | sort -u)
  done
  [ "${#hits[@]}" -gt 0 ] && printf '%s' "${hits[0]}"
}

# ── the deny lists: what the redactor can NAME, and what the ward must REFUSE ────
make_deny_names() { # <out>
  local out="$1"
  {
    echo '# generated by bin/skills/share-build.sh — names that never leave a build'
    echo "# this machine's own user, then every person the house keeps in a registry"
    id -un 2>/dev/null
    [ -n "${USER:-}" ] && printf '%s\n' "$USER"
    local f shape
    # operator · collaborators · names — the same three shelves Gimle knows a person from.
    for f in "${HOME_ROOT:-/nonexistent}/hodd/identity/operator.yaml" \
             "${HOME_ROOT:-/nonexistent}/hodd/identity/collaborators.yaml" \
             "${HOME_ROOT:-/nonexistent}/hodd/identity/names.yaml"; do
      [ -r "$f" ] || continue
      sed -nE 's/^[[:space:]-]*(name|full_name|alias|aliases|display|display_name)[[:space:]]*:[[:space:]]*(.*)$/\2/p' "$f" \
        | sed -E 's/[][]//g' | tr ',' '\n' \
        | sed -E 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//' \
        | grep -vE '^$|^#|^-?$' | head -40
    done
    # An explicit seed (used by the test ward, and by an operator who wants a name withheld).
    printf '%s\n' "${SKILLS_SHARE_NAMES:-}" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
  } | awk 'NF && !/^#/' | sort -u > "$out"
}

make_deny_models() { # <out> — the catalog is the truth, never a table in a doc
  local out="$1"
  {
    echo "# generated by bin/skills/share-build.sh — model ids from this machine's own catalog"
    if [ -x "$ROOT/bin/model/catalog.sh" ]; then
      bash "$ROOT/bin/model/catalog.sh" 2>/dev/null \
        | sed -nE 's/^[[:space:]]*"([^"]+)","([^"]+)".*/\1\/\2/p'
    fi
  } | awk 'NF && !/^#/' | sort -u > "$out"
}

# ── the redactor ────────────────────────────────────────────────────────────────
cat > "$WORK/redact.py" <<'PY'
"""Redact one text file. Rewrites what the house can NAME; records how many of each."""
import json, re, sys

src, dst, names_f, models_f, report_f = sys.argv[1:6]
text = open(src, encoding="utf-8", errors="replace").read()
counts = {}

def sub(kind, pattern, repl, s, flags=0):
    new, n = re.subn(pattern, repl, s, flags=flags)
    if n:
        counts[kind] = counts.get(kind, 0) + n
    return new

# ORDER MATTERS: a path before a host (a path can contain a host), a host before a bare port.
text = sub("machine path", r"(?:/(?:home|Users)/[^/\s\"'`]+)|(?:[A-Za-z]:\\\\Users\\\\[^\\\\\s]+)", "<the machine>", text)
text = sub("chat or user id", r"\b(?:chat|user|uid|gid|channel)[ _-]?id\s*[:=]\s*-?\d{4,}", "<an id>", text, re.I)
text = sub("host", r"\b[a-zA-Z0-9][a-zA-Z0-9.-]*\.(?:local|lan|internal|ts\.net|home\.arpa|tailnet)\b", "<the host>", text, re.I)

# the machine's own names, from the deny list's first lines (id -un, hostname)
import socket
own = set()
try:
    own.add(socket.gethostname()); own.add(socket.gethostname().split(".")[0])
except OSError:
    pass
for name in sorted(own, key=len, reverse=True):
    if len(name) >= 4:
        text = sub("host", r"(?<![\w.-])" + re.escape(name) + r"(?![\w.-])", "<the host>", text)

text = sub("private address", r"\b(?:10\.\d{1,3}|192\.168|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}\b", "<the host>", text)
text = sub("port", r"\b(?:<the host>|localhost|127\.0\.0\.1|\[::1\]):\d{2,5}\b", "<the host>", text)
text = sub("host", r"\b[a-z0-9][a-z0-9.-]*\.[a-z]{2,}:\d{2,5}\b", "<the host>", text, re.I)
text = sub("port", r"\bports?\s+(?:is\s+|of\s+|at\s+)?\d{3,5}\b", "port <the port>", text, re.I)
text = sub("chat or user id", r"(?<![\w.-])-?\d{9,}(?![\w.-])", "<an id>", text)

for line in open(models_f, encoding="utf-8", errors="replace"):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    text = sub("model id", r"(?<![\w./-])" + re.escape(line) + r"(?![\w./-])", "<a model>", text)
    bare = line.split("/", 1)[-1]
    if len(bare) >= 6 and any(c.isdigit() for c in bare):
        text = sub("model id", r"(?<![\w./-])" + re.escape(bare) + r"(?![\w./-])", "<a model>", text)

for line in sorted((l.strip() for l in open(names_f, encoding="utf-8", errors="replace")),
                   key=len, reverse=True):
    if not line or line.startswith("#") or len(line) < 3:
        continue
    text = sub("name", r"(?<![\w-])" + re.escape(line) + r"(?![\w-])", "<a person>", text, re.I)

open(dst, "w", encoding="utf-8").write(text)
with open(report_f, "a", encoding="utf-8") as rep:
    for kind, n in sorted(counts.items()):
        rep.write(f"{kind}\t{n}\t{src}\n")
PY

cat > "$WORK/manifest.py" <<'PY'
"""The per-skill manifest.json: name · version · sha256 · source_rev · redactions[]."""
import hashlib, json, os, sys

skill_dir, name, version, rev, report_f, out_f = sys.argv[1:7]
h = hashlib.sha256()
for base, dirs, files in os.walk(skill_dir):
    dirs.sort()
    for f in sorted(files):
        if f == "manifest.json":
            continue
        p = os.path.join(base, f)
        rel = os.path.relpath(p, skill_dir).replace(os.sep, "/")
        h.update(rel.encode() + b"\0")
        h.update(open(p, "rb").read() + b"\0")

redactions = []
seen = {}
if os.path.exists(report_f):
    for line in open(report_f, encoding="utf-8"):
        kind, n, path = (line.rstrip("\n").split("\t") + ["", "", ""])[:3]
        key = (kind, path)
        seen[key] = seen.get(key, 0) + int(n or 0)
for (kind, path), n in sorted(seen.items()):
    redactions.append({"file": os.path.basename(path), "kind": kind, "count": n})

json.dump({
    "name": name,
    "version": version,
    "sha256": h.hexdigest(),
    "source_rev": rev,
    "redactions": redactions,
}, open(out_f, "w", encoding="utf-8"), indent=2, sort_keys=True)
open(out_f, "a", encoding="utf-8").write("\n")
PY

DENY_NAMES="$WORK/deny-names.txt"; DENY_MODELS="$WORK/deny-models.txt"
make_deny_names "$DENY_NAMES"; make_deny_models "$DENY_MODELS"

rev_for() { # <dir> — the source revision the copy was built from
  git -C "$1" rev-parse --short HEAD 2>/dev/null || printf 'unknown'
}

redact_file() { # <src> <dst> <report>
  mkdir -p "$(dirname "$2")"
  case "$1" in
    *.md|*.txt|*.yaml|*.yml|*.json|*.sh|*.py|*.toml|*.ini|*.cfg|*.example|*.template)
      python3 "$WORK/redact.py" "$1" "$2" "$DENY_NAMES" "$DENY_MODELS" "$3" ;;
    *) # a binary is not inspected, so it does not travel: an uninspected file is a leak with
       # a good excuse. The reason is recorded rather than silently dropped.
      printf 'skipped-binary\t1\t%s\n' "$1" >> "$3" ;;
  esac
}

strip_results() { # <src> <dst> — method-only: cut the sections that carry our runs
  awk '
    /^#{1,6}[[:space:]]/ {
      hdr = tolower($0)
      if (hdr ~ /result|bench|runs?\b|measurement|inventory|ledger|history|scores?\b|numbers\b/) { cut = 1; next }
      cut = 0
    }
    cut { next }
    { print }
  ' "$1" > "$2"
}

build_one() { # <name> <form> <reason>
  local name="$1" form="$2" reason="$3" dir vis
  dir="$(skill_dir_for "$name")"
  if [ -z "$dir" ]; then
    finding "not found" "$name" "share.yaml names it, no shelf declares it — a share list may not invent a skill"
    return
  fi
  vis="$(yget "$dir/skill.yaml" visibility)"
  if [ "$vis" = "private" ]; then
    finding "refused" "$name" "visibility: private — a share entry cannot overrule the skill's own declaration"
    return
  fi
  local dest="$BUILD/$name" report="$WORK/$name.redactions"
  : > "$report"
  mkdir -p "$dest"
  local rev; rev="$(rev_for "$dir")"

  case "$form" in
    skill)
      redact_file "$dir/SKILL.md" "$dest/SKILL.md" "$report"
      for d in templates assets; do
        [ -d "$dir/$d" ] || continue
        while IFS= read -r f; do
          redact_file "$f" "$dest/$d/$(basename "$f")" "$report"
        done < <(find "$dir/$d" -type f | sort)
      done ;;
    method-only)
      strip_results "$dir/SKILL.md" "$WORK/method.md"
      redact_file "$WORK/method.md" "$dest/SKILL.md" "$report"
      [ -d "$dir/templates" ] && while IFS= read -r f; do
        redact_file "$f" "$dest/templates/$(basename "$f")" "$report"
      done < <(find "$dir/templates" -type f | sort) ;;
    templates-only)
      # No argument travels: a stub carries the declaration so `skills_get` still answers.
      { sed -n '/^---$/,/^---$/p' "$dir/SKILL.md"; printf '\nOnly the templates of this skill are shared.\n'; } \
        | python3 "$WORK/redact.py" /dev/stdin "$dest/SKILL.md" "$DENY_NAMES" "$DENY_MODELS" "$report"
      [ -d "$dir/templates" ] && while IFS= read -r f; do
        redact_file "$f" "$dest/templates/$(basename "$f")" "$report"
      done < <(find "$dir/templates" -type f | sort) ;;
    *)
      finding "bad form" "$name" "form '$form' is not skill · method-only · templates-only"; return ;;
  esac

  python3 "$WORK/manifest.py" "$dest" "$name" "$(yget "$dir/skill.yaml" version)" "$rev" \
    "$report" "$dest/manifest.json"
  printf '  "%s","%s","%s","%s"\n' "$name" "$form" "$rev" "$(ls -R "$dest" | wc -l)"
}

printf 'share_build[1]{share_list,out,mode}:\n  "%s","%s","%s"\n' "$SHARE_FILE" "$OUT" "$([ "$CHECK" = 1 ] && echo check || echo build)"
printf 'published[4]{skill,form,source_rev,files}:\n'
while IFS=$'\t' read -r name form reason; do
  [ -n "$name" ] || continue
  build_one "$name" "$form" "$reason"
done < <(share_entries "$SHARE_FILE")

# index.json — what the door reports it loaded, so a collaborator can see the set and its hashes
python3 - "$BUILD" <<'PY'
import json, os, sys
root = sys.argv[1]
rows = []
for name in sorted(os.listdir(root)):
    m = os.path.join(root, name, "manifest.json")
    if not os.path.isfile(m):
        continue
    d = json.load(open(m, encoding="utf-8"))
    rows.append({"name": d["name"], "version": d["version"], "sha256": d["sha256"]})
json.dump({"version": 1, "count": len(rows), "skills": rows}, open(os.path.join(root, "index.json"), "w", encoding="utf-8"), indent=2)
open(os.path.join(root, "index.json"), "a").write("\n")
PY

# ── the ward over the built tree: the last word is a refusal, not a review ──────
WARD="$ROOT/bin/gates/guards/skills-share-guard.sh"
WARD_ARGS=(--root "$BUILD" --names "$DENY_NAMES" --models "$DENY_MODELS")
if [ -x "$WARD" ]; then
  ward_out="$(bash "$WARD" "${WARD_ARGS[@]}" 2>&1)"; ward_rc=$?
else
  ward_out="the ward is missing: bin/gates/guards/skills-share-guard.sh"; ward_rc=1
fi
if [ "$ward_rc" -ne 0 ]; then
  # A refusal must say what it refused: the ward's own rows, then its remaining words.
  printf '%s\n' "$ward_out" | grep -E '^  "' | awk -F'","' 'NF == 4' | head -20 || true
  printf '%s\n' "$ward_out" | grep -vE '^  "' | grep -vE '^skills_share_(guard|findings)' | head -5 || true
  FINDINGS=$((FINDINGS + 1))
  printf '  "the ward refused the built tree","published/","the redactor cannot rewrite what it cannot name — reword the skill, or declare the pattern the ward is missing"\n'
fi

if [ "$CHECK" = 1 ]; then
  if [ -d "$OUT" ]; then
    drift="$(diff -r "$OUT" "$BUILD" 2>&1 || true)"
    if [ -n "$drift" ]; then
      printf '  "published/ is stale","%s","%s"\n' "$OUT" "rebuild: bin/skills/share-build.sh"
      FINDINGS=$((FINDINGS + 1))
    fi
  else
    printf '  "published/ does not exist yet","%s","build it: bin/skills/share-build.sh"\n' "$OUT"
    FINDINGS=$((FINDINGS + 1))
  fi
  printf 'share_build: %s finding(s)\n' "$FINDINGS"
  [ "$FINDINGS" -eq 0 ] || exit 1
  exit 0
fi

if [ "$FINDINGS" -ne 0 ]; then
  printf 'share_build: %s finding(s) — published/ was NOT replaced\n' "$FINDINGS"
  exit 1
fi

mkdir -p "$(dirname "$OUT")"
rm -rf "$OUT.new" && cp -a "$BUILD" "$OUT.new" && rm -rf "$OUT" && mv "$OUT.new" "$OUT"
cp -f "$DENY_NAMES" "$SHARE_DIR/deny-names.txt" 2>/dev/null || true
cp -f "$DENY_MODELS" "$SHARE_DIR/deny-models.txt" 2>/dev/null || true
printf 'share_build: %s skill(s) published to %s\n' "$(find "$OUT" -name manifest.json | wc -l)" "$OUT"
