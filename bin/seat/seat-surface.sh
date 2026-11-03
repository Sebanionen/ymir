#!/usr/bin/env bash
# seat-surface.sh — render THIS seat's own name into the AGENTS.md every harness reads.
#
#   bin/seat/seat-surface.sh            render the seat file and point every harness at it
#   bin/seat/seat-surface.sh --check    exit 1 when a surface is not the seat's own
#
# WHY (the Allfather, 2026-11-03): *"every machine and user needs to have their own
# names for that agent … it comes a lot of conflicts when several of Brokk exists.
# That needs to be a ymir home config that gets into all tools' AGENTS.md globally
# in installs and updates if they are still named Brokk."*
#
# The shared contract (the repo's AGENTS.md) names the counsellor's craft — Brokk.
# A seat whose primary is a different figure (Sindri on the smith's seat, Kvasir on
# compute, Forseti on the ledger) must NOT answer to that name. So the seat's name is
# a HOME CONFIG (`$YMIR_HOME/hodd/identity/seats.yaml`, read by seat-identity.sh) and
# this door renders it ABOVE the shared contract into one file —
# `~/.pi/agent/AGENTS.seat.md` — then points every harness instruction file at it.
#
# It NEVER writes the public repo. The repo contract stays shared; only the machine's
# copy carries the seat's name. Idempotent: safe in install and in every update.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SID="$ROOT/bin/agents/seat-identity.sh"
HOST="${YMIR_HOST:-$(hostname -s)}"
SEAT="$HOME/.pi/agent/AGENTS.seat.md"
if [ -z "${YMIR_HOME:-}" ]; then
  _hoard="$(bash "$ROOT/bin/vault/hodd.sh" path 2>/dev/null || true)"
  [ -n "$_hoard" ] || { printf 'seat-surface: no home — bin/vault/hodd.sh path answered nothing\n' >&2; exit 1; }
  YMIR_HOME="$(dirname "$_hoard")"
fi
export YMIR_HOME

# every file a harness instruction loader reads, where the harness is present
# (Pi · Claude Code · Codex · Cursor · Gemini CLI) — Rule 02: symlinks, never copies.
surfaces() {
  printf '%s\n' \
    "$HOME/.pi/agent/AGENTS.md" \
    "$HOME/.claude/CLAUDE.md" \
    "$HOME/.codex/AGENTS.md" \
    "$HOME/.cursorrules" \
    "$HOME/.gemini/GEMINI.md" \
    "$HOME/.hermes/AGENTS.md"
}

render() {
  [ -x "$SID" ] || { printf 'seat-surface: no seat-identity.sh at %s\n' "$SID" >&2; return 2; }
  bash "$SID" --render "$HOST" >/dev/null 2>&1 || {
    printf 'seat-surface: the seat has no identity in the roster — run bin/agents/seat-identity.sh --ensure\n' >&2
    return 1
  }
  [ -r "$SEAT" ] || { printf 'seat-surface: %s was not rendered\n' "$SEAT" >&2; return 1; }
}

link() {
  local f
  while IFS= read -r f; do
    [ -e "$(dirname "$f")" ] || continue          # the harness is not on this machine
    if [ -L "$f" ] && [ "$(readlink -f "$f")" = "$(readlink -f "$SEAT")" ]; then continue; fi
    # a real file is never overwritten silently: it is moved aside once, by name
    if [ -e "$f" ] && [ ! -L "$f" ]; then
      mv "$f" "$f.pre-seat-surface-$(date +%Y%m%d)" || return 1
      printf 'seat-surface: set aside %s (a real file, kept)\n' "$f" >&2
    fi
    mkdir -p "$(dirname "$f")"
    ln -sfn "$SEAT" "$f" && printf 'seat-surface: %s -> %s\n' "$f" "$(basename "$SEAT")"
  done < <(surfaces)
}

case "${1:-}" in
  -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//;s/^$//' | head -14; exit 0 ;;
  --check)
    render || exit 1
    NAME="$(bash "$SID" "$HOST" 2>/dev/null)"
    bad=0
    head1="$(sed -n '4p' "$SEAT" 2>/dev/null)"
    case "$head1" in *"$NAME"*) printf 'seat-surface: seat file names %s ✓\n' "$NAME" ;; *) printf 'seat-surface: seat file does not name %s\n' "$NAME"; bad=1 ;; esac
    OPERATOR="$(python3 -c "import yaml;d=yaml.safe_load(open('$YMIR_HOME/hodd/identity/operator.yaml'));print((d.get('allfather') or {}).get('display') or 'Allfather')" 2>/dev/null || echo Allfather)"
    if [ -n "$OPERATOR" ] && grep -qF "$OPERATOR" "$SEAT" 2>/dev/null; then
      printf 'seat-surface: seat file names the operator (%s) ✓\n' "$OPERATOR"
    else
      printf 'seat-surface: the operator is not named in the seat file (%s)\n' "${OPERATOR:-<empty>}"; bad=1
    fi
    while IFS= read -r f; do
      [ -e "$(dirname "$f")" ] || continue
      [ -L "$f" ] && [ "$(readlink -f "$f")" = "$(readlink -f "$SEAT")" ] && continue
      printf 'seat-surface: %s does not resolve to the seat file\n' "$f"; bad=1
    done < <(surfaces)
    [ "$bad" -eq 0 ] && printf 'seat-surface: every harness reads %s on %s\n' "$NAME" "$HOST"
    exit "$bad" ;;
  ""|--apply|apply)
    render || exit 1
    link || exit 1
    printf 'seat-surface: %s on %s — %s\n' "$(bash "$SID" "$HOST" 2>/dev/null)" "$HOST" "$(basename "$SEAT")" ;;
  *) printf 'error: unknown action %s\nhelp: seat-surface.sh [--check]\n' "$1" >&2; exit 2 ;;
esac
