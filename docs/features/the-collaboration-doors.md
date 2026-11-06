# The collaboration doors — who is with us, and how far

One command answers who works with the house, on which surface, and whether they actually use it. One command puts
the collaboration files into any repository. One renders a letter to a partner. One ships work to `main` without
sweeping up files nobody named.

## What it is

Collaboration happens on several surfaces — a repository, a board, a document suite, a meeting record, an agent's
read face, an email. The doors here keep the *people* straight: a register in the private home says who is
declared, and the doors measure the machines against it. Nothing about a person lives in code.

The same shelf of files — a contract, a living baton, its append-only history, and a check — travels into every
repository, so a stranger can continue where the last hand stopped.

## What you need

- The private home at `$YMIR_HOME` with `hodd/data/collaboration.yaml` (the register).
- For `who`: ssh to the host that runs the collaboration suite (default `zerwizserver`), and that host's containers
  answering — the gate, the board's database, the documents' database, the forge.
- For `letter`: the mail gate (`systems/snotra/services/letters/mail-send.sh`) and the vault grant it uses.
- For `ship`: a git checkout with a remote.

## Do it

```sh
bin/collab/collab.sh who            # every declared person, every surface, measured
bin/collab/collab.sh ladder         # the rungs, what each person owes, which projects carry the shelf
bin/collab/collab.sh init <repo>    # install the shelf into a repository (or --check the one it has)
bin/collab/collab.sh letter --to partner@example.com --person "A Partner" --dry-run
bin/collab/collab.sh ship --repo ~/Code/myproject --branch feat/thing \
  --message "feat: the thing" --path src/thing.ts
```

What you should see: `who` prints one row per person with a verdict — `entered`, `unentered`, or `drift` when a
declared account is missing from its surface — then the gaps it can prove (no second factor, no public key, an
account with no email) and a summary that says whether **any sign-in came from outside the house**. `init` prints
the five files it wrote and the exact line that wires the check into that project's gate.

## Notes & limits

- **A house sign-in is not a counterpart using the system.** A login from loopback, or from the house's own public
  address, is labelled `loopback` / `house`. Only a `remote` address counts as someone outside.
- **A surface it cannot read is `unread`, never zero.** If ssh fails, the row says so.
- **`init` never overwrites.** A repository that already has a baton is checked, not rewritten; a stray file is
  refused and left as it was. It prefers the project's own checker (an Elixir `mix` task, a node script) over the
  shelf's portable one.
- **`letter` has no send path.** It renders and leaves a draft; sending needs the operator's word and the approval
  gate. Editing one character after approval makes the approval stale.
- **`ship` stages only the paths you name** and reports what it leaves alone. It does not `git add -A`, ever.
- The baton check's freshness limit is 14 days by default; `--max-age-days` raises it for one run.

## If it does not work

- **`who` says `unread`.** ssh to the host failed, or a container is down. Run the suite's own health door
  (`bin/gimle/…` or the `gimle` skill's `gimle-check.sh`) and read the reason it prints.
- **`who` reports a person `drift`.** A declared account is not on its surface — the register and the machine
  disagree. Fix the register or the account; the door will not guess which is right.
- **`init --check` fails on a repository that has a baton.** The baton is incomplete, stale, or names a path that no
  longer exists; the message names which. Write a new baton with `handoff/check.sh --new --from <name>`.
- **`ship` refuses.** Either nothing is changed at the named path, or the branch does not exist yet in a repository
  with no commits. It prints which.

## The handoff is written for a business reader (2026-11-06)

The baton shelf looks like an internal document, and it is not one: these repositories are shared with the
clients and partners whose products they are. So the baton — the file `handoff/CURRENT.md` — is written for
**a reader outside the house**.

**What that means in practice.** The file carries a `**For:**` line naming the person who reads it and their
role. Section 1 is two or three sentences a non-engineer can follow. Section 2 gives the result and the screen
or command that proves it, with money in its own currency. Section 4 names each blocker with the person who owns
it, by the name on the contract — never an internal nickname.

**House words are refused.** `Allfather`, `Brokk`, `Eindri`, `Galdr`, `Sága`, `Hlidskjalf`, `Mímir`, `Muninn`,
`Huginn`, `Yggdrasil`, `Utgard`, `Bifrost`, `runes` and `the well` mean something inside the hall and nothing to
a client, so `handoff/check.sh --check` reports each one with its line number. If a line genuinely must carry
one, waive it **on that line**: `allow-house-word: <why>`. `Ymir` itself is allowed — naming the tool is honest,
naming the hall is not.

**The share of it that is not words.** Old copies of the shelf keep passsing their old check; a repository that
refreshes its shelf gets the stricter one. Run `handoff/check.sh --check` before you stop, as always.

## What the git hooks run (2026-11-06)

The kit now asks the repository instead of naming a tool: `checks.sh doctor` and `checks.sh test` run the
repository's own doctor and test scripts if it names them, or npm for a `package.json`, or `mix` for a `mix.exs`,
and print a plain **skip** when there is nothing to run. Previously the hooks ran npm in every repository, which refused every
commit in an Elixir project.
