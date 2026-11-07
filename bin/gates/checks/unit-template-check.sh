#!/usr/bin/env bash
# unit-template-check.sh — every shipped systemd unit template must be a unit systemd
# will actually READ.
#
# WHY (2026-10-12): TEN of the thirteen mill templates and FIVE of the six web templates
# placed `StartLimitIntervalSec`/`StartLimitBurst` in `[Service]`. systemd moved those keys
# to `[Unit]` in v230 and IGNORES them anywhere else — one journal line per restart, and
# nothing else:
#
#     mcp-gateway.service:11: Unknown key 'StartLimitIntervalSec' in section [Service], ignoring.
#
# So the restart limit never applied, and mcp-gateway.service looped **2246 times** on a
# stale ExecStart path that no longer existed. **A limit that is silently ignored is worse
# than no limit: it reads as protection.** Only `ymir-syn-watch.service` had it right, which
# is the proof the correct placement was known and the rest simply drifted.
#
# The check is general on purpose: it does not know about StartLimit. It asks systemd to
# verify each rendered template and fails on ANY key, lvalue, or section systemd says it
# will ignore — the whole class, not the one instance.
#
#   bin/gates/checks/unit-template-check.sh           # verify every template
#   bin/gates/checks/unit-template-check.sh --quiet   # only report failures
#
# Non-systemd hosts (macOS, Windows/WSL without systemd) SKIP cleanly: a platform layer is
# gated on its host and reports a clean skip elsewhere (Rule 05), never a false failure.
set -uo pipefail
_root() {
  local d; d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [ "$d" != "/" ]; do
    [ -d "$d/.pi" ] && [ -d "$d/RULES" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
}
ROOT="$(_root)"
cd "$ROOT" || exit 2
QUIET=0; [ "${1:-}" = "--quiet" ] && QUIET=1

if ! command -v systemd-analyze >/dev/null 2>&1; then
  [ "$QUIET" = 1 ] || echo "unit-template-check: skip — no systemd-analyze on this host (not a systemd host)"
  exit 0
fi

files=()
for f in tools/mill/systemd/*.service tools/mill/systemd/*.target \
         tools/web/systemd/*.service  tools/web/systemd/*.target \
         tools/skills-mcp/systemd/*.service; do
  [ -f "$f" ] && files+=("$f")
done
if [ "${#files[@]}" -eq 0 ]; then
  echo "unit-template-check: no unit templates found" >&2; exit 1
fi

# The per-seat roots a renderer substitutes. A value only has to be PLAUSIBLE for systemd's
# parser — the question here is whether the KEYS are readable, not whether the paths exist.
render() {  # <template> → stdout, the template with its placeholders filled
  sed -e "s|__YMIR_APP_DIR__|/tmp/ymir-check/app|g" \
      -e "s|__YMIR_BIN_DIR__|$ROOT/bin|g" \
      -e "s|__YMIR_ENV_FILE__|/tmp/ymir-check/.env.local|g" \
      -e "s|__YMIR_HLIDSKJALF_API_PORT__|3889|g" \
      -e "s|__YMIR_HLIDSKJALF_PORT__|3888|g" \
      -e "s|__YMIR_OPERATOR_CONFIG__|/tmp/ymir-check/config|g" \
      -e "s|__YMIR_OPERATOR_STATE__|/tmp/ymir-check/state|g" \
      -e "s|__YMIR_HOME__|/tmp/ymir-check/home|g" \
      -e "s|__YMIR_SKILLS_MCP_PORT__|8791|g" \
      -e "s|__YMIR_SMIDJA_PORT__|8437|g" \
      -e "s|__YMIR_VIZ_DB__|/tmp/ymir-check/viz.db|g" \
      -e "s|__YMIR_VIZ_DIR__|/tmp/ymir-check/viz|g" \
      "$1"
}

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT
bad=0
for f in "${files[@]}"; do
  rendered="$tmp/$(basename "$f")"
  render "$f" > "$rendered"
  out="$(systemd-analyze verify "$rendered" 2>&1 || true)"
  # Only systemd's own "I will ignore this" lines are failures. verify also warns about
  # binaries that do not exist in a scratch render, and those are not this check's business.
  ignored="$(printf '%s\n' "$out" \
    | grep -E "Unknown (key|lvalue|section)|ignoring\." \
    | grep -v '^$' || true)"
  if [ -n "$ignored" ]; then
    bad=$((bad + 1))
    printf 'unit-template-check: FAIL %s\n' "$f"
    printf '%s\n' "$ignored" | sed 's/^/    /'
  fi
done

if [ "$bad" -eq 0 ]; then
  [ "$QUIET" = 1 ] || printf 'unit_templates[1]{checked,verdict}:\n  "%s","ok — systemd reads every key"\n' "${#files[@]}"
  exit 0
fi
printf 'unit_templates[2]{checked,failed}:\n  "%s","%s"\n' "${#files[@]}" "$bad" >&2
printf 'note: a key systemd ignores is a guard that does not guard — move it to the section\n' >&2
printf '      systemd reads for that key (StartLimit* belongs in [Unit]).\n' >&2
exit 1
