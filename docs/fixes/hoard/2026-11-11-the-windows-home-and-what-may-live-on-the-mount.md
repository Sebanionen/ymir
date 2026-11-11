## hoard · 0.2.0 · 2026-11-11 — the Windows home, and what may live on the mount

### Why

At the operator's word: *"I am on Windows and we are running Ymir in WSL. The WSL box is just
for Ymir's runtime, but everything should be in our Windows."*

He was right, and the machine agreed. Measured on this seat before the move: the home sat at
`/home/ymir/Documents/ymirhome` on the WSL ext4 disk, and the repository at
`/home/ymir/coding/ymir` likewise. Both are invisible to Windows Explorer, cannot be reached
by his Windows backup, and vanish with `wsl --unregister`. `C:\` was mounted at `/mnt/c` as a
9p `v9fs` share, 80% full.

The home is the part that matters most: it is a private git repository holding the well, the
Runes ledger, the daily log, the plan ledger, the machine cards and the sealed vault. Losing it
to a WSL reset is not a nuisance, it is the loss of the house's memory.

> [!IMPORTANT]
> The move is not "put everything on `C:`". A 9p mount is a different filesystem with different
> guarantees, and some of those differences are load-bearing. The decision below is the point of
> this note; the migration is only its hand.

### The decision — what may live on the 9p mount, and what may not

| Thing | Crosses? | Why |
|---|---|---|
| The home (`ymirhome`) — plans, memory, ledgers, cards, settings | **Yes** | It is the operator's own ground. Documents, not an executed tree: nothing here is launched by a unit. |
| Documents, notes, research, marketing and business material | **Yes** | Same reason. Read and written by people and by scripts, never `exec`d. |
| Project checkouts (git working trees) | **Yes, with two settings** | `core.filemode=false` and `core.autocrlf=false` are both required, and both are proven below. |
| The well's store (`hodd/memory/kaia.engram`, SQLite in WAL mode) | **Yes, proven** | Measured on this mount: 500 inserts across four concurrent writers with no error, `integrity_check` ok, and the episode count held at 2 across the copy. |
| The sealed vault (`hodd/secrets/`) | **Yes, with the ward moved** | See "the ward moves from chmod to ACL" below. This is the least comfortable row in the table, and it is stated plainly rather than buried. |
| Python virtualenvs (`<home>/.venvs/`) | **No** | A venv's shebangs and symlinks name the machine that built it, and its interpreter is `exec`d. It is rebuilt by `bin/voice/voice-ensure.sh`, never carried. |
| The pinned runtime (`~/ymir-runtime`) | **No — refused** | This is the one thing the errand must refuse, and the migration refuses it in words on every run. See below. |
| systemd units, sockets, pid files, lock files | **No** | They live in the distro because the distro runs them. A unit's `ExecStart` is executed, and the 9p mount cannot guarantee what execution needs. |

### Why the runtime may not cross — four measurements, not a preference

This is the refusal the errand names, so it gets its reasons measured rather than asserted.

**1. There are no real mode bits.** On `/mnt/c`, `chmod 600 file` lands as `777`. Every file is
readable and executable by every account. A ward that says "this key is mine alone" cannot be
expressed in `chmod` here. A tree that systemd executes from needs that expression.

**2. The filesystem folds case.** Measured: creating `Case.txt` makes `case.txt` resolve to the
same file. A runtime tree cannot tell `import Foo` from `import foo`, and Node, Python, and every
package manager that ever shipped two `.js` files differing only in case will break in ways that
look like a bug in the code.

**3. A unit's `ExecStart` is an execution, not a read.** The mount is a network-style filesystem
(`v9fs`, `msize=65536`). Startup is slower, and every extra millisecond sits between the boot and
the service answering. A supervisor that restarts a slow service in a loop is a supervisor that
never settles.

**4. The Windows file lock model is not the POSIX one.** A running binary can be replaced under
Linux and cannot under Windows. A self-update that writes a new body and re-execs it — which is
exactly what an updater does — is the classic case that fails on a Windows-backed tree.

`~/ymir-runtime` therefore stays on ext4. **The home may cross; the runtime may not.** The
migration prints that sentence on every run, including the successful one, so the boundary is
never a memory.

### The ward moves from `chmod` to ACL — said plainly

Before the move, `hodd/secrets/` was mode `700` with `600` files, holding `age.key` (the key that
decrypts the vault) and a plaintext gate password. After the move, every one of those files
reports `777` from Linux.

That is not the loss it looks like, but it is not nothing either. Measured with `icacls` on this
profile: a directory under `C:\Users\<windows-profile>\` inherits `SYSTEM`, `Administrators` and
that one user — Full, and nothing else. No `Everyone`, no `Users`, no `Authenticated Users`. The
Windows ACL is the ward now, and for a single-user machine it is at least as tight as `700` was.

The case that would be a real regression is a home placed somewhere shared — `C:\Users\Public`,
a mapped drive, a synced folder — because those inherit `Everyone` and `Interactive` with write
access. The migration does not police that destination choice beyond refusing a non-Windows
filesystem; **a home placed in a shared folder is a decision the operator would be making, and it
would be a bad one.** Named here so it cannot be made by accident.

### What the move actually did, measured

| Fact | Before | After |
|---|---|---|
| The home | `/home/ymir/Documents/ymirhome` (ext4) | `/mnt/c/Users/<windows-profile>/ymirhome` (9p `v9fs`) |
| The Windows view of it | — | `C:\Users\<windows-profile>\ymirhome` |
| The resolver (`~/.config/ymir/home`) | the ext4 path | the 9p path |
| Append-only artifacts, verified by name | 26 | 26, sha256 for sha256 |
| The well (episodes) | 2 | 2, `integrity_check` ok on both sides |
| Capacity needed | — | 65 MB carried; 202 MB of virtualenv left behind |
| The old home | — | retained whole, undeleted, as the backup |

`bin/engine/ymir-validate.sh` passes with the moved home: twelve checks, every required one green,
one warning (`desktop apps not running`) that was there before the move too. The registry row now
reads the 9p path, which is the proof that the whole door chain followed the record rather than a
stale copy of it.

### Git on the mount — proven, not assumed

A Windows-backed checkout is not corrupting modes or line endings *when it is told not to*, and
"told" means two settings that are not the defaults:

- **`core.filemode=false`** — the mount invents `777` for everything, so git would otherwise
  report every file as having changed mode. A dirty tree from no edit at all.
- **`core.autocrlf=false`** — with translation on, a file goes LF→CRLF on checkout and CRLF→LF on
  commit. One round trip is invisible; a `git diff` in between is not, and a merge across the
  divide is a conflict made of nothing.

The migration proves both with a real probe on the destination, not a claim: it initialises a
repository on the mount, commits a file with LF endings, and asserts that `git status` is clean,
that no `100755` appeared for a plain file, that the committed blob contains no `\r`, that a
`chmod` leaves the work tree clean, and that `git fsck` reports no damage. If any of those fail,
the migration refuses to make the destination the home and the old home stays the home.

### The two faults the move exposed

Both were found by the migration itself, which is the reason it verifies instead of believing.

**The case fold.** The home held `hodd/machines/DESKTOP-FRS81OR/plans/README.md` and
`hodd/machines/desktop-frs81or/plans/README.md` — two files, one path once the filesystem folds
case, different content. The first copy silently lost one of them, and the inventory caught it
before anything was repointed. The migration now finds such groups before the first byte, names
every member, and **refuses** by default. With `--heal-case-collisions` it carries the first of
each group and drops the rest from the copy *while saying which*, and the old home keeps every
one of them. A **tracked** path in a collision is never dropped: a tracked file is part of the
record, and the naming is the operator's to fix.

**The resolver ate the space.** `bin/vault/hoard-lib.sh` read the recorded home with
`tr -d '[:space:]'`, which deletes whitespace *inside* the string. A Windows profile path very
often contains a space, so `/mnt/c/Users/<windows-profile>/ymirhome` resolved as
`/mnt/c/Users/AgentSeb/ymirhome` — a directory that does not exist. Every door then failed to
find the home while cheerfully reporting a path. It was invisible until the home moved somewhere
with a space in it, which is exactly the kind of bug a move exists to find. The reader now trims
the edges only, and also strips a trailing `\r` for a record written from the Windows side.

### How to ask for the move

The migration never chooses a destination. Where the operator's home lives is his decision.

```bash
# preview: names every directory it will touch, writes nothing
YMIR_HOME_TARGET='/mnt/c/Users/<you>/ymirhome' bin/engine/ymir-migrate.sh apply --dry-run

