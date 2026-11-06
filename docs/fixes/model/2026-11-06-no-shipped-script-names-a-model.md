# No shipped script names a model — `bin/model/agent-model.sh`

**Date:** 2026-11-06 · **Plan:** 206 §11 · **Law:** `RULES/25-agnostic-by-construction.md`, `RULES/07-config.md`

## What was wrong

The Allfather: *"this model choosing logic don't make sense. all users and computers have different models and
capabilities.. are we shipping hardcoded models?"* — yes. Five shipped scripts named a model id:
`bin/agents/eindri-review-spawn.sh` (default), `bin/agents/eindri-checkpoint.sh` (a resume hint),
`bin/ward/vidarr-agent.sh`, `bin/ward/garmr-bite.sh`, `bin/ward/garmr/common.py` and `bin/ward/garmr/escalate.py`.
`llamacpp-3050-big/…` exists on nidavellir and nowhere else; `opencode-go/deepseek-v4.1-flash` is a vendor
choice baked into a public repo. The house already had the truth — `bin/model/catalog.sh` — and the code
went around it.

## What was built

`bin/model/agent-model.sh` — **the one resolver**, with the authority order stated in one place: explicit
`--model` → `YMIR_<AGENT>_MODEL` → `config/agents.<host>.yaml` (this machine) → `config/agents.yaml` (the
fleet) → the agent's `tier:` (`fast` · `balanced` · `strong` · `local`) resolved against this seat's
catalogue → the fleet `default_model` → **refusal**.

**The law over all of them:** a model this seat's catalogue does not list is refused **by name**, and an
unservable row is reported as a FINDING and fallen through — never silently honoured, never silently skipped.
`--check` judges every row on this seat; `--plain` is what a spawner calls; `--explain` shows the chain.

Every call site above now resolves instead of naming: the spine, the checkpoint hint, Viðarr, Garmr's
advisor and the Garmr escalate rungs (an empty row now means *resolve here*).

## The fleet's declaration (the operator's own file, not the repo)

`$YMIR_HOME/config/agents.yaml`: every agent row and `default_model` set to `opencode-go/deepseek-v4.1-flash`
at the Allfather's word. A machine that cannot serve it corrects its own overlay
(`config/agents.<host>.yaml`) — deliberately, on the record.

## Verified

`agent-model.sh --check` on nidavellir: **10 ok / 0 fail**, every row resolving to
`opencode-go/deepseek-v4.1-flash` from `fleet agents.yaml`. `model-rows-guard` (the 28th ward): `ok`, 10 rows.
`agent-model.sh forseti --plain` → `opencode-go/deepseek-v4.1-flash`.

## CHANGE LOG

- **2026-11-06** — written with the doors it describes (plan 206): the review loop joined to the
  spine, the read-only agent's mouth, the resolver that replaced five hardcoded model ids, and the
  operator-only mail door.
