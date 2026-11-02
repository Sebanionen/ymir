#!/usr/bin/env bash
# home-seed.sh — make a home that a fresh user can understand, and offer to keep it in git.
#
#   bin/engine/home-seed.sh                 explain, create the skeleton, print what it made
#   bin/engine/home-seed.sh --check         say what is missing, change nothing
#   bin/engine/home-seed.sh --repo          also `git init` it as a PRIVATE repository
#   bin/engine/home-seed.sh --yes           never prompt (takes --repo only when given)
#
# WHY (his word, 2026-11-02): *"if the users are missing ymir home it hsoule make the folders and repo if the
# users wanna. rigtnow it seems like he done understands on a fresch install what ymir home are."*
#
# A new operator is told "everything private lives in your home" and then meets an empty directory they were
# expected to design. This door answers the three questions plainly — WHAT the home is, WHERE it lives, WHAT
# goes in it — creates the skeleton the rest of the house expects, writes the two documents that explain it,
# and offers to make it a private git repository so the home can follow the user to another machine.
#
# It never deletes and never overwrites: a file that exists is left exactly as it is.
set -uo pipefail

ROOT="$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(CDPATH='' cd "$ROOT" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)"
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true

CHECK=0; REPO=0; YES=0; LIST=0
for a in "$@"; do
  case "$a" in
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --list) LIST=1 ;;
    --check) CHECK=1 ;;
    --repo) REPO=1 ;;
    -y|--yes) YES=1 ;;
    *) printf 'error: unknown flag %s\nhelp: home-seed.sh [--check|--repo|--yes]\n' "$a" >&2; exit 2 ;;
  esac
done

CONTRACT="$ROOT/.agents/home-contract.yaml"

# THE ONE PARSER of the home contract (RULES/42). Every row says where a file goes, whether it is seeded, a
# stub, defaulted, optional or generated, which template ships it, and which door writes it. Two parsers would be
# two truths, so bin/gates/checks/home-contract-check.sh calls THIS one with --list.
contract_rows() {  # prints: path<TAB>kind<TAB>template<TAB>door<TAB>required
  [ -r "$CONTRACT" ] || return 1
  python3 - "$CONTRACT" <<'PY2'
import sys
try:
    import yaml
except Exception:
    sys.exit(1)
d = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
for r in d.get("contract") or []:
    if not isinstance(r, dict):
        continue
    path = r.get("path")
    if not path:
        continue
    print("%s\t%s\t%s\t%s\t%s" % (
        path, r.get("kind", ""), r.get("template", "-"), r.get("door", "-"),
        "true" if r.get("required") in (True, "true") else "false"))
PY2
}

if [ "${LIST:-0}" = "1" ]; then
  out=$(contract_rows) || { printf 'home-contract-check[1]{finding,detail}:\n  "no contract","%s"\n' "$CONTRACT" >&2; exit 1; }
  [ -n "$out" ] || { printf 'home-contract-check[1]{finding,detail}:\n  "the contract lists no rows","%s"\n' "$CONTRACT" >&2; exit 1; }
  printf '%s\n' "$out"
  exit 0
fi

home=""
declare -f ymir_home_root >/dev/null 2>&1 && ymir_home_root home 2>/dev/null
# No guessed home (RULES/07): env → the resolver → the ONE documented default, stated as a decision.
if [ -z "$home" ]; then
  home="${YMIR_HOME:-}"
fi
if [ -z "$home" ]; then
  printf 'home_seed[1]{finding,detail}\n  "no home resolved","set YMIR_HOME (or install with bin/engine/ymir-install.sh, which records it)"\n' >&2
  exit 2
fi

# The skeleton the rest of the house reads. Nothing exotic — every one of these is named by a door.
DIRS="
hodd
hodd/identity
hodd/data
hodd/memory
hodd/memory/daily
hodd/plans
hodd/secrets
hodd/state
hodd/docs
hodd/workspaces
hodd/reference
config
state
"

printf 'home[1]{what}\n'
printf '  "Your home is the ONE private place Ymir keeps: identity, memory, plans, secrets, documents and the\n'
printf '   workspaces you own. It is NOT the code tree and never inside it — the code is public, the home is\n'
printf '   yours. It can be moved, backed up, or kept in a private git repository; nothing here is deleted\n'
printf '   by an update."\n'
printf 'home[1]{where}\n'
printf '  "%s"\n' "$home"

missing=()
for d in $DIRS; do
  [ -d "$home/$d" ] || missing+=("$d")
done

if [ "${#missing[@]}" -eq 0 ]; then
  printf 'home_seed[1]{state,detail}\n  "complete","every directory the house expects is already here"\n'
