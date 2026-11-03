# The gates — what stops what, and why each exists

Two layers: **wards** (`npm run check`, twenty of them, in `scripts/wards/`) prove the repository is coherent; **gates**
(`scripts/gates/`, run by the git hooks) stop a specific class of mistake from entering history at all.

## The git hooks, and what each refuses

```
hooks[3]{hook,refuses,why}:
  "**pre-commit**","a red ward, a type error, **a credential**, **a machine path or a real address**","a secret in a commit is a secret in every clone, and a history rewrite is the only cure"
  "**commit-msg**","a subject that says nothing","a commit that cannot be read six months later is a commit nobody trusts"
  "**pre-push**","a push to `master` or `main`, and a push of a red tree","merges are the Allfather's, and the branch guard is the reminder"
```

## The gates themselves

```
gates[2]{script,catches,tuned_to_avoid}:
  "`scripts/gates/secret-scan.sh`","private keys, `GOCSPX-`, `sk-`, `ghp_`, `xoxb-`, Google API keys, `postgres://` URLs **with a literal password**, and `"api_key": "<24+ chars>"`","`postgres://user:${VAR}@host` — a reference is not a secret, and a gate that cries wolf teaches people to pass `--no-verify`"
  "`scripts/gates/private-data.sh`","absolute paths into a person's home, `Documents/ymirhome`, and real addresses at gmail/hotmail/live/outlook/yahoo/icloud","documentation, tests and fixtures, where a fake address is deliberate; `$HOME/...` is home-relative, not a machine path"
```

**Run them by hand whenever in doubt:**

```bash
bash scripts/gates/secret-scan.sh --all
bash scripts/gates/private-data.sh --all
```

## What these gates found on their first run

Both fired within a minute of being written, and both were right:

- **`scripts/tenancy-check.sh` contained a real customer's email address.** The script now takes both tenant addresses from the
  environment (with obviously fake defaults), because a real company's address belongs in the database, not in a script.
- **The testing documentation carried what looked like live credentials** in copy-pasteable `psql` commands. They are now
  `${TEST_DB_PASSWORD}` references.

## The gates Ymir has that this project does not, and whether it should

```
borrowed[4]{gate,what_it_does,verdict}:
  "**fixes-guard** — a behaviour change must leave a note in `docs/fixes/`","it keeps the reason beside the change","**adopt** — the shelf exists; the guard is the missing half"
  "**subsystem-docs-guard** — a code change must touch its owning document","it stops documentation drifting from code","**adopt, lightly** — the `docs/architecture/` shelf exists; a mapping from path to document is the work"
  "**branch-guard** — refuse a push to a protected branch","this project has it in pre-push already","**have it**"
  "**vault and confidential guards**","they stop vault content leaving the vault","**not applicable yet** — no vault content is ever read here; adopt the day it is"
```

**The rule for adding a gate:** it must catch something that has actually happened or that would be unrecoverable if it did. A gate
nobody has ever triggered is a tax on every commit.
