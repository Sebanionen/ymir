# Rule 13 — Pi extensions: one home, pi's own layout, and a gate that proves it

> Adopted 2026-10-04, after an investigation that found the extension tree's source split across
> two directories, the running harness three days stale, and the document that governs it
> answering "where does an extension live?" two incompatible ways.

**Built on [pi.dev/docs/latest/extensions](https://pi.dev/docs/latest/extensions) and on the
installed loader's own rule.** Where this rule and habit disagree, pi's source wins.

## What pi actually does — the three facts the rule rests on

1. **An extension is a file or a directory with an entry point.** Pi loads direct `.ts`/`.js`
   files, and a **subdirectory only if it holds `index.ts` or `index.js`** (or a `package.json`
   with a `pi` field). From the installed loader: *"No recursion beyond one level."*
   **A helper directory named `lib/` is therefore never scanned — and that is correct.**
2. **Two auto-discovered locations exist**: `~/.pi/agent/extensions/` (global) and
   `.pi/extensions/` (project). **Pi does not de-duplicate.** An extension in both registers its
   tools twice, pi exits with `Tool "<name>" conflicts with …`, and **no agent can be seated.**
   The symptom is remote — herdr reports "the pane must sit at an interactive shell prompt".
3. **A deploy is a copy, and nothing re-runs it.** A repo edit changes nothing in the running
   harness until something deploys it again.

## The law

1. **One home per extension, ever.** The source is `.pi/shared/extensions/`; the deployed copy
   is `~/.pi/agent/extensions/`, written by `bin/seat/valknut-load.sh --pi`. **Never the same
   extension in both, and never in two of the three trees.**
2. **`.pi/extensions/` registers nothing.** It holds no-op factories that exist solely to stop a
   duplicate collision, and nothing else. **A file there that grows past a no-op is a bug**, and
   `--check` fails on it.
3. **A multi-file extension is a directory with an `index.ts`.** A single-file extension is a
   single file. **An extension's own internals live inside its own directory** — Ró's helpers
   belong to Ró, Skuld's to Skuld. **A shared `lib/` is only for what genuinely has no owner**,
   and every entry in it states why.
4. **No thin loaders.** A project-local file that imports a shared factory and calls it with
   `pi` registers the same tools a second time, from a directory pi already scanned. **You
   cannot both deploy a copy and load the source.** Pick one; we deploy.
5. **Take `pi` as `any`.** `@earendil-works/pi-coding-agent` is **not installed as a package**
   here, so an extension that imports its types cannot load at all. Declare tool `parameters` as
   a plain JSON schema object.
6. **Start nothing in the factory.** Per pi's docs: do not start processes, sockets, watchers or
   timers in the factory — some invocations load extensions without starting a session. Begin
   at `session_start`; release at `session_shutdown`, idempotently, because reload, session
   replacement and process exit all converge on that path.
7. **Load order is a contract.** *"Handlers run in extension load and registration order."* A
   restructure that changes the tree must prove Sýn's `before_agent_start`, Gná's
   `session_start` and Skuld's supervision still seat.
8. **Deploy both the extension and everything it imports.** Copying the top-level files without
   their modules ships extensions that **cannot load** — the exact failure that made
   `Cannot find module ./lib/…` the first symptom anyone saw.
9. **The gate is `bin/seat/valknut-load.sh --check`, and it must pass.** Deployed tree byte-identical
   to source; helper modules deployed; no test file in the live tree; nothing in two load paths.
   **A gate that only ever passes is worse than no gate**, so every check is proved by breaking
   the thing it watches.

## Why, in one sentence

**Nothing in the extension tree is wrong in a way that throws — it is wrong in a way that lists
cleanly**, which is why a stale deploy, a half-finished migration and two contradictory
descriptions all survived until somebody went looking.

## The failures this rule exists to prevent

| | measured 2026-10-04 |
|---|---|
| **a stale deploy, invisible** | deployed `ymir-subagents.ts` was **12,991 B against a 13,748 B source**. The missing lines are `bin/agents/erindi-brief.sh` — the fix that stops a dispatch seating a figure with an unfilled brief. Every file listing looked correct |
| **an unfinished migration** | plan 29 built a flat `.pi/extensions/` + `lib/`. Plan 58 moved the extensions to `.pi/shared/extensions/` and **did not move their internals**, so the loader grew a second copy line. One system, two sources, and the second was never planned |
| **a specified-but-unbuildable half** | plan 58 says `.pi/extensions/*.ts` should be "thin loaders that pull the shared set". That is mutually exclusive with a copy deploy, so they became no-ops. **The next reader reads that row as an outstanding task** |
| **the doc answering twice** | one table said `.pi/extensions/` held the governance four; a later section said *"never in `.pi/extensions/`"*. Neither was true |
| **a collision that seats nobody** | two load paths register the same tool twice and pi exits. The only symptom herdr can report is that the pane will not sit at a prompt |

## Not this rule's business

**`~/.pi/agent/agents/` and `.agents/agents/` are governed by Rule 02** (agents, not
extensions). **MCP servers** are `pi.registerMcpServer()` or `mcp.json`, not extensions. **The
other harnesses** — OpenCode, Claude Code, Codex, Cursor — have their own adapters and their own
governed asset; this rule is about the **Pi** extension surface only.

---

## 2026-10-07 — the one tree (the two-home half of this rule is retired)

Commit `ac5fd8ad` (2026-10-04) ended the two-home design this rule was written
around: **`.pi/shared/extensions/` no longer exists — the extensions live in
`.pi/extensions/`, and nothing is deployed to `~/.pi/agent/extensions/`.** The law
this rule exists for still holds — **one home per extension** — but *which* tree is
the home changed, and the loader no longer copies.

What stands now:

1. **One home: `.pi/extensions/`.** Source and live tree are the same directory. A
   multi-file extension is a directory with an `index.ts`; a bare `lib/` is a helper
   tree pi never scans, so it is not an extension.
2. **The global home holds no extension.** `bin/seat/valknut-load.sh` removes any
   `~/.pi/agent/extensions/<name>` that also stands in the project tree, and writes
   only `.ymir-root` there — a root record, not an extension.
3. **The gate is still `bin/seat/valknut-load.sh --check`.** It fails when an
   extension stands in two load paths, or when the root record is missing.
4. **Roots are walked, not counted (Rule 12).** An extension finds the repo through
   the `.ymir-root` record and a walk to the tree owning `.pi/` and `RULES/`.

**Superseded text, named so a reader is not misled:** this rule's §1 "source is
`.pi/shared/extensions/`", §2 "`.pi/extensions/` holds no-op stubs", and any sentence
describing a *deploy* to the global home. The failures table above is kept unchanged
— it still teaches *why*: two load paths seat nobody.

---

## 2026-10-10 — global reach, still ONE home: the user-settings extension path

Appended, not rewritten. The 2026-10-07 correction moved the home to `.pi/extensions/` and
retired the global copy. It left one gap: a project tree is **only** discovered when a session's
cwd sits inside it, so a session working in another repository (`~/CodeP/excalidraw`, say) loaded
none of Ymir's extensions. The fix is not a second home — it is telling pi where the one home is.

**Pi's discovery has three sources, not two** (measured in pi's own loader,
`dist/core/extensions/loader.js: discoverAndLoadExtensions`):

