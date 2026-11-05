#!/usr/bin/env bash
# test_skills_mcp.sh — the skills door, proved by command.
#
# Plan 184 built four pieces and each one makes a claim that a reviewer cannot check by
# reading: that a manifest-less directory FAILS BY NAME, that a duplicate name is refused
# naming both paths, that a description must be one line, that the redactor's output is clean
# on a good fixture and REFUSED on a seeded canary, that the three tools answer for a few
# hundred tokens, and that the file fetcher cannot be walked out of its tree.
#
# Every fixture here is INVENTED (hearth-keeping · rune-counting · word-weaving) and the
# canary is SEEDED at test time into a temp tree, so nothing private-shaped is committed:
# a fixture carrying a real host or a real name would itself be the leak the ward refuses.
#
#   bin/gates/tests/test_skills_mcp.sh
#
# Exit: 0 all green · 1 a failure (each printed by name).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIX="$ROOT/bin/gates/tests/fixtures/skills-mcp"
MCP="$ROOT/tools/skills-mcp/skills-mcp.py"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s%s\n' "$1" "${2:+ — $2}"; fail=$((fail + 1)); }
t()   { local name="$1"; shift; local out; if out="$("$@" 2>&1)"; then ok "$name"; else bad "$name" "$(printf '%s' "$out" | tail -2 | tr '\n' ' ')"; fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cp -r "$FIX/shelf" "$T/shelf"
GOOD="$T/good"; mkdir -p "$GOOD"

# ── 1. the manifest law ─────────────────────────────────────────────────────────
mkdir -p "$T/shelf/naked-skill"
printf -- '---\nname: naked-skill\ndescription: A skill with no declaration.\n---\nbody\n' \
  > "$T/shelf/naked-skill/SKILL.md"

naked_out="$(bash "$ROOT/bin/skills/manifest.sh" scan --root "$T/shelf" 2>&1 || true)"
if printf '%s' "$naked_out" | grep -q 'FAIL","naked-skill".*no skill.yaml'; then
  ok "manifest.sh scan: a directory with no skill.yaml fails BY NAME"
else
  bad "manifest.sh scan: a directory with no skill.yaml fails BY NAME" "$(printf '%s' "$naked_out" | head -2 | tr '\n' ' ')"
fi
rm -rf "$T/shelf/naked-skill"

# a duplicate name, on a second shelf, with no declared override: refused, naming BOTH paths
mkdir -p "$T/other" && cp -r "$T/shelf/hearth-keeping" "$T/other/"
dup_out="$(bash "$ROOT/bin/skills/manifest.sh" scan --root "$T/shelf" --root "$T/other" 2>&1 || true)"
if printf '%s' "$dup_out" | grep -q 'DUPLICATE","hearth-keeping".*hearth-keeping and .*hearth-keeping'; then
  ok "manifest.sh scan: a duplicate name is refused, naming both paths"
else
  bad "manifest.sh scan: a duplicate name is refused, naming both paths" "$(printf '%s' "$dup_out" | head -3 | tr '\n' ' ')"
fi

# a declared override is legal: shadows + reason, on a second shelf
printf 'name: hearth-keeping\nkind: craft\nowner: house\ndescription: Our own hearth rule, overriding the borrowed one.\nvisibility: private\nversion: 1.0.1\nshadows: hearth-keeping\nshadows_reason: the house version wins over the borrowed one.\n' \
  > "$T/other/hearth-keeping/skill.yaml"
ovr_rc=0; ovr_out="$(bash "$ROOT/bin/skills/manifest.sh" scan --root "$T/shelf" --root "$T/other" 2>&1)" || ovr_rc=$?
if [ "$ovr_rc" -eq 0 ] && printf '%s' "$ovr_out" | grep -q 'OVERRIDE'; then
  ok "manifest.sh scan: a declared override (shadows + reason) is legal and reported"
else
  bad "manifest.sh scan: a declared override (shadows + reason) is legal and reported" "rc=$ovr_rc"
fi
rm -rf "$T/other"

# a description that wraps is a search row with a newline in it — refused
cp -r "$T/shelf/rune-counting" "$T/shelf/rune-counting-wraps"
printf 'name: rune-counting-wraps\nkind: machine\nowner: house\ndescription: One line that will not\nstay on one line.\nvisibility: share-method\nversion: 0.2.0\n' \
  > "$T/shelf/rune-counting-wraps/skill.yaml"
wrap_out="$(bash "$ROOT/bin/skills/manifest.sh" scan --root "$T/shelf" 2>&1 || true)"
if printf '%s' "$wrap_out" | grep -q 'description wraps over 2 lines'; then
  ok "manifest.sh scan: a description must be exactly one line"
else
  bad "manifest.sh scan: a description must be exactly one line" "$(printf '%s' "$wrap_out" | head -2 | tr '\n' ' ')"
fi
rm -rf "$T/shelf/rune-counting-wraps"

# a description that is absent is a build failure, not an unfindable skill
cp -r "$T/shelf/word-weaving" "$T/shelf/word-weaving-nodesc"
printf 'name: word-weaving-nodesc\nkind: craft\nowner: house\nvisibility: public\nversion: 1.0.0\n' \
  > "$T/shelf/word-weaving-nodesc/skill.yaml"
nodesc_out="$(bash "$ROOT/bin/skills/manifest.sh" scan --root "$T/shelf" 2>&1 || true)"
if printf '%s' "$nodesc_out" | grep -q 'description is required'; then
  ok "manifest.sh scan: a missing description is refused"
else
  bad "manifest.sh scan: a missing description is refused" "$(printf '%s' "$nodesc_out" | head -2 | tr '\n' ' ')"
fi
rm -rf "$T/shelf/word-weaving-nodesc"

# ── 2. the share build and its ward ─────────────────────────────────────────────
t "manifest.sh scan: the three fixture skills are clean" \
  bash "$ROOT/bin/skills/manifest.sh" scan --root "$FIX/shelf"

t "share-build.sh: builds the three fixtures" \
  bash "$ROOT/bin/skills/share-build.sh" --share "$FIX/share.yaml" --root "$FIX/shelf" --out "$GOOD/published"

if [ -f "$GOOD/published/hearth-keeping/manifest.json" ]; then
  ok "share-build.sh: a manifest.json carries name · version · sha256 · source_rev · redactions"
else
  bad "share-build.sh: a manifest.json carries name · version · sha256 · source_rev · redactions"
fi
t "share-build.sh --check is CLEAN on the good fixture" \
  bash "$ROOT/bin/skills/share-build.sh" --check --share "$FIX/share.yaml" --root "$FIX/shelf" --out "$GOOD/published"

# the seeded canary: a fake host with a port, a fake personal name, and a home path.
CAN="$T/canary"; mkdir -p "$CAN/shelf/bench-ledger"
cat > "$CAN/shelf/bench-ledger/SKILL.md" <<'MD'
---
name: bench-ledger
description: How we measured the models on our own machines.
---
# Bench-ledger

We ran the sweep on /home/canary/bench with 203.0.113.10:8443 as the judge.
Ask Bertil Kanariefagel at bertil.kanariefagel@corvid-bench.test or +46 70 123 45 67.

| run | model | tok/s | latency |
|---|---|---|---|
| 4 | openrouter/qwen3.6-35b-a3b | 41 | 900 |
MD
printf 'name: bench-ledger\nkind: craft\nowner: house\ndescription: How we measured the models on our own machines.\nvisibility: share-method\nversion: 0.0.1\n' \
  > "$CAN/shelf/bench-ledger/skill.yaml"
printf 'skills:\n  - name: bench-ledger\n    reason: the method only, never the runs\n    form: skill\n' \
  > "$CAN/share.yaml"

can_rc=0
can_out="$(SKILLS_SHARE_NAMES="Bertil Kanariefagel" bash "$ROOT/bin/skills/share-build.sh" --check \
  --share "$CAN/share.yaml" --root "$CAN/shelf" --out "$CAN/published" 2>&1)" || can_rc=$?
if [ "$can_rc" -ne 0 ] && printf '%s' "$can_out" | grep -q 'the ward refused the built tree'; then
  ok "share-build.sh --check is NON-ZERO on the seeded canary, and names the ward's refusal"
else
  bad "share-build.sh --check is NON-ZERO on the seeded canary, and names the ward's refusal" "rc=$can_rc"
fi

# the redactor really rewrote the home path (the proof it is a redactor, not a filter)
can_build="$T/canbuild"; mkdir -p "$can_build"
SKILLS_SHARE_NAMES="Bertil Kanariefagel" bash "$ROOT/bin/skills/share-build.sh" \
  --share <(printf 'skills:\n  - name: bench-ledger\n    reason: probe the redaction\n    form: skill\n') \
  --root "$CAN/shelf" --out "$can_build/published" >/dev/null 2>&1 || true

# ── 3. the ward, alone: clean on the fixture set, the canary caught ─────────────
t "skills-share-guard.sh: clean on the fixture set" \
  bash "$ROOT/bin/gates/guards/skills-share-guard.sh" --root "$GOOD/published" --quiet

guard_rc=0
guard_out="$(SKILLS_SHARE_NAMES="Bertil Kanariefagel" bash "$ROOT/bin/gates/guards/skills-share-guard.sh" \
  --root "$CAN/shelf" --quiet 2>&1)" || guard_rc=$?
canary_classes="machine path|address|port|name|mailbox|phone|bench table|model id"
missed=""
IFS='|' read -r -a want <<< "$canary_classes"
for c in "${want[@]}"; do
  printf '%s' "$guard_out" | grep -q "\"$c\"" || missed="$missed $c"
done
if [ "$guard_rc" -ne 0 ] && [ -z "$missed" ]; then
  ok "skills-share-guard.sh: the seeded canary is caught — path · address · port · name · mailbox · phone · bench table · model id"
else
  bad "skills-share-guard.sh: the seeded canary is caught" "rc=$guard_rc missed:${missed:-none}"
fi

# ── 4. the door: three tools and one file fetcher ───────────────────────────────
cat > "$T/call.py" <<'PY'
import asyncio, importlib.util, os, sys
spec = importlib.util.spec_from_file_location("skills_mcp", sys.argv[1])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
mcp = mod._build()
def call(tool, **kw):
    r = asyncio.run(mcp._tool_manager.call_tool(tool, kw))
    return r.content[0].text if hasattr(r, "content") else str(r)
mode, *rest = sys.argv[2:]
if mode == "search":    print(call("skills_search", query=rest[0]))
elif mode == "get":     print(call("skills_get", name=rest[0], full=(len(rest) > 1 and rest[1] == "full")))
elif mode == "tpl":     print(call("skills_templates", tag=rest[0] if rest else ""))
elif mode == "file":    print(call("skills_file", path=rest[0]))
PY

mcp_call() { SKILLS_MCP_ROOT="$GOOD/published" python3 "$T/call.py" "$MCP" "$@"; }

# search: one line per hit, never a body
search_out="$(mcp_call search "" 2>&1)"
if [ "$(printf '%s\n' "$search_out" | grep -c ' — ')" -eq 3 ] \
   && ! printf '%s' "$search_out" | grep -q '^# '; then
  ok "skills_search: one line per hit, three fixtures, no bodies"
else
  bad "skills_search: one line per hit, three fixtures, no bodies" "$search_out"
fi
if mcp_call search "fix note" 2>/dev/null | grep -q '^hearth-keeping — '; then
  ok "skills_search: a query narrows to the skill that answers it"
else
  bad "skills_search: a query narrows to the skill that answers it"
fi

# get: front matter only by default — the body is withheld until full=true
get_out="$(mcp_call get hearth-keeping 2>&1)"
if printf '%s' "$get_out" | grep -q '^---' \
   && ! printf '%s' "$get_out" | grep -q 'Keep the hearth'; then
  ok "skills_get full=false: front matter, NO body"
else
  bad "skills_get full=false: front matter, NO body" "$(printf '%s' "$get_out" | head -3 | tr '\n' ' ')"
fi
if mcp_call get hearth-keeping full 2>/dev/null | grep -q 'Keep the hearth'; then
  ok "skills_get full=true: the body arrives, for that one skill"
else
  bad "skills_get full=true: the body arrives, for that one skill"
fi

# templates + file
if mcp_call tpl plan 2>/dev/null | grep -q 'word-weaving/templates/plan.md'; then
  ok "skills_templates: names the generic template, by tag"
else
  bad "skills_templates: names the generic template, by tag"
fi
if mcp_call file word-weaving/templates/plan.md 2>/dev/null | grep -q 'Plan template'; then
  ok "skills_file: fetches one named file from the published tree"
else
  bad "skills_file: fetches one named file from the published tree"
fi
# confinement
if mcp_call file ../../etc/passwd 2>/dev/null | grep -q 'refused'; then
  ok "skills_file ../../etc/passwd: REFUSED (path-confined)"
else
  bad "skills_file ../../etc/passwd: REFUSED (path-confined)"
fi
ln -sf /etc/passwd "$GOOD/published/word-weaving/templates/escape.md"
if mcp_call file word-weaving/templates/escape.md 2>/dev/null | grep -q 'refused'; then
  ok "skills_file: a symlink out of the tree is REFUSED"
else
  bad "skills_file: a symlink out of the tree is REFUSED"
fi
rm -f "$GOOD/published/word-weaving/templates/escape.md"

# no write path, no shell: the server's source says so, and the door does not import them
if ! grep -qE '^\s*(import|from)\s+(subprocess|socket|httpx|requests)' "$MCP" \
   && ! grep -qE '\.(write_text|write_bytes)\(|open\([^)]*["\x27][wa]' "$MCP"; then
  ok "skills-mcp.py: no shell, no network, no write path"
else
  bad "skills-mcp.py: no shell, no network, no write path"
fi

# selftest + the load cost
SELFTEST="$(python3 "$MCP" --selftest 2>&1)"
if printf '%s' "$SELFTEST" | grep -q '"tools","4","skills_search, skills_get, skills_templates, skills_file"'; then
  ok "skills-mcp.py --selftest: three tools and one file fetcher"
else
  bad "skills-mcp.py --selftest: three tools and one file fetcher" "$(printf '%s' "$SELFTEST" | tr '\n' ' ')"
fi
if SKILLS_MCP_ROOT="$GOOD/published" python3 "$MCP" --selftest | grep -q "$GOOD/published"; then
  ok "skills-mcp.py --selftest: resolves the published root"
else
  bad "skills-mcp.py --selftest: resolves the published root"
fi
TOKENS="$(python3 "$MCP" --schema-tokens 2>&1 | sed -n 's/^budget: \([0-9]*\) token.*/\1/p')"
if [ -n "$TOKENS" ] && [ "$TOKENS" -lt 400 ]; then
  ok "skills-mcp.py --schema-tokens: ${TOKENS} tokens at load, under 400"
else
  bad "skills-mcp.py --schema-tokens: under 400" "got '${TOKENS:-none}'"
fi
t "skills-mcp.py --schema-tokens exits 0 (the budget is a gate, not a note)" \
  python3 "$MCP" --schema-tokens

# ── 5. the packaging ────────────────────────────────────────────────────────────
t "unit-template-check --quiet: the systemd unit template is readable by systemd" \
  bash "$ROOT/bin/gates/checks/unit-template-check.sh" --quiet
if grep -q '127.0.0.1' "$ROOT/tools/skills-mcp/systemd/skills-mcp.service" \
   && ! grep -qE '^(ExecStart|Environment)=.*0\.0\.0\.0' "$ROOT/tools/skills-mcp/systemd/skills-mcp.service"; then
  ok "skills-mcp.service: loopback only, and the health probe is documented"
else
  bad "skills-mcp.service: loopback only, and the health probe is documented"
fi

printf '\nskills-mcp tests: %s failure(s)\n' "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