# do it: copies, verifies, repoints once, idempotently
YMIR_HOME_TARGET='/mnt/c/Users/<you>/ymirhome' bin/engine/ymir-migrate.sh apply
```

With no destination recorded it **defers** (exit 3) rather than failing, and the migration engine
now understands a third outcome: deferred is reported, never recorded as applied, and never
treated as an error. Recording it as applied would have silenced it forever.

Before it writes anything it stops on: a live well (a store being written while it is copied is a
torn copy), a destination that is not a Windows mount, too little room, a tracked case collision,
or an append-only inventory that comes back empty — because an empty inventory means the move
cannot name what it is carrying, which is the fault Rule 06 exists to catch.

After it finishes it says what the move does **not** do: the well and the model bridge were raised
with the old path and must be restarted, and the venv must be rebuilt if the voice is used. A
running process keeps the path it was born with.

### Left unmade, on purpose

- **The old home is not deleted.** It stands at `/home/ymir/Documents/ymirhome`, whole, including
  the file the case fold dropped from the copy. Removing it is the operator's act, after the new
  home has been lived in.
- **Project checkouts are not moved by this migration.** The decision says they may cross; the
  moving of a checkout carries its own risk (build output, `node_modules`, a test that must be
  re-run on the new ground) and earns its own errand. The two git settings and the probe are here
  for it to use.
- **The runtime is not moved, ever, by this migration.** Said in the header, said in the output,
  said here.

### Files

- `.agents/migrations/0022-the-home-moves-to-windows.sh` — the move, its pre-flight, its dry run, its refusal
- `bin/engine/ymir-migrate.sh` — passes `--dry-run` through, and understands `exit 3` = deferred
- `bin/vault/hoard-lib.sh` — the recorded home is trimmed at the edges, never inside
