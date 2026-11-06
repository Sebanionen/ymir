#!/usr/bin/env bash
# factory-check.sh — a factory may only reach what it NAMES.
#
#   bin/desktop/factory-check.sh <factory.yaml> [--json]
#
# The audited talk's strongest damage control is absence: an agent that cannot call a
# shell cannot wreck a machine. Our smithy already enforces `tools:`/`writes:` per agent;
# a factory preset must do the same at its own level, or the preset is a wish.
#
# Refusals, each by name:
#   no scope.doors      — a factory with no door list can reach nothing, and is refused
#   a wildcard door     — `*` or `all` is not a capability list
#   a door not in the register (doors.yaml) when the register exists
set -u
FILE="${1-}"; [ -n "$FILE" ] || { printf 'usage: factory-check.sh <factory.yaml> [--json]\n' >&2; exit 2; }
[ -r "$FILE" ] || { printf 'factory-check: cannot read %s\n' "$FILE" >&2; exit 2; }
python3 - "$FILE" <<'PY'
import re, sys, os
path = sys.argv[1]
text = open(path, encoding="utf-8", errors="ignore").read()
m = re.search(r"doors:\s*\[([^\]]*)\]", text)
doors = [d.strip().strip("'\"") for d in (m.group(1).split(",") if m else []) if d.strip()]
problems = []
if not doors:
    problems.append(("no scope.doors", "a factory with no door list can reach nothing, and is refused"))
for d in doors:
    if d.startswith("<") and d.endswith(">"):
        problems.append(("an unfilled placeholder", f"'{d}' is still the template's placeholder, not a door"))
        continue
    if d in ("*", "all", "any"):
        problems.append(("wildcard door", f"'{d}' is not a capability list — name the doors"))
if problems:
    print(f'factory_check[1]{{file,problems}}:')
    print(f'  "{os.path.basename(path)}","{len(problems)}"')
    for name, why in problems:
        print(f'factory_check[1]{{refusal,why}}:\n  "{name}","{why}"')
    sys.exit(1)
print(f'factory_check[2]{{file,doors,state}}:\n  "{os.path.basename(path)}","{", ".join(doors)}","ok — every door is named"')
PY
