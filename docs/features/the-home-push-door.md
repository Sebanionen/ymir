# The home push door — named paths only, never `-A`

## What it is

`bin/vault/push.sh` is the one sanctioned way to commit and push **the private
home** (`$YMIR_HOME`). It stages *only the paths you name*, refuses to delete a
tracked file, and can tell you what it would stage before it stages anything.

The home is a private git repository, and its history is the record of your work.
This door exists because of a specific, expensive incident: a scratch file written
seconds before a commit was swept in by `git add -A` and pushed, and the only way
back was a history rewrite. **A staging discipline that depends on you remembering
is not a discipline.** The door makes it structural — it cannot sweep a file in,
because it never looks at the tree; it looks at the list you gave it.

## What you need

- A home that is a git repository with an `origin` remote and a `main` branch.
- Working git credentials for that remote (the home is a private GitHub repo; an
  `https` origin needs your token, an `ssh` origin needs your key).
- The home resolvable: `bin/vault/hodd.sh path` must print a directory.

## Do it

### Look before you push

```bash
bin/vault/push.sh --dry-run "memory: today's log" hodd/memory/daily/2026-11-04.md
```

```
dry run — nothing staged, nothing committed, nothing pushed.
  home: /home/you/Documents/ymirhome
  message: memory: today's log
  paths:
    hodd/memory/daily/2026-11-04.md
  what git would stage:
     M hodd/memory/daily/2026-11-04.md
```

Nothing is touched. The last block is `git status --porcelain` limited to your named
paths, so you see exactly which files the commit will contain — and, just as
importantly, you see when a path you named is not changed at all.

### Push

```bash
bin/vault/push.sh "memory: today's log" hodd/memory/daily/2026-11-04.md
bin/vault/push.sh "plans: <NN> opened" svartalfaheim/<realm>/projects/<project>/plans/<NN>-my-slug.md \
                                       svartalfaheim/<realm>/projects/<project>/plans/README.md
```

It makes **one commit** holding exactly those paths, then pushes `origin main`:

```
pushed 1 path(s): hodd/memory/daily/2026-11-04.md
```

The message is your commit message, quoted as a single argument. Name the **index**
when you open a plan — a plan file pushed without its `README.md` row is a plan no
one finds, and the weaver will say so later rather than sooner.

### When there is nothing to push

```
nothing to push: the named paths are unchanged
```

Exit 0. A no-op is not a failure, and a door that calls one a failure teaches you to
ignore its failures.

### What it refuses

A tracked file, deleted from your named paths:

```
push: refused — a tracked file is deleted among the named paths:
hodd/docs/old-runbook.md
Rule 11: retire it by MOVING it (hodd/reference/), never by deleting it.
```

That is Rule 11 in code: a document is retired by **moving** it to
`hodd/reference/` with a note saying why and what replaced it, never by deleting it.
A deletion in the home is a hole in the record, and history rewrites are how a vault
loses a month.

## Notes & limits

- **Never `git add -A` in the home.** That is the whole reason this door exists.
  Staging discipline is the law (Rule 04), and the incident that wrote it is recorded
  in `hodd/docs/secrets-vault.md`.
- **It refuses a deletion; it does not refuse a secret.** The home's own pre-commit
  ward (`bin/gates/guards/secret-guard.sh`, where installed) is the backstop for a
  credential. This door does not decrypt or inspect your files — it stages and
  commits, and the vault's design (tokens by reference, values only in
  `hodd/secrets/`) is what keeps a secret out of the tree in the first place.
- **One commit per push.** If you have eight unrelated changes, push them in eight
  named pushes or write one message that truly describes all of them. The door will
  not split them for you and will not invent a message.
- **It pushes `origin main`, always.** The home's trunk is `main`; a home whose
  branch has been renamed will fail at the push, loudly, with git's own message.
- **`--dry-run` is the safe half.** Use it when you are unsure, and use it in
  scripts: it makes no change and cannot fail on credentials.
- It operates on **the home**, never this repository. Publishing code goes through a
  branch and a pull request, not through this door.

## If it does not work

**`push: no home`** — `bin/vault/hodd.sh path` answered nothing from this shell. Run
it alone; if it prints nothing, the home is not resolvable in your environment (check
`YMIR_HOME`, or the recorded choice under `~/.config/ymir/home`).

**`usage: push.sh [--dry-run] "<message>" <path> [path…]`** — the message and at
least one path are both required. Quoting the message as one argument is the usual
miss; a message with spaces that is not quoted becomes several paths.

**`push: refused — a tracked file is deleted among the named paths`** — you named a
file you have deleted. Restore it (`git restore <path>`) and retire it properly, or
un-name it and leave the file in place. The door will not let a deletion through.

**`push: commit failed (see git)`** — the staging worked and the commit did not.
Usually git has no identity set in the home (`user.name` / `user.email`) and says so
on stderr. Set it once in the home and push again.

**`push: committed, but the push failed (see git)`** — your work is committed
locally and did not reach the remote. Almost always credentials or branch protection.
Fix the remote access, then push again; **do not** re-run the door expecting it to
redo the commit — it will print `nothing to push`, because the commit already exists.

## Proven on this machine, 2026-11-04

Proved end-to-end against a throwaway home and a bare origin repository (never
against your real home), with `YMIR_HOARD` pointed at the temporary home:

```
push.sh "test: append" hodd/data/keep.md        → pushed 1 path(s)     (commit + push to origin main)
push.sh "test: nothing" hodd/data/keep.md       → nothing to push …    (exit 0)
push.sh --dry-run "test: dry" hodd/data/keep.md → dry-run block, ` M hodd/data/keep.md`, nothing staged
rm hodd/data/keep.md && push.sh "test: delete" …→ refused — a tracked file is deleted; Rule 11
push.sh msgonly                                 → usage, exit 2
```

The temporary origin's log afterwards: `d92a1d5 test: append` on top of `e277c32
init` — two commits, only the named file, nothing swept in.
