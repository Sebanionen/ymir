#!/usr/bin/env bash
# public-data-guard.sh — the TREE scan for RULES/04: templates and logic, and nothing private.
#
# The public repository may carry templates (`*.example`, schemas, synthetic names) and logic (the
# code that reads the home at run time). It may not carry a secret, the operator's own words, a
# private address or a personal mailbox — "whether or not they are a secret", and "not as a value,
# not as an example filled with the real thing" (RULES/04, 2026-10-01).
#
# This is the WARD in the one list (`bin/gates/guards.sh`); the judgement itself lives in
# public-guard.py, so a person can run either and get the same answer:
#
#   bin/gates/guards/public-data-guard.sh          # every tracked file
#   python3 bin/gates/guards/public-guard.py --list # the four classes and what each allows
#
# Exit: 0 clean · 1 findings · 2 usage.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
exec python3 "$ROOT/bin/gates/guards/public-guard.py" --tree
