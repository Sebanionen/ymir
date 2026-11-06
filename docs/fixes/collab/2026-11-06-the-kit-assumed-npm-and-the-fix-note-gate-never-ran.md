# 2026-11-06 — the kit assumed npm, and the fix-note gate never ran

**Component:** collab (Vingólf) · **Doors:** `bin/collab/kit/.githooks/{pre-commit,pre-push}`,
`bin/collab/kit/scripts/checks.sh` (new), `bin/collab/kit/scripts/gates/fixes-guard.sh` ·
**Plan:** none — found by the first install of the kit into a non-Node repository

## What was wrong

The collaboration kit went into a client's Elixir umbrella today, the first repository
that is neither a Node project nor our own. Three faults, each of the class the kit exists to refuse:

1. **`pre-commit` and `pre-push` ran npm.** `npm run check`, `npm run typecheck`, `npm run test`. In an Elixir
   repository those cannot succeed, so the hooks refused **every commit**. Proved by running the hook by hand:
   `pre-commit refused: a ward found a fault` with no ward having run.
2. **`fixes-guard` was unreachable.** `pre-push` ended with `exit 0` and the fix-note gate sat *below* it, so it
   had never run in any repository — the gate was documented, believed, and dead.
3. **`fixes-guard` looked in the wrong shelves.** Its code pattern was `^(backend|src|scripts|shared)/` — one
   project's shape. In that repository the code is under `apps/`, `lib/`, `config/`, so even a reachable guard
   would have refused nothing.

## What changed

- **`scripts/checks.sh`** — one door the hooks ask instead of naming a tool: the repository's own
  `scripts/doctor.sh` / `scripts/test.sh`, else `package.json` (npm), else `mix.exs` (Elixir), else a **printed
  skip**. A clean skip is a pass; a silent green is a lie (RULES/25).
- **`pre-commit`** runs `checks.sh doctor`; **`pre-push`** runs the ref gates, then the fix-note gate on the
  range git is about to send, then `checks.sh test` — every gate above the exit.
- **`fixes-guard`** covers the code shelves the kit actually meets: `.githooks|apps|backend|bin|config|lib|priv|
  rel|scripts|shared|src|test|tests`.
- **Kit version 1.0.0 → 1.1.0**, so `.collab-kit.json` says which standard a repository carries.

## Proved

- `bash scripts/checks.sh doctor` in that repository: `checks[doctor]: mix compile --warnings-as-errors`, and the
  compile it runs is the repository's own.
- The same door in a repository with none of the three shapes prints `skipped — … this is a skip, not a pass`
  and exits 0.
- `standardise.sh --check` reports 20 present / 0 missing / 0 different there after `--apply` of
  1.1.0.

## What was NOT done

- **Growth Agent and InvestReady were not re-standardised.** Their shelf is older by this fix; `--check` on
  either will report `differs` for the three hooks and the two guards, which is the signal, not a failure.
- **No GitHub enforcement.** Branch protection still needs the paid plan; the hooks are the gate.

## Appended the same hour — a fourth fault: the private-data gate could not parse

Turning the gates on for the first time (`bash scripts/gates/private-data.sh --all`) gave
`line 38: unexpected EOF while looking for matching '`. The cause was one apostrophe: the refusal message read
`the house's private home` **inside single quotes**, so the string closed at `house` and the rest of the script
was swallowed. `bash -n` proves it: the gate has **never run** in any repository that carries the kit — the third
dead gate found in one afternoon, after `fixes-guard` below `exit 0` and the hooks that only spoke npm.

Fixed by rewording the message (no apostrophe) and, while in there:

- **`%h/Documents/ymirhome` and `$HOME/Documents/ymirhome` are now allowed** — they are home-relative, which
  the rule permits, and the gate was refusing a systemd unit for saying `%h`. A literal `/home/<name>/...` is
  still refused, proved with two fixtures: the `%h` unit passes, the absolute one is named with its line.

Still open on the whole tree — **pre-existing, not this change**: `secret-scan.sh --all` names
`.agents/skills/nsr-compliance/assets/**/*.env.example` (`postgres://app:app@localhost` — obviously fake, but
the pattern cannot tell) and `bin/collab/who.py` (`postgresql://forgejo:%s@127.0.0.1` — a reference built from a
vault-read variable). Both need the fixtures-or-reference allowance the gate's own documentation promises; the
staged view of this change is clean, so neither blocks it.

## CHANGE LOG

- **2026-11-06** — written, then appended the same hour when the private-data gate was found to be a script
  that could not parse; both faults of that gate carry their fixtures above.
