#!/usr/bin/env bash
# review-rules.sh — the rules floor: load what a reviewer MUST know, or refuse to review.
#
# WHY (plan 203 §11): a reviewer that does not hold the project's law passes work that breaks it, and does so
# politely, with a green tick. So the floor is loaded BEFORE the diff, its files are hashed, and a missing file
# is a REFUSAL — never a skip.
#
#   bin/forge/review-rules.sh <repo>            # load the floor, print it with the ruleset hash
#   bin/forge/review-rules.sh <repo> --quiet    # exit 0/1 only, for a gate
#   bin/forge/review-rules.sh <repo> --quote <rule> "the finding"
#                                               # a refusal in the house's own shape: rule, file, line
#
# Exit: 0 the floor is complete · 1 a source is missing (the refusal names it) · 2 usage.
set -uo pipefail
REPO="${1-}"; shift || true
Q=0; QUOTE=""; FINDING=""
case "${1-}" in --quiet) Q=1 ;; --quote) QUOTE="${2-}"; FINDING="${3-}" ;; esac
[ -n "$REPO" ] && [ -d "$REPO" ] || { printf 'usage: review-rules.sh <repo> [--quiet|--quote <rule> <finding>]\n' >&2; exit 2; }
REPO="$(cd "$REPO" && pwd)"
DECL="$REPO/.review-rules.yaml"

if [ -n "$QUOTE" ]; then
  # A refusal is not an opinion: it names the rule, the file it came from, and the finding.
  printf 'review-refusal[3]{rule,source,finding}:\n  "%s","%s",«%s»\n' "$QUOTE" "$DECL" "$FINDING"
  exit 1
fi

if [ ! -f "$DECL" ]; then
  [ "$Q" = 1 ] && exit 1
  printf 'review-rules: REFUSED — no .review-rules.yaml in %s\n' "$REPO" >&2
  printf 'review-rules: the reviewer cannot know what this project forbids\n' >&2
  exit 1
fi

# the two roots a source may resolve in, resolved ONCE by the house resolver (never guessed here)
ROOT_YMIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RR_YMIR_HOME=""
if [ -r "$ROOT_YMIR/bin/vault/hoard-lib.sh" ]; then
  # shellcheck disable=SC1091
  . "$ROOT_YMIR/bin/vault/hoard-lib.sh" 2>/dev/null || true
  ymir_home_root RR_YMIR_HOME 2>/dev/null || RR_YMIR_HOME=""
fi
export RR_YMIR_TREE="$ROOT_YMIR" RR_YMIR_HOME

python3 - "$REPO" "$DECL" "$Q" <<'PY'
import datetime
import hashlib
import socket, os, re, sys

repo, decl, quiet = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
text = open(decl, encoding="utf-8").read()

def section(name: str) -> list[str]:
    out, on = [], False
    for line in text.splitlines():
        if re.match(rf"^{name}:", line):
            on = True; continue
        if on:
            if re.match(r"^[a-z_]+:", line):
                break
            m = re.match(r"^\s*-\s*(\S.*)$", line)
            if m:
                item = m.group(1).split("#")[0].strip().strip('"')
                if item:
                    out.append(item)
    return out

sources = section("rules") + section("house_law")
missing = []
digest = hashlib.sha256()

# A project repo is not the house: RULES/ lives in the ymir tree, and the plan ledger lives in the home.
# So a source resolves in three places, in this order, and a source that resolves in NONE is a refusal.
# Rule 07: neither home is guessed. review-rules.sh hands both in, resolved by the house's own resolver.
YMIR_TREE = os.environ["RR_YMIR_TREE"]
YMIR_HOME = os.environ["RR_YMIR_HOME"]

def resolve(rel: str) -> str | None:
    for base in (repo, YMIR_TREE, YMIR_HOME):
        candidate = os.path.join(base, rel)
        if os.path.isdir(candidate) or os.path.isfile(candidate):
            return candidate
    return None

for rel in sources:
    path = resolve(rel)
    if path is None:
        missing.append(rel)
        continue
    if os.path.isdir(path):
        for root, _dirs, files in os.walk(path):
            for f in sorted(files):
                if f.endswith(".md"):
                    digest.update(f.encode())
                    digest.update(open(os.path.join(root, f), "rb").read())
        continue
    if not os.path.isfile(path):
        missing.append(rel)
        continue
    digest.update(rel.encode())
    digest.update(open(path, "rb").read())

plan_ledger = ""
m = re.search(r"^plan_ledger:\s*(\S+)", text, re.M)
if m:
    plan_ledger = m.group(1)
    if resolve(plan_ledger) is None:
        missing.append(plan_ledger)

freeze, forbidden = section("freeze"), section("forbidden")

if missing:
    if not quiet:
        print(f"review-rules: REFUSED — {len(missing)} source(s) missing from {repo}")
        for rel in missing:
            print(f"  missing  {rel}")
        print("review-rules: a missing rule file is a refusal, never a skip")
    sys.exit(1)

if not quiet:
    # The hash is NOT a portable identifier, and printing it as one cost a whole night's
    # comparing (2026-11-06): two seats read the same law and printed f7c802a0… and
    # f224f614… because source #4 is the PLAN LEDGER and one of them had appended a plan.
    # So the facts carry WHERE and WHEN, and the record must quote all three: a ruleset
    # number with no seat and no time names nothing.
    print(f"review-rules[7]{{facts,value}}:")
    print(f'  "repo","{repo}"')
    print(f'  "sources",{len(sources)}')
    print(f'  "frozen",{len(freeze)}')
    print(f'  "forbidden",{len(forbidden)}')
    print(f'  "ruleset","{digest.hexdigest()[:16]}"')
    print(f'  "seat","{socket.gethostname()}"')
    print(f'  "at","{datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}"')
    print("review-rules: the floor is complete — the law is read before the diff")
    print("note: the ruleset hash is PER SEAT and PER MOMENT (source 4 is the plan ledger, which "
          "grows) — a review record carries ruleset + seat + at, never the number alone")
PY