```
discovery[3]{order,source}:
  "1","<cwd>/.pi/extensions — the project tree"
  "2","~/.pi/agent/extensions — the global home"
  "3","the user settings `extensions[]` array — absolute paths and ~ are supported"
```

Source 3 is what we use. `bin/seat/valknut-load.sh --pi` now also writes this checkout's
`.pi/extensions` into `~/.pi/agent/settings.json`'s `extensions` array, idempotently, keeping
every other entry (a flag such as `-builtin:mcp` is left untouched) and pruning a path that
points at some *other* checkout's extensions tree. `--check` asserts it and fails without it.

**Why this does not create the double registration this rule exists to prevent.** Sources 1 and 3
yield **absolute paths to the same files**, and the loader de-duplicates:

```
seen[2]{fact,evidence}:
  "the loader keeps a Set","`const seen = new Set()` … `if (!seen.has(resolved))` — discoverAndLoadExtensions"
  "both sources resolve identically","discoverExtensionsInDir returns path.join(dir, name), absolute; the configured path is resolved and then enumerated the same way"
```

Measured 2026-10-10, calling pi's own `discoverAndLoadExtensions` with the real
`~/.pi/agent/settings.json`, from three cwds:

| cwd | extensions loaded | duplicates | the door present |
|---|---|---|---|
| `~/CodeP/excalidraw` | 20 | **0** | yes |
| `~/ymir` | 20 | **0** | yes |
| `/tmp` | 20 | **0** | yes |

**A copy would double-register; a symlink would too** — a symlink resolves to a different string
and the Set is keyed on the resolved path, not on `realpath`. Naming the same directory is the
only mechanism that keeps one home *and* reaches every session, which is why it is the one this
rule now records.

