#!/usr/bin/env bash
# test_hermes_seat.sh — the acceptance test for plan 177 H1/H2/H3: Hermes carries the seat, the
# packet and the digest door — proved WITHOUT staging a real model turn.
#
# What it proves (each an `ok` line, exit non-zero on any `FAIL`):
#   · ~/.hermes/SOUL.md carries the marked ymir-seat block and names THIS seat and THIS operator,
#     read from hodd/identity/seats.yaml and operator.yaml — never a hard-coded name;
#   · the seat's declared agent is not Brokk (Rule 44), and a roster that says brokk is refused;
#   · an unseated config is reported as *unnamed*, never invented (a sandbox render, real code);
#   · .hermes.md exists at the repo root, is git-ignored, and names the seat and the operator;
#   · `hermes mcp list` names `ymir` — the packet is seated;
#   · `python3 bin/mcp/ymir-mcp.py --selftest` lists the doors, and the seat file's door list is
#     EXACTLY the packet's (a seat file naming fifteen doors while the packet registers thirty is
#     the drift this house keeps paying for);
#   · the Gná arm's session side is installed and consented (reported as a note, not a failure:
#     the arm has its own door and its own proof).
#
# What it CANNOT prove without a model turn: that the model actually answers as the seat and uses
# the doors. That sentence is the one a human must close with one Hermes session in the repo — the
# test says so rather than pretending.
#
# A machine without Hermes is a CLEAN SKIP with its reason and exit 0 (RULES/25) — never a silent
# pass that pretends it proved something.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=$((fail+1)); }
note(){ printf 'note %s\n' "$1"; }
t()   { local name="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }

SEATFILE="$HOME/.pi/agent/extensions/.ymir-seat"
SOUL="$HOME/.hermes/SOUL.md"
SID="$ROOT/bin/agents/seat-identity.sh"
HERMES_MD="$ROOT/.hermes.md"

if ! command -v hermes >/dev/null 2>&1; then
  printf 'skip  hermes is not installed on this seat — the Hermes surface cannot be proved from\n'
  printf '      outside the harness (RULES/25: a clean skip with its reason is a pass; this proves nothing)\n'
  exit 0
fi

# ── the names, from the operator's own config — never a literal ──────────────────────────────
HOST="${YMIR_HOST:-$(hostname -s)}"
SEAT_NAME="$(bash "$SID" "$HOST" 2>/dev/null || true)"
HOARD="$(bash "$ROOT/bin/vault/hodd.sh" path 2>/dev/null || true)"
HOME_DIR="$(dirname "${HOARD:-/}")"
OPERATOR="$(python3 -c "import yaml,sys;d=yaml.safe_load(open(sys.argv[1])) or {};print((d.get('allfather') or {}).get('display') or '')" \
             "$HOME_DIR/hodd/identity/operator.yaml" 2>/dev/null || true)"
[ -n "$OPERATOR" ] || OPERATOR='<the operator, unnamed in the config>'   # the renderer's own fallback

# ── 0. render from THIS tree, so the assertion is about this code, not a stale artifact ────────
# A second checkout of the repo can re-render the machine's SOUL.md from older code (measured on
# 2026-11-04: the seat file reverted to an older door list mid-errand). The renderer is idempotent, so
# rendering here makes the claim exact: THIS tree's renderer and THIS tree's packet agree.
t "render: the seat surface renders from this tree" bash "$ROOT/bin/seat/seat-surface.sh"

# ── 1. the seat, and the law that no seat is named Brokk ─────────────────────────────────────
t "seat: .ymir-seat is present"                    test -r "$SEATFILE"
t "seat: seat-identity resolves a name"            test -n "$SEAT_NAME"
t "law: this seat is not named Brokk"              bash -c '! printf "%s" "$1" | grep -qix brokk' _ "$SEAT_NAME"
t "law: the roster for this host is not Brokk"     bash -c '! bash "$1" "$2" 2>/dev/null | grep -qix brokk' _ "$SID" "$HOST"

# ── 2. SOUL.md: the marked block, this seat, this operator ──────────────────────────────────
t "soul: the ymir-seat block opens"                grep -qF 'ymir-seat:begin' "$SOUL"
t "soul: the ymir-seat block closes"               grep -qF 'ymir-seat:end' "$SOUL"
t "soul: names this seat ($HOST)"                  grep -qF "**$HOST**" "$SOUL"
t "soul: names the seat primary ($SEAT_NAME)"       grep -qF "**$SEAT_NAME**" "$SOUL"
t "soul: names the operator ($OPERATOR)"           grep -qF "$OPERATOR" "$SOUL"
t "law: the agent SOUL declares is not Brokk"      bash -c '! sed -n "/ymir-seat:begin/,/ymir-seat:end/p" "$1" | grep -m1 "^You are" | grep -qix "You are \*\*brokk\*\*.*"' _ "$SOUL"

# ── 3. the seat file and the packet agree (the drift guard) ─────────────────────────────────
python3 - "$ROOT" "$SOUL" <<'PY' && ok "doors: the seat file lists exactly the packet's doors" || bad "doors: the seat file and the packet disagree"
import re, subprocess, sys
root, soul = sys.argv[1], sys.argv[2]
try:
    out = subprocess.run([sys.executable, root + "/bin/mcp/ymir-mcp.py", "--selftest"],
                         capture_output=True, text=True, timeout=240)
    line = (out.stdout or "").strip().splitlines()[0]
    if not line.startswith("doors:"):
        raise SystemExit(1)
    fields = line.split(":", 1)[1].split(",")
    # "30 <first-door>" shares one field, so the first door is taken from it too
    head = fields[0].split()
    packet = set(head[1:]) | {f.strip() for f in fields[1:] if f.strip()}
except Exception as exc:
    print("      (the packet did not answer: %s)" % exc, file=sys.stderr)
    raise SystemExit(1)
try:
    text = open(soul).read()
except OSError:
    raise SystemExit(1)
found = set(re.findall(r"\bymir_[a-z_]+\b", text))
# doors whose name is not ymir_-prefixed (the packet's own first field) are matched by presence,
# so this door names no door literally — the set is read from the packet in both directions.
found |= {n for n in packet if not n.startswith("ymir_") and n in text}
if packet != found:
    print("      missing from the seat file: %s" % ", ".join(sorted(packet - found)), file=sys.stderr)
    print("      named but not in the packet: %s" % ", ".join(sorted(found - packet)), file=sys.stderr)
    raise SystemExit(1)
PY

# ── 4. .hermes.md at the repo root, machine-local (gitignored), naming the seat ─────────────
t ".hermes.md: exists at the repo root"            test -f "$HERMES_MD"
t ".hermes.md: is git-ignored (Rule 04)"           bash -c 'cd "$1" && git check-ignore -q .hermes.md' _ "$ROOT"
t ".hermes.md: names this seat ($HOST)"            grep -qF "# This seat: $HOST" "$HERMES_MD"
t ".hermes.md: names the operator"                 grep -qF "$OPERATOR" "$HERMES_MD"

# ── 5. the packet is SEATED in Hermes, and the door answers ─────────────────────────────────
t "hermes: mcp list names the ymir packet"         bash -c 'hermes mcp list 2>/dev/null | grep -q "ymir"'
t "packet: --selftest lists the doors"             bash -c '"$1" "$2/bin/mcp/ymir-mcp.py" --selftest | grep -q "^doors:"' _ "$(command -v python3)" "$ROOT"
t "packet: registers 30 doors and ymir_where"      bash -c '"$1" "$2/bin/mcp/ymir-mcp.py" --selftest | head -1 | grep -q "ymir_where" && "$1" "$2/bin/mcp/ymir-mcp.py" --selftest | head -1 | grep -qE "^doors: 3[0-9]"' _ "$(command -v python3)" "$ROOT"
t "packet: the seated ymir server points at a runnable door" bash -c 'python3 - "${YMIR_MCP_ADAPTER:-$HOME/.pi/agent/mcp-adapter.json}" <<"PY"
import json, os, sys
cfg = sys.argv[1]
d = json.load(open(cfg))
srv = (d.get("servers") or d.get("mcpServers") or {}).get("ymir") or {}
argv = [srv.get("command") or ""] + list(srv.get("args") or [])
door = next((a for a in argv if a.endswith("ymir-mcp.py")), "")
raise SystemExit(0 if door and os.access(door, os.R_OK) else 1)
PY'

# ── 6. the arm's session side (reported, not counted: it has its own door) ───────────────────
if bash "$ROOT/bin/pi/arm.sh" hook hermes --check >/dev/null 2>&1; then
  ok "arm: the hermes session hook is installed and consented"
else
  note "the arm's session hook is not installed on this seat — bin/pi/arm.sh hook hermes --install"
fi

# ── 7. an unseated config is UNNAMED, and a brokk roster is refused (real code, sandbox HOME) ─
# A sandbox HOME and a sandbox YMIR_HOME keep this probe off the operator's real files. The one
# file the renderer writes inside the repo is .hermes.md, which is generated and gitignored — it is
# saved and put back exactly, so the probe leaves the tree as it found it.
SAVED_MD="$(mktemp)"; cp "$HERMES_MD" "$SAVED_MD" 2>/dev/null || true
SB=""
restore_md() { [ -s "$SAVED_MD" ] && cp "$SAVED_MD" "$HERMES_MD"; rm -f "$SAVED_MD"; [ -n "$SB" ] && rm -rf "$SB"; }
trap restore_md EXIT INT TERM

sandbox() {  # <primary> <machine_agent-name-or-empty> — renders into a throwaway HOME
  SB="$(mktemp -d)"; mkdir -p "$SB/home/hodd/identity" "$SB/homedir/.hermes" "$SB/homedir/.pi/agent"
  {
    printf 'fleet:\n  name: the sandbox fleet\n  house: sandhouse\nseats:\n  sandhost:\n'
    printf '    primary: %s\n    role: smith\n    status: sealed\n' "$1"
    if [ -n "${2:-}" ]; then printf '    machine_agent:\n      name: %s\n      role: the keeper\n' "$2"; fi
  } > "$SB/home/hodd/identity/seats.yaml"
  printf 'version: 1\n' > "$SB/home/hodd/identity/operator.yaml"
  HOME="$SB/homedir" YMIR_HOME="$SB/home" YMIR_HOST=sandhost \
    bash "$ROOT/bin/seat/seat-surface.sh" >"$SB/out.log" 2>"$SB/err.log"
  SB_RC=$?
  SB_SOUL="$SB/homedir/.hermes/SOUL.md"
}

sandbox huginn ""
if grep -q 'unnamed (the roster has not sealed' "$SB_SOUL" 2>/dev/null; then
  ok "unseated: a machine agent with no sealed name renders as *unnamed*"
else
  bad "unseated: the renderer invented a machine-agent name instead of saying unnamed"
fi
if grep -qF '<the operator, unnamed in the config>' "$SB_SOUL" 2>/dev/null; then
  ok "unseated: an unnamed operator is reported, never invented"
else
  bad "unseated: the operator fallback is missing from the rendered seat"
fi
if grep -qF '**sandhost**' "$SB_SOUL" 2>/dev/null && grep -qF '**huginn**' "$SB_SOUL" 2>/dev/null; then
  ok "unseated: the sandbox seat's own host and primary are still named"
else
  bad "unseated: the sandbox seat's host or primary is not named"
fi
rm -rf "$SB"; SB=""

sandbox brokk ""
if grep -qi 'Brokk is the counsellor ROLE' "$SB/err.log" 2>/dev/null; then
  ok "law: a roster naming this seat Brokk is refused, loudly"
else
  bad "law: a roster naming this seat Brokk was not refused"
fi
if [ -f "$SB_SOUL" ] && grep -qF 'ymir-seat:begin' "$SB_SOUL"; then
  bad "law: the refusal still wrote a Brokk identity into SOUL.md"
else
  ok "law: the refusal writes no Brokk identity into SOUL.md"
fi
rm -rf "$SB"; SB=""

# a host that is not in the roster at all is refused, never given an invented name
if bash "$SID" --render no-such-host-9z 2>/dev/null | grep -q .; then
  bad "unseated: an unknown host was rendered a name"
else
  ok "unseated: an unknown host is refused, never invented"
fi

printf '\nhermes seat: %s failure(s) — the model turn itself is the one proof a script cannot make.\n' "$fail"
exit "$([ "$fail" -eq 0 ] && echo 0 || echo 1)"
