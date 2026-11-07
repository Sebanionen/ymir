#!/usr/bin/env bash
# harness-extensions-install.sh — every harness gets the house's extensions and packages, on install AND on update.
#
#   bin/seat/harness-extensions-install.sh            sync every harness present on this host
#   bin/seat/harness-extensions-install.sh --check     report per harness: current · stale · absent · skip
#
# WHY (RULES/13, 2026-11-02; his word: *"all extentons and packets to all harnesses must come on uptaaes"*).
# Measured that day: the extensions lived only in the checkout, so an agent booted anywhere else had none;
# OpenCode's global AGENTS.md was three weeks stale; and nothing but Pi and OpenCode was refreshed by an update
# at all. A user's agent therefore drifts from the house the moment they pull.
#
# WHAT IT DOES, per harness, from the descriptors in `.agents/harnesses/`:
#   pi        the settings `extensions[]` entry, resolved by realpath (bin/seat/valknut-load.sh --global)
#   opencode  the plugin set copied into ~/.config/opencode/plugins
#   claude    the hook scripts into ~/.claude/hooks  (the JSON wiring is NAMED, never merged blind)
#   codex     hooks.json and the skills links under ~/.codex
#   cursor    the rules into ~/.cursor/rules
# A harness that is not installed is a clean SKIP with its reason, never a failure (RULES/25).
set -uo pipefail

_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(CDPATH='' cd "$_d" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)"

# A PINNED runtime wins over the working tree (RULES/02 §7): the extensions a harness loads must be the
# ones a deployment proved, not whatever branch an agent left checked out.
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
home=""; declare -f ymir_home_root >/dev/null 2>&1 && ymir_home_root home 2>/dev/null
[ -n "$home" ] || home="${YMIR_HOME:-}"
[ -n "$home" ] && [ -r "$home/config/runtime.env" ] && . "$home/config/runtime.env"
if [ -n "${YMIR_RUNTIME_DIR:-}" ] && [ -d "$YMIR_RUNTIME_DIR/.git" ]; then
  ROOT="$YMIR_RUNTIME_DIR"
fi

mode="install"
case "${1:-}" in
  -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --check|check) mode="check" ;;
  ""|install|--install) ;;
  *) printf 'error: unknown action %s\nhelp: harness-extensions-install.sh [--check]\n' "$1" >&2; exit 2 ;;
esac

say() { printf '%s\n' "$*"; }
changed=0; stale=0; absent=0