Superseded sentence, named so a reader is not misled: *"Pi reads `${HOME}/.pi/agent/extensions/`"*
in the harness-integration asset — still true, and no longer the whole truth.

## 2026-10-24 — the worktree case: a worktree of the seat is ONE home, never a second

Appended, not edited: the law above stands. This is the case it could not name, and the
reason four errands died on 2026-10-24 with a bare shell at a prompt
(`docs/fixes/seat/2026-10-24-a-worktree-carries-no-second-extension-home.md`).

A Yggdrasil worktree checks `.pi/extensions/` out like any other file, so a pi seat inside
it loaded the same eighteen extensions **twice** — the worktree's copy and the settings-named
seat tree, two absolute paths, two registrations, eighteen tool-name collisions, pi exits,
and the dispatcher types the brief into what is left. The law was right; nothing enforced it
inside a worktree.

```
worktree_extension_home[4]{rule,where}:
  "a worktree is created WITHOUT .pi/extensions/","bin/forge/yggdrasil.sh create — per-worktree sparse-checkout, non-cone: '/*' and '!/.pi/extensions/'"
  "the exclusion is sparse, never a symlink and never a delete","the files stay tracked and the worktree stays clean; a symlink shows as deleted tracked files and must not ship"
  "a worktree of the SEATED repository is ONE home","valknut-load.sh --check: state `shared`, served by the seat tree — PASS"
  "a worktree that carries its OWN .pi/extensions is the fault","state `shared-copy` — FAIL, with the one-line `sparse-checkout set` repair printed"
```

"Same repository" is **asked of git** (`rev-parse --git-common-dir` on both trees, both
canonicalised), never inferred from a path: a tree of a different repository is its own home
and must pass on its own terms. `bin/seat/valknut-load.sh --ext-home` prints the verdict for
the tree you are standing in, so a human and a test ask the same door;
`.agents/tests/pi-extensions.test.sh` section 8 proves both directions hermetically.

An existing worktree is never rewritten. One that is not sparse keeps working, reports
`shared-copy`, and is repaired by its owner with the line the gate prints.

## 2026-11-02 (appended) — Pi is the first harness, not the only one

His word this day, while the platform claim was being audited:

> *"opencodes packets need to have the same functionality as the extentions for pi. and we need make more harnesses
> like claude and codex and others in the future. they need to be installed in root for the harnesses and the
> agents.md that the tools are reading needs to be updated on ymir installts and updates. so ymir works globally on
> their computers."*

This rule governs **the extension surface of one harness**. It now governs **the harness surface of the house**, and
the measurement behind that sentence is in `hodd/docs/audits/2026-11-02-harness-and-os-support-audit.md` in the home.

**What is already true.** `bin/backend/fm-harness.sh` identifies nine harnesses — claude · codex · opencode · grok ·
kimi · muse · pi · pi-signed · cursor — by ancestry and hook markers. Detection is not the gap.

**What the rule now demands:**

```
harness_law[6]{rule,what_it_means}
  "ONE CONTRACT, MANY HARNESSES","a harness is described by a descriptor — binary, launch, inject, read a transcript, list sessions, install a hook, global dirs, instruction file, capability flags — never by an `if pi` branch in a door"
  "THE TRANSCRIPT IS NORMALISED","five harnesses store history in three incompatible ways (Pi: JSONL tree; Claude and Codex: flat JSONL; OpenCode v2 and Cursor: SQLite). Every reader parses ONE house shape, produced by one normalizer, never a vendor's file directly"
  "PARITY IS NAMED, NOT ASSUMED","every capability the house ships for one harness is `full · partial · absent` for every other, with the reason. Absent is a pass only when it is written down; a silent gap is a lie"
  "GLOBAL INSTALL, NOT A CHECKOUT","extensions/plugins and the instruction file each tool actually reads (AGENTS.md · CLAUDE.md · .cursor/rules · codex AGENTS.md) are written into the USER'S OWN home on install AND re-verified on update — a house that only loads inside its own repo does not work on their computer"
  "NO VENDOR TELEMETRY DEPENDENCY","only one harness documents OTEL; the record that matters is the house's own ledger and its own transcript index"
  "A HARNESS CHANGE UPDATES THE MATRIX","adding or changing a harness updates the capability matrix and the install in the same change, or the matrix is drift (the twin of Rule 05's platform duty)"
```

**Why one home still matters.** This rule's original subject — one home per extension, `index.ts` per multi-file
extension, `valknut-load --check` as the gate — was written to stop two load paths seating nobody. The same fault
returns at a larger scale: two *harness* paths, one of them undocumented, is two halves of the house that never meet.