else
  printf 'home_seed[%s]{missing,action}\n' "${#missing[@]}"
  for d in "${missing[@]}"; do printf '  "%s","create"\n' "$d"; done
  if [ "$CHECK" = 1 ]; then
    printf 'home_seed[1]{state}\n  "incomplete","run bin/engine/home-seed.sh without --check to lay it out"\n'
    exit 0
  fi
  mkdir -p "$home"
  for d in "${missing[@]}"; do mkdir -p "$home/$d"; done
  printf 'home_seed[1]{state,detail}\n  "created","%s director%s under %s"\n' "${#missing[@]}" \
    "$([ "${#missing[@]}" -eq 1 ] && echo y || echo ies)" "$home"
fi

[ "$CHECK" = 1 ] && exit 0

# ── the shapes the runtime READS: seeded once from the template, never overwritten ──
if rows=$(contract_rows); then
  realm=""
  [ -r "$home/hodd/data/realm.md" ] && realm=$(sed -n 's/^realm:[[:space:]]*//p' "$home/hodd/data/realm.md" | head -1)
  [ -n "$realm" ] || realm="work"
  seeded=0; stubbed=0; kept=0
  while IFS=$'\t' read -r cpath kind tmpl door required; do
    [ -n "$cpath" ] || continue
    dest="${cpath//\{realm\}/$realm}"
    case "$kind" in
      seeded|stub|defaulted) ;;
      *) continue ;;                       # generated: a door writes it; optional: no template owed
    esac
    [ "$tmpl" = "-" ] && continue
    if [ -f "$home/$dest" ]; then kept=$((kept+1)); continue; fi
    if [ ! -f "$ROOT/$tmpl" ]; then
      printf 'home_seed[1]{missing,template}\n  "%s","%s ships no file — the row promises a shape that is not there"\n' "$dest" "$tmpl"
      continue
    fi
    mkdir -p "$(dirname "$home/$dest")"
    cp "$ROOT/$tmpl" "$home/$dest"
    case "$kind" in stub) stubbed=$((stubbed+1)) ;; *) seeded=$((seeded+1)) ;; esac
  done <<< "$rows"
  printf 'home_seed[1]{contract,detail}\n  "%s seeded · %s stubs copied · %s already present (never overwritten)"\n' \
    "$seeded" "$stubbed" "$kept"
fi

# ── the two documents that answer "what is this?" without a person standing beside the user ──
if [ ! -f "$home/README.md" ]; then
  cat > "$home/README.md" <<'EOF'
# My Ymir home

This is the **one private place** Ymir keeps on this machine: my identity, memory, plans, secrets, documents and
workspaces. It is deliberately **outside** the Ymir code tree — the code is public, this is mine.

```
README.md       this page
hodd/           the hoard: everything private, by shelf
  identity/       who I am, my companies, my collaborators and projects
  data/           what this machine knows: fleet, machines, operator preferences
  memory/         the well, the daily log, the runes ledger
  plans/          my own working plans (personal only)
  secrets/        the vault — encrypted; referenced by path, never inlined
  docs/           the curated knowledge shelf (docs/INDEX.md is the door)
  state/          what is running right now
  workspaces/     the work itself
config/         per-machine configuration (agents, runtime, services)
state/          locks and queue files
AGENTS.md       my private contract — optional; the public one is in the code tree
```

**Keep it private.** If this home is a git repository, make it a **private** one. Never commit a decrypted
secret; `hodd/secrets/platform.env.age` may be committed, a plaintext `platform.env` may not.

**Move it, do not delete it.** An update never removes anything here; to carry it to another machine, copy the
whole directory (or push the private repository) and point `YMIR_HOME` at it.
EOF
  printf 'home_seed[1]{wrote,file}\n  "README.md","plain words for a person who has just arrived"\n'
fi

if [ ! -f "$home/.gitignore" ]; then
  cat > "$home/.gitignore" <<'EOF'
# Never commit a secret in the clear. The encrypted form (*.age) may be committed; these may not.
hodd/secrets/*.env
hodd/secrets/*.plain
hodd/secrets/age.key
hodd/secrets/*.key
# Runtime churn
state/
*.lock
*.pid
*.log
# Editor and OS noise
.DS_Store
__pycache__/
*.pyc
EOF
  printf 'home_seed[1]{wrote,file}\n  ".gitignore","the small list that keeps a secret out of a commit"\n'
fi

# ── the optional private repository ──────────────────────────────────────────
if [ "$REPO" = 1 ] || { [ "$YES" = 0 ] && [ -t 0 ]; }; then
  if [ ! -d "$home/.git" ] && command -v git >/dev/null 2>&1; then
    want=0
    if [ "$REPO" = 1 ]; then want=1
    else
      printf '\nKeep this home in a git repository, so it can follow you to another machine?\n'
      printf 'It must be a PRIVATE repository — the home is not public. [y/N]: '
      IFS= read -r answer || true
      case "${answer:-}" in y|Y|yes|YES) want=1 ;; esac
    fi
    if [ "$want" = 1 ]; then
      ( cd "$home" && git init -q && git add README.md .gitignore 2>/dev/null && \
        git -c user.name="$(git config user.name 2>/dev/null || echo ymir)" \
            -c user.email="$(git config user.email 2>/dev/null || echo ymir@localhost)" \
            commit -q -m "the home: private, and explained" 2>/dev/null ) \
        && printf 'home_seed[1]{repo,detail}\n  "initialised","%s — commit the shelves as you fill them, and PUSH IT PRIVATE"\n' "$home" \
        || printf 'home_seed[1]{repo,detail}\n  "skipped","git init ran but the first commit did not; the directory is ready"\n'
    else
      printf 'home_seed[1]{repo,detail}\n  "declined","no repository — the home is still usable, and --repo will make one later"\n'
    fi
  elif [ -d "$home/.git" ]; then
    printf 'home_seed[1]{repo,detail}\n  "already a repository","%s"\n' "$home"
  fi
fi

printf 'home_seed[1]{next,detail}\n  "point Ymir at it","YMIR_HOME=%s — the installer records this so later runs need not ask"\n' "$home"
exit 0
