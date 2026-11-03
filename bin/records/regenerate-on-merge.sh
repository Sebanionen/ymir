#!/usr/bin/env bash
# regenerate-on-merge.sh — the merge driver for WOVEN documents (Þættir, plan 174).
#
# git calls it as:  <driver> %O %A %B %L %P   (base · ours=output · theirs · marker · path)
# A woven document has no hand-kept content: the answer to any conflict is to
# WEAVE it again from the fragments the merge just combined.
set -uo pipefail
path="${5:-${3:-}}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
case "$path" in
  FEATURES.md|*/FEATURES.md)
    bash "$root/bin/records/weave-features.sh" >/dev/null || exit 1 ;;
  bin/README.md|*/bin/README.md|.agents/backend/README.md|*/.agents/backend/README.md)
    bash "$root/bin/gates/inventory.sh" >/dev/null || exit 1 ;;
  .agents/assets/agents/capabilities.md|*/.agents/assets/agents/capabilities.md)
    bash "$root/bin/gates/capabilities.sh" >/dev/null || exit 1 ;;
  *)
    exit 1 ;;   # not a woven document — let git keep the conflict
esac
exit 0