copy_tree() {  # <src-dir> <dst-dir> <label> — copy only what differs, keep one .bak of anything replaced
  local src=$1 dst=$2 label=$3 n=0
  [ -d "$src" ] || return 0
  mkdir -p "$dst" 2>/dev/null || { say "  \"$label\",\"skip\",\"$dst is not writable\""; return 0; }
  while IFS= read -r f; do
    case "$f" in */node_modules/*|*/__pycache__/*|*.pyc) continue ;; esac
    rel=${f#"$src"/}
    target="$dst/$rel"
    if [ -f "$target" ] && cmp -s "$f" "$target"; then continue; fi
    if [ "$mode" = "check" ]; then
      say "  \"$label\",\"stale\",\"$rel differs from the tree\""; stale=$((stale+1)); return 1
    fi
    mkdir -p "$(dirname "$target")"
    [ -f "$target" ] && cp -p "$target" "$target.bak-$(date -u +%Y%m%d-%H%M%S)" 2>/dev/null
    cp -p "$f" "$target" && n=$((n+1))
  done < <(find "$src" -type f 2>/dev/null)
  [ "$n" -gt 0 ] && { say "  \"$label\",\"synced\",\"$n file(s) into $dst\""; changed=$((changed+1)); }
  return 0
}

printf 'harness_extensions[%s]{harness,state,detail}:\n' 6

# ── pi: the settings entry that makes the extensions load from any directory ──
if command -v pi >/dev/null 2>&1; then
  if [ "$mode" = "check" ]; then
    if grep -q "$ROOT/.pi/extensions" "$HOME/.pi/agent/settings.json" 2>/dev/null; then
      say "  \"pi\",\"current\",\"settings extensions[] → $ROOT/.pi/extensions\""
    else
      say "  \"pi\",\"stale\",\"settingsextensions[] does not name this checkout\""; stale=$((stale+1))
    fi
  else
    bash "$ROOT/bin/seat/valknut-load.sh" --global >/dev/null 2>&1 \
      && say "  \"pi\",\"synced\",\"settings extensions[] → $ROOT/.pi/extensions\"" \
      || say "  \"pi\",\"skip\",\"valknut-load could not bind the seat\""
  fi
else
  say "  \"pi\",\"absent\",\"no pi on this host\""; absent=$((absent+1))
fi

# ── opencode: the plugin set (guards + the recovered ymir-tools) ──────────────
# ONE home. The source is .agents/harness/opencode/plugins; the deployed copy is
# ~/.config/opencode/plugins. OpenCode also auto-loads <project>/.opencode/plugins,
# so a symlink there registered every guard TWICE (6 plugins, 12 load failures,
# 2026-11-04). Never link the source into a project — deploy it here.
#
# V2 plugins import `@opencode/plugin` (and ymir-tools imports `effect`), so the
# deployed home must be able to resolve them. A missing node_modules is a plugin
# that cannot load at all; install it once, here, rather than failing per file.
if command -v opencode >/dev/null 2>&1; then
  if [ -d "$ROOT/.agents/harness/opencode/plugins" ]; then
    copy_tree "$ROOT/.agents/harness/opencode/plugins" "$HOME/.config/opencode/plugins" "opencode" || true
    if [ "$mode" != "check" ] && command -v npm >/dev/null 2>&1; then
      if [ ! -d "$HOME/.config/opencode/node_modules/@opencode/plugin" ]; then
        ( cd "$HOME/.config/opencode" \
          && { [ -f package.json ] || printf '%s\n' '{"name":"ymir-opencode-plugins","private":true,"type":"module"}' >package.json; } \
          && npm install --no-audit --no-fund --silent @opencode/plugin effect >/dev/null 2>&1 ) \
          && say "  \"opencode-deps\",\"installed\",\"@opencode/plugin + effect in ~/.config/opencode\"" \
          || say "  \"opencode-deps\",\"absent\",\"npm could not install @opencode/plugin (plugins import it and will not load)\""
      fi
    fi
  else
    say "  \"opencode\",\"absent\",\"no .agents/harness/opencode/plugins in this tree\""
  fi
  [ "$mode" = "install" ] && say "  \"opencode\",\"note\",\"the twenty tools come from ymir-tools.ts; loaded by opencode's own config\"" || true
else
  say "  \"opencode\",\"absent\",\"no opencode on this host\""; absent=$((absent+1))
fi

# ── claude: the hook SCRIPTS; the JSON wiring is named, never merged blind ────
if command -v claude >/dev/null 2>&1; then
  copy_tree "$ROOT/.claude/hooks" "$HOME/.claude/hooks" "claude-hooks" || true
  if [ -f "$ROOT/.claude/settings.json" ]; then
    if [ "$(command -v python3)" ] && python3 - "$ROOT/.claude/settings.json" "$HOME/.claude/settings.json" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
want = json.load(open(src)).get("hooks")
have = {}
try: have = json.load(open(dst)).get("hooks") or {}
except Exception: pass
sys.exit(0 if want == have else 3)
PY
    then
      say "  \"claude\",\"current\",\"hooks wired in ~/.claude/settings.json\""
    else
      say "  \"claude\",\"stale\",\"hooks.json wiring differs — merge by hand, never blindly (the file is yours)\""
      [ "$mode" = "check" ] && stale=$((stale+1))
    fi
  fi
else
  say "  \"claude\",\"absent\",\"no claude on this host\""; absent=$((absent+1))
fi

# ── codex: hooks.json and the skills links ───────────────────────────────────
if command -v codex >/dev/null 2>&1; then
  if [ -f "$ROOT/.codex/hooks.json" ]; then
    if cmp -s "$ROOT/.codex/hooks.json" "$HOME/.codex/hooks.json" 2>/dev/null; then
      say "  \"codex\",\"current\",\"hooks.json matches the tree\""
    elif [ "$mode" = "check" ]; then
      say "  \"codex\",\"stale\",\"hooks.json differs\""; stale=$((stale+1))
    else
      mkdir -p "$HOME/.codex"
      [ -f "$HOME/.codex/hooks.json" ] && cp -p "$HOME/.codex/hooks.json" "$HOME/.codex/hooks.json.bak-$(date -u +%Y%m%d-%H%M%S)"
      cp -p "$ROOT/.codex/hooks.json" "$HOME/.codex/hooks.json" && say "  \"codex\",\"synced\",\"hooks.json\""
    fi
  else
    say "  \"codex\",\"current\",\"no hooks.json in the tree for codex\""
  fi
else
  say "  \"codex\",\"absent\",\"no codex on this host\""; absent=$((absent+1))
fi

# ── zed: skills natively, AGENTS.md natively, context servers by a NAMED merge ─
if command -v zed >/dev/null 2>&1 || [ -d "$HOME/.config/zed" ]; then
  # .agents/skills is Zed's own shelf too, so nothing is copied for skills — it reads the same tree.
  if [ -d "$ROOT/.agents/skills" ]; then
    say "  \"zed\",\"current\",\".agents/skills is Zed's native shelf — nothing to copy\""
  fi
  if [ -f "$HOME/.config/zed/settings.json" ] && python3 - "$HOME/.config/zed/settings.json" <<'PY2' >/dev/null 2>&1
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if isinstance(d.get("context_servers"), dict) and d["context_servers"] else 3)
PY2
  then
    say "  \"zed\",\"current\",\"context_servers wired in ~/.config/zed/settings.json\""
  else
    say "  \"zed\",\"note\",\"context_servers is empty or absent — a NAMED merge, never blind: the key is context_servers, not mcpServers\""
  fi
else
  say "  \"zed\",\"absent\",\"no zed on this host\""; absent=$((absent+1))
fi

# ── cursor: the rules ────────────────────────────────────────────────────────
if command -v cursor-agent >/dev/null 2>&1 || command -v cursor >/dev/null 2>&1; then
  copy_tree "$ROOT/.cursor/rules" "$HOME/.cursor/rules" "cursor-rules" || true
else
  say "  \"cursor\",\"absent\",\"no cursor on this host\""; absent=$((absent+1))
fi

if [ "$mode" = "check" ] && [ "$stale" -gt 0 ]; then
  say "help: bin/seat/harness-extensions-install.sh (syncs every harness present; never merges a JSON you own)"
  exit 1
fi
if [ "$mode" = "check" ]; then
  printf 'harness_extensions[1]{state}:\n  "current","every harness present on this host carries the tree'"'"'s set"\n'
fi
exit 0
