# handoff — the baton

One hand stops; another continues. Without a written baton the second one re-derives the state of this
repository from the code and the tickets, and the first one's reasoning is lost — which is the expensive
part, because the reasoning is what the plans carry and the code does not.

**Two files and a shelf:**

```
handoff/
├── CURRENT.md      the live baton — always the last five minutes of the previous hand
├── TEMPLATE.md     the shape every baton must have
├── log/            one file per handoff, dated — append-only, never rewritten
└── check.py        the check (handoff/check.sh runs it)
```

`CURRENT.md` is the only living document in the repository: it is rewritten at every handoff, because a
baton that accumulates is not a baton. Everything it says is also written once into `log/`, which is
append-only — a correction is a new baton that cites the old one.

## The law

| Rule | Why |
|---|---|
| write a baton before you stop | a session that ends without one leaves the next hand to archaeology |
| write it for a stranger | someone who has read the repository's contract and nothing else must be able to continue |
| say where the work is, not what it was like | branch, commit, PR number, deployment, and the command that proves each |
| name what is blocked, and on whom | a blocker nobody wrote down becomes two people waiting |
| check it, do not trust it | a stale baton must fail a gate instead of quietly lying |

**When to write one:** ending a session · handing to a sub-agent · going blocked · handing between
machines · before a merge is sealed. **Not** after every commit — a baton is for a hand, not a habit.

## Use it

```sh
handoff/check.sh --new --from <your-name>     # writes handoff/log/<date>-<from>.md and refreshes CURRENT.md
handoff/check.sh --check                      # complete, dated, fresh, and its paths exist
handoff/check.sh --check --max-age-days 30    # a longer leash for a long quiet stretch
```

The check fails on: a missing baton · a missing section · no date, an unparseable date, or an age over
the limit (default 14 days) · no branch or deployment line · a backticked path under a known shelf that
does not exist · an empty `log/`.

**Wire it into the gate.** The check is worth nothing if nobody runs it:

- Elixir: add `handoff/check.sh` to the `precommit` alias in `mix.exs`.
- Node: add `"handoff": "handoff/check.sh --check"` to `package.json` scripts, and call it from CI.
- Anything else: add `handoff/check.sh --check` to the CI job that must pass before a merge.

## Written for a business reader — appended 2026-11-06

Appended at the operator's word: *"we need to have handoffs in business language — not the house repos are
for more people than ymir users."* Everything above still stands; this section says who the baton is
written **for**, because that was never written down and it decided the wrong things.

**The fact that changes the writing: these repositories are shared.** A baton is read by the client who
owns the product, the partner whose name is on the contract, the accountant who wants the invoice, the
developer on their first day, the auditor three years from now. Most of them have no Ymir, no seat, no
agent, and no glossary — and none of them should have to learn ours to read where the work stands.

```
law[6]{rule,why}:
  "plain English, and the reader named","a baton with no `**For:**` line has no reader, and a document written for nobody is written for its author"
  "full names, as the contract carries them","an internal nickname is a door a client cannot open: write the person, not the persona"
  "no house vocabulary","Allfather, Brokk, Eindri, Galdr, Sága, runes, wards and the well all mean something inside the hall and nothing to a client"
  "say what a person can see","a screen, a report, a number, a command and its output — never 'the subsystem refused'"
  "money and dates in full","a currency code and a year, not an amount a reader has to place in time"
  "jargon that cannot be avoided gets one line in section 1","one sentence of explanation costs the next hand ten minutes and saves the reader an hour"
```

**Say this, not that:**

| Inside the hall | In a handoff a client reads |
|---|---|
| "the Allfather sealed the merge" | "Josef Lindbom approved the change on 6 November 2026" |
| "Brokk dispatched an Eindri" | "the assistant gave the work to a separate worker, who opened pull request #3" |
| "the well was rebuilt" | "the assistant's long-term memory was rebuilt from its own log; nothing was lost" |
| "the ward refused the push" | "the release check stopped the deploy: one hard-coded password was found and removed" |
| "left it on the shelf for the next hand" | "the work is on branch `x`, unfinished; the next step is written in section 3" |

**The word itself.** Inside the house this shelf is called *the baton*, and this file still says so. In the
document a reader opens, prefer **handoff**: it is the word a person outside the hall already uses.

**Enforced, not hoped for.** The check now refuses a baton with no `**For:**` line, and refuses the house
personae (`Allfather`, `Brokk`, `Eindri`, `Galdr`, `Sága`, `Hlidskjalf`, `Mímir`, `Muninn`, `Huginn`,
`Yggdrasil`, `Utgard`, `Bifrost`, `runes`, `the well`) unless the line that carries one waives it in
writing with `allow-house-word:` — the same shape as every other waiver in this house: on the line it
waives, never by widening the rule.
