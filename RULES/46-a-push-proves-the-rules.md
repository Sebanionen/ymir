# 46 — A push proves the rules, for everyone who pushes

**Appended 2026-11-05** at the Allfather's word:

> *"make a rule for ymir on pushes to validate thet ymir are following the rules. we need to make a hook or a guard for this"*
> *"all usres that pusch need to make sure ymir are following the rules. not just us"*

## The law

```
push_law[5]{rule,what_it_means}:
  "THE CHECK IS ON THE PUSH, NOT ON THE PERSON","a rule that depends on who is pushing is not a rule. Every branch that reaches this repository is judged by the same wards, in the same order"
  "CI IS THE BINDING HALF","`.github/workflows/ymir-gates.yml` runs `bin/gates/ci-verify.sh` → `bin/gates/guards.sh` for every pull request, including one from a fork whose author never installed a hook. A collaborator cannot be asked to run what they cannot install"
  "THE HOOK IS THE CONVENIENCE","`.githooks/pre-push` runs the same one list in the author's own terminal, so a refusal costs seconds instead of a round trip. Seated by `git config core.hooksPath .githooks` (install step `gates`)"
  "ONE LIST, ONE ORDER","`bin/gates/guards.sh`'s `WARDS` array is the only list. A ward absent from it runs nowhere; a ward in it runs everywhere"
  "A REFUSAL NAMES FILE AND LINE","a gate that prints a summary is a gate nobody can act on. Every ward refuses with the file, the line and the rule it enforces"
```

## What the new ward asks — `bin/gates/guards/rules-compliance-guard.sh`

It judges **only what the push adds**, so a legacy tree is never re-litigated:

```
asks[4]{rule,question,refusal}:
  "RULES/06 · home RULES/changelog","does a NEW document carry its history?","`<file>: a new document has no CHANGE LOG section`"
  "RULES/README","does a new rule name itself and appear in the index?","`<file>:1 the first line must be '# NN — <title>'` · `a new rule is not named in RULES/README.md`"
  "home RULES/network.md N1/N7 · RULES/39","does a new line carry an internal address or a plain-HTTP cross-host URL?","`<file>: address or plain-HTTP URL in a new line`"
  "RULES/12 · RULES/23","is a new door executable and does it have a shebang?","`a new door is not executable (chmod +x)`"
```

## What it deliberately does not do

- It does not judge the whole tree — only the range `origin/<base>..HEAD`.
- It does not fix anything; a silent fix hides the habit that caused it.
- It does not replace the specific wards (numbering, weave, language, the ward's list); it asks the cheap universal
  questions those wards leave to a human to remember.

## CHANGE LOG

- **2026-11-05** — appended (Hœnir, heimdall) with the ward, the hook and the CI path in the same change.
