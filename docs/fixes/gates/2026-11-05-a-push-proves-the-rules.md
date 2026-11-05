# A push proves the rules — the ward, the hook, and the CI that binds everyone

**2026-11-05 · component: gates · `bin/gates/guards/rules-compliance-guard.sh` · `RULES/46` · `.githooks/pre-push`**

His word: *"make a rule for ymir on pushes to validate thet ymir are following the rules … all usres that pusch need to
make sure ymir are following the rules. not just us"*.

## The gap

`bin/gates/guards.sh` held 25 wards, each knowing one rule. Nothing asked the cheap universal questions: does a new
document carry its history, does a new rule name itself and reach the index, does a new line carry an internal address or
a plain-HTTP URL, is a new door executable. Those were left to a human remembering `RULES/`.

## The change

- **`bin/gates/guards/rules-compliance-guard.sh`** — judges the push range only (`origin/<base>..HEAD`), asks four rules,
  refuses with file · line · rule · finding, and skips cleanly when the base is unknown (Rule 25).
- **Registered** in `guards.sh`'s `WARDS` list — the one list, so it runs in the local hook AND in CI.
- **`RULES/46`** — the law, including the sentence that matters: *a collaborator cannot be asked to run what they cannot
  install*, so CI is the binding half and the hook is the convenience.
- **`.githooks/pre-push`** — the same one list in the author's terminal; seated by `core.hooksPath` in the install's
  `gates` step.

## Proven

- `rules-compliance-guard.sh check origin/main HEAD` on a clean tree → `clean`.
- A deliberately added document without a CHANGE LOG → refused with that file named.
- An added line carrying a LAN address → refused with the rule (`RULES/39 · network N1/N7`).

## Owed

The install step must set `core.hooksPath .githooks` on every fresh clone (Rule 05: every platform layer), and the Windows
layer needs the same step in git-bash or WSL — otherwise a Windows seat has CI only, and that is the half we can rely on
anyway.
