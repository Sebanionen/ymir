# Installation & First Setup — stand the whole system up

> **Purpose:** Everything Galdr must know to install, provision, and repair
> Ymir for an operator who does not have it. The code is authoritative; this
> page is the map.

One command sets up the whole system for the user; it self-heals what it can and
reports what it cannot. It **asks for consent first** — with a plan it computes on
this host, not a recited paragraph — and it **validates at the end** that what it
claims is actually running.

```
bin/engine/ymir-install.sh               # the first setup (idempotent; asks to proceed)
bin/engine/ymir-install.sh --plan        # the plan, probed — changes nothing (--json too)
bin/engine/ymir-install.sh --check       # report only, no writes, no prompt
bin/engine/ymir-install.sh --yes         # non-interactive (accept the plan)
bin/engine/ymir-install.sh --skip-engines --skip-services
bin/engine/ymir-install.sh --no-desktop  # don't open the desktop apps at the end
bin/engine/ymir-install.sh --status      # alias of --check
```

## The plan comes first — `bin/bridge/ymir-plan.sh`

The consent a real install asks for is a **computed plan**, one row per step, each
carrying its state and the reason for it. A hardcoded paragraph cannot know the
host: the old one named an Omarchy version on a Mac, promised a workspace tree that
already stood, and never mentioned that no application had been installed at all.

```
bin/bridge/ymir-plan.sh              # the plan (TOON)
bin/bridge/ymir-plan.sh --json       # the same, for automation
bin/bridge/ymir-plan.sh --phase 5    # one phase
bin/bridge/ymir-plan.sh --blocked    # only what cannot proceed, and why
```

```
plan_states[5]{state,means}:
  "DO","a change will be made"
  "SKIP","already satisfied — nothing to do"
  "INFO","a fact about this host, discovered; no change implied"
  "BLOCKED","cannot run — the reason names what is missing"
  "CONSENT","needs the operator's word (a credential, an invite, the shells)"
```

```
plan_phases[9]{n,name,gate}:
  "0","resolve","this host, the container engine, the code root, and the home"
  "1","code","the tree is intact — and holds nothing of the operator's"
  "2","home","the operator's world, outside the tree"
  "3","runtimes","git/python3 · bun/uv/mcp<2> · pi · hermes · the terminal backend"
  "4","engines","treehouse · no-mistakes · sandcastle · the Utgard image"
  "5","apps","hlidskjalf · odrerir · sessrumnir · smidja — web build required, shell gated"
  "6","wire","the way in (auth · invite · heimdall) and the launcher entries"
  "7","raise","every port listening, then the desktop apps"
  "8","verify","what stands, honestly"
```

`ymir-install.sh` prints the plan at the consent prompt; `--plan`/`--dry-run` prints
it and exits without writing. The plan is recomputed on every run, so it cannot
drift behind the code the way a paragraph did. `bin/bridge/ymir-plan.sh` is the ward for
the law below: its phase-1 `purity` row names any of the operator's things found in
the code tree.

## Where things live — the package is code, the home is the operator's

**Law (Rule 04):** the package carries the **core systems** — everything needed to
run the programs. Everything the **operator** owns goes to `$YMIR_HOME`: their
info, their records, their documents, their settings, their state, their
credentials. A packaged install (npm) treats its tree as read-only; the next
upgrade replaces it, so anything of theirs kept there is kept at its peril.

```
roots[5]{root,resolves_from,holds}:
  "ymir_home_root","$YMIR_HOME → the choice recorded at installation → one documented default","everything private the operator owns"
  "hoard_root","$YMIR_HOARD → <home>/hodd","docs · secrets · identity · tenants · memory"
  "hoard_data_dir","$YMIR_DATA_DIR → <hoard>/data","this machine's records: operator, fleet, machines, the host profile"
  "hoard_state_dir","$YMIR_STATE_DIR → <home>/state","runtime state: pids, logs, locks, caches"
  "hoard_settings_dir","$YMIR_SETTINGS_DIR → <home>/config","settings: agents.yaml, cron.yaml, tailscale-sync, the wedge channel"
```

Plus `hoard_local_env` → `$YMIR_HOME/.env.local`: the operator's **credentials**
(`HLIDSKJALF_AUTH`, OAuth keys, tokens), never in the tree.

**The home is chosen, not assumed.** A real interactive install asks once
(`step_home`), records the answer as machine state under `~/.config/ymir/home`
(the same place `engram-python` and `accounts.json` live), and every later script
resolves it through `bin/vault/hoard-lib.sh`. `--check` never writes; `--yes` takes what
is recorded, else the documented default.

**No script carries its own default (2026-09-24; widened 2026-09-30).** Every
governed script that needs the home calls `ymir_home_root`; none restates a path.
Hand-converging this once already failed — nine scripts were fixed and a tenth was
found a week later only by reading — so the rule is now a **lock**:
`bin/gates/guards/defaults-guard.sh` refuses a home default anywhere outside the two definition
sites — `bin/vault/hoard-lib.sh` in bash and `src/ymir_runtime/paths.py` in python — and
a waiver must be written on the line it applies to. The same ward also refuses a
script that *uses* the home without resolving it, which is the class the first
pass missed: a file can be free of literals and still be unable to find anything.

```
defaults-guard[3]{class,refuses,note}:
  "a guessed default","any absolute path naming a seat's own home","code only; a comment or runbook may quote a path, and a test fixture must name a synthetic one"
  "an unresolved home","a file that reads $YMIR_HOME without calling the resolver","the literal pass is structurally blind to this"
  "an absolute symlink","a TRACKED link whose target is absolute","a link's content IS its target, so no grep of the worktree can see it"
```

The third class is the one that shipped a machine into every clone: `state` was
tracked as a link to `$HOME_SEAT/Documents/ymirhome/state`, so each seat
inherited a dead link and the seat that wrote it never saw the failure. The law is
one line — **a tracked link is relative and in-tree** — which Rule 02's harness
links and `config` → `.agents/config` already satisfy. `.gitignore` refuses the
path itself (`/state`, not `state/*`, which cannot match a link *named* `state`),
and an absent link is a pre-install note the install seats per machine. The scan
covers `bin/ .agents/ tools/ scripts/ src/`: guarding the doors and not the yard is
how `tools/mill/worker.sh` came to carry three absolute paths unchallenged.

```bash
bin/vault/hoard-lib.sh                     # the lib (source-safe; functions only)
ymir_home_root   HOME                # → the home
hoard_settings_dir SETTINGS          # → <home>/config
hoard_local_env  ENVFILE             # → <home>/.env.local
```

**Rule for new code:** never write `$ROOT/data`, `$ROOT/state`, `$ROOT/config`,
`$ROOT/.env.local` or `$ROOT/workspace`. Resolve the root through the lib. A script
that points an operator's thing into the tree is the bug the `purity` row exists to
catch.

### The engine builds its own home — `src/ymir_runtime/` and its private venv

The agent-execution road (seat · status · send · stop) lives in the tracked tree
as `src/ymir_runtime/` — python, **stdlib only**, so a bare `python3` runs it and
the install has nothing to compile. A harness never reads it: only a `bin/` door
calls it (`bin/engine/ymir-engine.sh`; behind it `bin/agents/eindri-start.sh` and
`bin/agents/einherjar-spawn.sh` are thin adapters).

When the engine ever grows a dependency, the venv appears **without the tree
changing** — a private, machine-local home built at first use, exactly the
`~/.fleet/well-venv` pattern:

```bash
bin/engine/ymir-engine-ensure.sh          # status of the engine's own home (idempotent)
# → engine-ensure[1]{venv,state,deps}:
#     "$HOME/.fleet/ymir-engine-venv","not needed (stdlib only)","0"
```

`src/pyproject.toml` is the one declaration of that dependency list; the ensure
script reads it and provisions `$YMIR_ENGINE_VENV` →
`$HOME/.fleet/ymir-engine-venv` (override wins) only when the list is non-empty.
Nothing is ever committed: the repo ships source, the seat builds its own home.

The engine's unit tests sit **beside the modules** (`src/ymir_runtime/tests/`) and
are reached by a bare `python3 -m unittest` from the checkout root; the live
proofs are `tests/e2e/engine-proof.sh proof|parity`.

### Carrying an existing tree home — migration 0005

Every *writer* resolves the home now, but an installation made before this change
still holds the operator's things in the tree. `.agents/migrations/0005-roots-out-of-tree.sh`
carries them:

```
what moves           from                    to
------------------   ---------------------   ----------------------------
this machine's       data/                   <hoard>/data
  records
runtime state        state/                  <home>/state
  (pids · logs ·     (including the          (running services keep their open
   locks · the        applied-migrations      fds across the move — `mv` keeps
   applied-marker)    marker)                 the inode)
credentials          the local env file      $YMIR_HOME/.env.local (0600)
settings             .agents/config/*        <home>/config
                     that git does NOT track
```

One name, two files — the migration decides by evidence, never by assumption:

```
collision[3]{case,what_happens,nothing_lost}:
  "identical content","the tree's copy is removed","the content is provably at home already"
  "different content","the home's keeps the name; the tree's is carried beside it as <name>.stale-<UTC>","both are real, so both are kept — never merged, never discarded"
  "not a plain file","left in place and reported","a directory is not silently swallowed"
```

Templates and defaults never move: `*.example` (and `*.example.*`), `.gitkeep`, and
any settings file **git tracks** — that is the distro's shipped default, not the
operator's. The plan's `purity` row applies the same rule, asking git about the
real path (the tree's `config` is a symlink into `.agents/config`, and git tracks
what the index holds, not the link). Idempotent: a second run changes nothing.

```bash
bin/engine/ymir-migrate.sh status            # pending / applied
bin/engine/ymir-migrate.sh apply --dry-run   # name the migration, touch nothing
bin/engine/ymir-migrate.sh apply             # carry it
```

Stop the runtime first if you want no stale pid files; nothing is lost either way.

## Operating it afterwards — the doors, the cloth, and the shapes

### The doors (the CLI), named for the figure who does the work

`npm install -g @zerwiz/ymir` puts **two** commands on PATH: `ymir` (the front
door) and `ymir-install` (the bare installer). Everything else the operator
needs is a door on `ymir` — never a script path inside `node_modules`.

```
doors[14]{verb,door,what}:
  "ymir","first setup (a bare call installs)","the plan, then consent, then the work"
  "ymir install [...]","bin/engine/ymir-install.sh","the same, said out loud"
  "ymir plan","bin/bridge/ymir-plan.sh","what an install would do here — writes nothing"
  "ymir raise / lower","scripts/start.sh · stop.sh","lift the hall, or lay it down"
  "ymir eir","bin/agents/eir-doctor.sh","what stands, and mend what does not (the healer)"
  "ymir groa","bin/agents/groa-update.sh","take the latest, then mend this home forward"
  "ymir groa migrate","bin/engine/ymir-migrate.sh","heal this home's structure"
  "ymir heimdall","bin/engine/ymir-setup-auth.sh","the way in — status · set · github (the guardian)"
  "ymir invite","bin/engine/ymir-invite.sh","let someone else in — mint · list · revoke"
  "ymir smidja","bin/desktop/smidja-board.sh","the smithy's board on :8437 — build · start · stop · status"
  "ymir hlidskjalf","scripts/electron.sh start --view hlidskjalf","the high seat's window"
  "ymir sessrumnir","scripts/electron.sh start --view sessrumnir","the seat-hall's window"
  "ymir mimir","bin/records/mimir.sh","the memory well"
  "ymir sense","bin/host/host-sense.sh","what THIS machine is"
```

A name the law has not given a home is still answered, once, with the name that
has it: `ymir doctor` → *the door is named `ymir eir` now*. Colour appears only
where a human watches.

### The cloth — `bin/desktop/ymir-style.sh`

Ymir had correct output and no design. The cloth is cut from the same stone as
the halls (`midgard/design-system/tokens.css`): **bone** `#cfc3a9` for words,
**bronze** `#c9973f` for what acts, **steel** `#96a0a8` for what stands, **blood**
`#c2584a` for what is wrong, and a mark per state (`◆` do · `·` already · `—`
fact · `✕` blocked · `?` needs your word · `✓` proved).

```
cloth_rules[4]{rule,why}:
  "colour and marks only when stderr is a terminal and NO_COLOR is unset","a pipeline never parses a decoration"
  "data on stdout, the human rendering on stderr","the TOON row is the data; the coloured line is for the eye"
  "the words are never conditional — only the colour is","hiding information to save colour is the wrong trade"
  "no banner over four lines, no rule longer than its text","density first (Monoline TUI · cli-guidelines)"
```

`bin/bridge/ymir-plan.sh --colour` renders the plan in the cloth on stderr while the
TOON stays on stdout. The installer prints it at the consent, and ends with the
next steps — *a reaction for every action, a next step for every ending*.

### A clone and a package are one tree — `bin/desktop/app-lib.sh`

The apps are the only thing that differs between the two shapes, and only in
where they live:

```
surface            a clone                  an npm install
---------------    ----------------------   ------------------------------------
hlidskjalf         apps/hlidskjalf          node_modules/@zerwiz/hlidskjalf
hlidskjalf-mobile  apps/hlidskjalf-mobile   node_modules/@zerwiz/hlidskjalf-mobile
odrerir            apps/odrerir             node_modules/@zerwiz/odrerir
sessrumnir         apps/sessrumnir          node_modules/@zerwiz/sessrumnir
smidja             apps/smidja-factory      node_modules/@zerwiz/smidja-factory
```

`bin/desktop/app-lib.sh` answers for both — `app_dir <surface> <var>`, `app_pkg
<surface>` — and **eighteen files** were converted to it: the raise path
(`scripts/start.sh`), the windows (`scripts/electron.sh`), the invite door, the
seat-hall trio, Eir, the icon mint, the desktop placement, the hall snapshot, and
the installer's own SPA and shell steps. `bin/desktop/smidja-lib.sh` delegates to it, so
there is **one** truth about where things live.

**`app_class <surface>` is the second answer it owns (added 2026-09-24).** The
window class a surface PRESENTS (`ymir-hlidskjalf` · `ymir-smidja` ·
`ymir-odrerir` · `ymir-sessrumnir`) is decided here once. It must equal the
surface's `.desktop` `StartupWMClass`, the generated Hyprland window rule, and
the slug the Electron sets (`app.setName` / `appendSwitch('class')`). It did not:
`bin/desktop/desktop-place.sh` declared `CLASS_sessrumnir="sessrumnir"` while the app
presents `ymir-sessrumnir`, so the rule and the entry matched nothing and every
Ymir key seemed to open one app. Rename a class HERE first;
`bin/desktop/desktop-verify.sh --class-only` asserts the invariant and
`.agents/tests/desktop-classes.test.sh` holds it in the tree.

**The trap that named itself.** `printf -v <name>` writes to the *function's*
scope. A helper whose scratch variable shares the caller's requested name
swallows the answer — `app_dir hlidskjalf c` returned nothing because the
helper's own `local c` held the path. Every scratch name in the resolvers is
function-prefixed (`_apd_c`, `_smd_c`, `_apr_root`) for exactly that reason, and a
new resolver must follow the rule.

**Why it matters beyond tidiness:** a packaged install shipped with eighteen
scripts looking in `apps/`, so `ymir raise` died on
`cd …/apps/hlidskjalf: No such file or directory` while every package had in fact
arrived. A shape assumption is a bug that only shows itself on the *other* shape.

### The hall answers on the port it was given

`scripts/start.sh` raises the SPA, and the SPA must listen on
`$HLIDSKJALF_PORT` (3888 by default) — every other door looks for it there. Two
rules came out of a packaged install where it listened nowhere:

```
spa_serving[2]{shape,how}:
  "a packaged install","serves its built ./dist with `vite preview --port $PORT --strictPort`"
  "a clone","serves the dev server, but STILL on $PORT — `npm run dev -- --port $PORT --strictPort`"
```

A bare `npm run dev` lets Vite take 5173 and the hall silently answers on the
wrong port; the raise now prints the log's last lines when the port stays silent
rather than claiming success. Óðrerir resolves through `bin/desktop/app-lib.sh` like every
other surface (it read as `missing apps/odrerir` on a packaged install).

### The marks land on any desktop — not only Omarchy's

`bin/desktop/desktop-place.sh` holds **two kinds of thing**, and they were behind one gate:

```
desktop_halves[2]{half,who_reads_it}:
  "the window rules (numbered desktops, the Lua rule)","Hyprland / Omarchy only"
  "the launcher entries and the rune icons","the freedesktop standard — GNOME, KDE, Hyprland alike"
```

A GNOME operator gets entries and icons and no window rules, which is the correct
answer — and the reason a packaged install on GNOME placed *nothing* while the
clone's marks already existed. `bin/desktop/desktop-place.sh entries` is the launcher half
alone (any Linux desktop), the installer's `marks` step calls it, and both the
desktop database and the icon cache are refreshed after.

### Every notice can be silenced — `ymir config`

Some lines are information the first time and noise the tenth. A user must be able
to say **not again**, once, and be believed. The preferences live in the operator's
settings (`<home>/config/notices.conf`, one `key=on|off` per name) and the door is:

```
ymir config                          # what is shown, and what is not
ymir config notice version off       # silence one; `on` restores it
judgment[4]{key,what}:
  "version","the line that says which version moved to which"
  "patience","the long-hour words before a slow install or build"
  "next","the where-to-go-from-here block at the end"
  "hints","the one-line helpers that say how to hide a notice"
```

Every notice that can be silenced **says so once**, in the cloth's faint voice —
`(not again: ymir config notice version off)` — so the way out is discoverable
without a manual. Absent means on; a preference is honoured by the shell cloth
(`notice_wanted`, `notice_hint`) and by the CLI alike. `ymir-install.sh`'s marks
and the raise path honour it too.

### Four surfaces, one raise

`ymir raise` lifts the whole hall — the SPA (`:3888`), Óðrerir (`:4322`), the
board (`:8437`), and the commit-hall Sessrúmnir rises in the same motion (it is an
Electron app of its own, not a browser surface). `ymir-install.sh`'s desktop step
opens **one window per surface** rather than a single "both".

### What a user went from, and to

`npm install -g` prints *"changed 266 packages"* and no versions. The CLI records
the version it last ran in the home's state (`state/version`) and says the
transition **once**, on the first run after an update:

```
  the tree moved  0.1.7 → 0.1.9
  run `ymir eir` to see what stands, `ymir raise` to lift the hall
```

### The patience words — `style_patience`

A long hour must say what it is doing. `bin/desktop/ymir-style.sh` carries the line, and
the installer's long chain and the raise path's build open with it:

```
◆ much moves   the halls are being stood up for the first time
      this hour is long, and nothing of yours is lost in it —
      roots come home, shapes are re-cut, names are set true again.
      Your patience is noted, and it is earned.
```

Written in the house voice, kept under four lines (density), and shown on stderr
with everything else the cloth renders.

### Two libs the packaged tree needs

```
libs[2]{path,resolves}:
  "bin/desktop/smidja-lib.sh","the smithy: apps/smidja-factory in a clone, node_modules/@zerwiz/smidja-factory in a package — `smidja_factory_dir`, `smidja_visualizer_dir`"
  "bin/desktop/electron-lib.sh","whether a shell's runtime VERIFIES: `electron_runtime_state` (ok · partial · absent) and the exact remedy"
```

**Why they exist.** A packaged tree has no `apps/`: the smithy arrives as a
dependency and the skill symlink dangles. Four call sites assumed the clone's
layout, so the visualizer read as unbuildable in a package. They resolve through
`bin/desktop/smidja-lib.sh` now.

**And a shell is never declared ready on a directory's presence.** npm gates
install scripts; a skipped Electron postinstall leaves `dist/` partial and
`path.txt` unwritten, so the web app builds, every check passes, and the window
never opens. `electron_runtime_state` verifies, and the plan's `electron` row
says *the runtime is PARTIAL* with the command that mends it.

## The app packages — how the four surfaces arrive

The distro depends on the surfaces as their own npm packages, so one
`npm install -g @zerwiz/ymir` fetches them into the tree:

```
app_packages[4]{package,repo,what}:
  "@zerwiz/hlidskjalf","zerwiz/hlidskjalf","the control plane — dist/ ships built, served on :3888"
  "@zerwiz/odrerir","zerwiz/odrerir","the live hall — dist/ ships built"
  "@zerwiz/sessrumnir","zerwiz/sessrumnir","the seat-hall desktop — out/ ships built (a fork of pi-desktop)"
  "@zerwiz/smidja-factory","zerwiz/smidja","the smithy and its visualizer — the factory plus the UI's source, built at install"
```

They are **optionalDependencies**, deliberately: a broken app package must never
stop the CORE from installing, and a package not yet on the registry is skipped by
npm and starts arriving the moment it is published. The plan's phase-5 rows report
each surface separately — installed, declared-but-not-fetched, or no package at all
— so a silent skip cannot hide.

A global install nests them under the distro's own `node_modules`
(`<prefix>/lib/node_modules/@zerwiz/ymir/node_modules/@zerwiz/<app>`); a local one
hoists them to `node_modules/@zerwiz/<app>`. The plan checks both shapes.

```
bin/forge/npm/npm-publish.sh                       # the platform only
bin/forge/npm/npm-publish.sh --all                 # the platform + every app package
bin/forge/npm/npm-publish.sh --dry-run --all       # what would go out, and from where
bin/forge/npm/npm-publish.sh --unpublish @zerwiz/ymir@0.1.5   # take ONE version back
```

**A version can be taken back, and the window is short.** npm permits unpublishing
**one version for 72 hours** after it was published; past that it is npm support's
door. So `--unpublish` demands a spec that names the version — never a bare name —
and the row says where the CDN may still serve the tarball for a while afterwards.
Publishing a newer version is the other half of the repair: it moves the `latest`
tag off the bad build at once, even before the removal propagates.

**A `files[]` entry that names a directory overrides `.gitignore`.** This is how
`@zerwiz/ymir@0.1.5` shipped the memory well: `files: [".agents/"]` packed that
subtree *including* the gitignored stores, and the repo stayed clean while the
artefact did not. Name what ships, exclude what must not, and prove it with
`npm pack --dry-run` — the repo's cleanliness says nothing about the tarball.

The app repos are cloned into `apps/` by the install's `apps` step (from the
registry's `repo: apps/<path>` blocks), which is where `--all` reads their
manifests. The token comes from the hoard, never from `~/.npmrc`.

The seeded `projects.yaml` teaches the **current** key: a project row names its
**realm** (`realm: personal`), not a workspace — that key was `workspace:` before
plan 62 (2026-10-01). A registry written before the rename still works: readers
resolve both through `bin/skuld/registry-lib.sh` and name the old key when they see it,
and `bin/engine/ymir-validate.sh`'s `registry` check warns (never fails) about rows still
carrying it. The operator's live registry is renamed by hand, with his word.

The registers beside it are **one file for one fact**, and each arrives from its template
in `registry/` — never a heredoc in the installer (plan 128): `companies.yaml` holds the
houses the operator IS, `clients.yaml` the companies a house SERVES. A client is a company
whose owner is not us, served by exactly one house (`served_by`), with its own realm and
its own decisions — never a house, never a member of one. So a place can say whose client
it is: `place.yaml`'s `client_of: <house-id>` makes a place whose `company:` is a client
resolve, and `projects.yaml`'s optional `client: <client-id>` names the client a project is
for. `bin/identity/place-validate.sh --all`, `bin/identity/clients.sh validate|check` and
`bin/identity/projects-validate.sh` are the doors that decide it, and the `clients` step
reads the same door: a place that cannot say whose client it is is a **RED** naming the file
and the fix, never a shrug.

## The steps

```
install[35]{step,what,self-heals}:
  "panes","the run shown in a herdr pane","bin/seat/herdr-run.sh sits a pane beside the caller when inside herdr; inline otherwise — a pane that cannot be raised never loses the work"
  "prereqs","git python3 bun docker|podman gh · mcp<2","bin/engine/prereq-ensure.sh installs bun+uv+mcp in user space; engram is an honest optional SKIP"
  "memory-well","the engram engine (Mimirsbrunn)","optional; reported with the exact next command, never a fake fix"
  "home","the home the operator CHOOSES, recorded under ~/.config/ymir/home","asks once, records the answer; --check never writes, --yes takes what is recorded, else the documented default"
  "tree","workspace/{work,personal}/<domains>, companies/, workspaces.yaml, projects.yaml, and the hoard OUTSIDE the repo (secrets/ · docs/ · identity/ · tenants/ at the hoard root under the chosen home)","creates if missing; hoard_root resolves through bin/vault/hoard-lib.sh so no script can point the hoard inside the checkout (Rule 04), and an empty secrets/platform.env (0600) is seeded so bin/vault/hodd.sh emit resolves"
  "clients","the client register — the companies a house SERVES, beside the houses it IS (plan 128)","seeds hodd/identity/{clients,companies}.yaml from registry/*.yaml.example when absent through ONE door — bin/identity/registers-seed.sh (one source each, never an inline heredoc; an existing register is never touched) and then reads the ONE door — bin/identity/clients.sh validate for the register's shape, bin/identity/place-validate.sh --all for every place's client_of/served_by relation; a place whose client_of names no resolvable client, or an absent register beside a place that declares one, is a FAIL naming the file and the fix — absent is a red, not a shrug"
  "apps","the app repos (the app split) — hlidskjalf · hlidskjalf-mobile · odrerir · sessrumnir · smidja","reads $HOARD/identity/projects.yaml (never guesses a remote); clones a missing apps/<path> from its registered git{} block, fast-forwards a present one, and stamps the smithy engine (apps/smidja) from the cloned factory's templates"
  "engines","treehouse · sandcastle · no-mistakes","installs treehouse + no-mistakes from their installers"
  "local-model","the local brain for THIS hardware — a CUDA llama.cpp engine, the best model that fits, pi wiring, and Ymir registration","bin/model/llama-ensure.sh ADOPTS a standing CUDA llama-server (proves CUDA0, never rebuilds it) and only builds with GGML_CUDA=ON when none exists; bin/model/model-fit.sh picks the largest model that fits the PROBED GPU/VRAM/RAM/disk (generic — never this box); bin/model/model-fetch.sh downloads it resumable, checksummed, consent first, into the hoard; bin/pi/pi-model-wire.sh wires ~/.pi/agent/models.json (exact served id + key reference) and proves a one-shot; bin/model/model-register.sh writes the same model into the hoard config/agents.<host>.yaml overlay so Ymir/Smidja share one model road; bin/model/model-tune.sh measures the real ctx/ngl/n-cpu-moe/kv/fa and replaces the placeholder in data/local-models.md. When a local rail already serves models, NOTHING is downloaded — the operator's registered model is adopted. Loud refusals (no CUDA, unknown hardware, no disk, bad checksum), never a silent skip"
  "hermes","the Nous Research agent runtime","installs via bin/engine/hermes-ensure.sh when absent"
  "snotra","the meeting ear's engine — whisper.cpp + a model","systems/snotra/services/ear/snotra-ensure.sh reports the seat's engine and installs what is missing (pacman/apt/build); a voxtype seat keeps its models. The MCP face + unit ride the fleet step — and so does the WATCH (snotra-detect), which the fleet step raises by CAPABILITY on any seat with a microphone: a call seat owes the ear's watch, a headless heart reports a clean skip"
  "voice","the voice engines — whisper.cpp (speech → text) + piper (text → speech), each with a model","bin/voice/voice-ensure.sh ADOPTS what stands and installs what is missing: the whisper half is delegated to systems/snotra/services/ear/snotra-ensure.sh (one road), the piper half installs via pipx or a venv under $YMIR_HOME and fetches a voice (.onnx) into $YMIR_HOME/voices. Machine property, in the hoard — never the tree. Loud refusals (no python/pip, no network, no model), never a silent skip; --skip-engines / YMIR_SKIP_VOICE honored"
  "a2a","the A2A mesh engine — a2abridge (MIT): the local directory daemon (:7777) + the bridge that gives each harness the a2a tools","bin/bridge/a2abridge-ensure.sh ensure --install fetches the pinned engine and raises its directory unit; bin/bridge/a2a-mcp.sh install wires a2abridge + engram into pi + opencode. The unit is the ENGINE's own, Ymir-patched (journal output + the boot hook WantedBy=default.target) with a house template (tools/mill/systemd/a2abridge-directory.service) so a raise seats it by role; the heart's A2A node (:8301) rides the fleet step. Repairable: bin/agents/eir-doctor.sh a2abridge"
  "sessrumnir","the Sessrúmnir desktop GUI (its own repo; lands via the `apps` step at apps/sessrumnir)","bin/desktop/sessrumnir-ensure.sh installs deps + builds on first run (deps are never committed); launch via bin/desktop/sessrumnir-launch.sh"
  "backend","Þjazi — herdr (protocol 14+) or tmux","bin/seat/herdr-ensure.sh detects/tests version, installs via the pinned installer or falls back to tmux"
  "host","this machine — sensed on EVERY host","bin/host/host-sense.sh senses the setup on ANY host (Rule 05); the Omarchy layer then RECORDS it (bin/host/omarchy-sense.sh observe), places the apps (bin/desktop/desktop-place.sh), installs the post-update hook and the wedge-alarm channel, and (on Omarchy) offers the suggested shell plugins — listed, never installed unbidden; seeds the private config/agents.yaml from its example and DERIVES the Eindri dispatch profile from the machine into $YMIR_HOME/hodd/config/eindri-dispatch.json (bin/fleet/dispatch-profile.sh derive — the shipped template with unfilled model tokens is never left to look active; the private override wins over the repo file)"
  "role","what this machine IS — resolved BEFORE the chain, so the whole step set is role-selected","bin/skuld/role-lib.sh establish_roles: --role/$YMIR_ROLE → the fleet registry (bin/skuld/role.sh) → the machine card in hodd/data/machines.md → ask (interactive) → the safe body dev; step_role reports the role + components + live link, records it with bin/skuld/role.sh set, and folds a Machine Card into the ONE registry hodd/data/machines.md (plan 39). An unknown --role is refused (exit 2); --check writes nothing"
  "fleet","the role-gated fleet services: the heart's offices (well-mcp · ratatoskr A2A node · the mill worker · the embedding stone · the cards root · snotra, the meeting ear's MCP face) on heart seats, the stone on forge seats, the well door, the MCP gateway and the a2abridge mesh directory on dev seats","bin/fleet/fleet-ensure.sh copies tools/ and packages/ to the seat (a DIRECTORY row keeps its relative path, so a cross-package import resolves in the deployed copy as in the repo), plus the snotra operator commands — WITH hoard-lib.sh beside them, because each resolves the operator's home through it and a command without its resolver dies on an unbound YMIR_HOME — to ~/.fleet; materializes ONLY what the roles owe (a2abridge-directory is engine-owned: patched by bin/bridge/a2abridge-ensure.sh and materialized from its house template when owed; the arm is seated as the standing unit ymir-syn-watch.service from tools/mill/systemd/), purges stale units, points the seat's pi mcp-adapter.json at THIS body's MCP gateway (bin/bridge/mcp-gateway.sh, :8316, which fronts well/bolthorn/skuld and resolves the heart at request time; --well-url still forces an explicit well door), and carries the model rail the same way — bin/bridge/mcp-config.sh writes the serving box under the config's `ymir` block, read from the ONE resolver bin/model/rail-resolve.sh (plan 51 Part 9c: models come from whichever strong box is CONNECTED), enables the ONE target (ymir.target), raises them, and VERIFIES — a program that cannot rise is a FAILURE with its reason, never a warn"
  "mesh","the A2A mesh (Ratatoskr): the local discovery directory (:7777) + the engine","bin/bridge/a2abridge-ensure.sh installs the a2abridge engine (A2A_NO_IDE=1), patches its user unit (journal output + the boot hook WantedBy=default.target), and raises the directory; the directory is a role-owed program (heart · dev) in the autoboot ONE table, materialized from tools/mill/systemd/a2abridge-directory.service and verified beside the well/tickets/skills doors"
  "autoboot","the boot law: Linger asserted on headless seats, ymir.target enabled once, the boot proof run","checks loginctl show-user $USER -p Linger (enables it headless or fails with the remedy), reports the value on every seat, and calls bin/engine/ymir-autoboot.sh verify — every role-owed program enabled and standing"
  "heimdall","the ssh-key ward (Heimdall) — entry by the rune carried on GitHub","bin/host/heimdall-ensure.sh arms it: ward script to ~/.local/bin (stable path, not the repo tree), the operator's GitHub user recorded, keys fetched/validated/merged into ~/.ssh/authorized_keys, 15-min user timer live (loginctl linger note for headless). --install may add openssh via pacman/apt (sudo, system package). Idempotent; a seat can stand warded or bare — reported honestly"
  "sandbox","utgard-runner:latest image","builds via bin/forge/utgard.sh build on Docker or rootless Podman; distinguishes an unreachable engine from a build failure"
  "memory","engram store + harness MCP registrations","raises the bridge; reports MCP coverage — the store is ONE well in the hoard ($YMIR_HOME/hodd/memory/kaia.engram), resolved via hoard-lib or ENGRAM_DB"
  "record","the RECORD's offices — the engram store, the journal fold receiver, the record crons (heart only)","asserts the store is present and bin/records/journal-receive.sh is executable, and counts the @heart jobs in the cron config; a body SKIPs the whole step with the reason — the record lives on the heart, and a body that ran it would fork the chain (Law 7)"
  "vault","Hnitbjörg — the encrypted document vault: a LUKS2 container (bin/vault/hnitbjorg.sh), sealed by default, opened only with sudo and the operator's passphrase (or a phone key held on the phone over USB/MTP)","bin/vault/hnitbjorg-ensure.sh ensures cryptsetup + the vault dir and NEVER creates a vault — init asks for a passphrase only the operator may type; the home is resolved through bin/vault/hoard-lib.sh (never guessed); repairable via bin/agents/eir-doctor.sh vault"
  "smidja","smidja/smidja_data/smidja.db","bin/desktop/smidja-bootstrap.sh creates it from the tracer schema + a bootstrap session"
  "visualizer","the Smíðja visualizer UI (Vue, served on :8437)","builds ./dist with bun when absent — the API serves the UI from dist, and without it the API answers but shows no interface"
  "loaders","agents/skills into the harnesses","runs bin/seat/valknut-load.sh, then bin/seat/valknut-load.sh --install to seat the post-merge rebind hook. The harnesses load their surfaces from their OWN homes — Pi reads ${HOME}/.pi/agent/extensions/ — so a merged extension fix is invisible until the bind re-runs. The same rebind rides the updater (bin/agents/groa-update.sh) after every pull, and the post-merge hook after every merge: no install and no update leaves the surfaces stale"
  "gates","the git delivery gates — secret-guard (pre-commit), branch-guard + fixes-guard (pre-push)","bin/gates/guards/secret-guard.sh --install seats the pre-commit, bin/gates/guards/fixes-guard.sh --install seats the pre-push (which then runs the tree wards, branch-guard and fixes-guard in one hook), and bin/gates/guards/hoard-guard.sh --install seats the private home's pre-commit — so the gate is live from the first commit of a fresh clone; idempotent"
  "marks","each app's rune icon + .desktop entry into the operator's own desktop, and the Ymir contract into pi's agent home","bin/desktop/design-icon.sh mint --all + install writes to $HOME/.local/share (never a session sandbox), so every app is dockable and pinnable; the contract symlink means every pi session, in ANY folder, loads Brokk"
  "invite","the way in for anyone else — an invite code","bin/engine/ymir-invite.sh ensure mints one only when nothing is live, so the step is idempotent; the code is printed at the end of the run and again in workspace/INSTALL.md"
  "register","workspace/INSTALL.md","writes the record"
  "services","gate API, SPA, Nornir, bridges, visualizer — as USER UNITS on dev seats (hlidskjalf-spa · hlidskjalf-gate · mimir · bifrost · smidja · nornir, all joined to ymir.target)","raised by the fleet step; this step PROVES the raise with bin/engine/ymir-autoboot.sh verify — the old run-scripts/start.sh road is retired for boot (it stays as the manual raise for a window an operator opens)"
  "desktop","Hlidskjalf + Smíðja desktop apps","bin/desktop/desktop-place.sh puts each on its OWN numbered desktop (preferring EMPTY ones); scripts/electron.sh start --both self-heals the Electron binary"
  "validate","the running system","bin/engine/ymir-validate.sh — live port/store/process checks"
```

**34** `step_*` functions are defined (`home` asks, `tree` builds); **28** run as the
visible progress chain. A step is not a row: one step may emit
several. `prereqs` also emits `memory-well`, `host` also emits `agents-config`,
`smidja` also emits `visualizer`, and `spa` also emits `hlidskjalf`. **Every
role-owned step opens with a `role_gate`** (plan 51 P1): a component this
machine's roles do not own becomes a `SKIP` naming the role that does, so the
install never stands up another role's parts. The fleet
step raises every role-owed program (the role gates live in `bin/engine/ymir-autoboot.sh`
— ONE table, shared with `bin/fleet/fleet-ensure.sh`); the `autoboot` step asserts
Linger and runs the boot proof. `--check`
skips the runtime-only steps (`services`, `desktop`, `validate`), which have
nothing to report when the runtime is not raised, so a real run prints those
three in addition. The exact set is whatever the host honestly has — never
assume the count:

```bash
bash bin/engine/ymir-install.sh --check | grep -cE '^  "'   # the honest count, on your host
```

## The Pi binary is the operator's, not Ymir's

`bin/pi/pi-ensure.sh` ensures Ymir's **Pi packages** and nothing more:

```
npm:pi-mcp-adapter   MCP servers (from mcp.json: a2abridge, engram)
npm:pi-web-access    web fetch/search tools
npm:pi-lmstudio      LM Studio / local model bridge
```

The Pi **binary** belongs to the operator, on whatever channel the operator
picked — npm, mise, or something else — and one seat may legitimately differ from
the next. Ymir therefore does not install it, does not choose a channel for it,
and does not edit the operator's `~/.npmrc`, shell rc, or `PATH` to steer it. If
`pi` is absent, `pi-ensure.sh` says so and exits non-zero; it does not resolve it.

The packages go in through `pi install npm:<pkg>`, which writes Pi's own
extension prefix (`~/.pi/agent/npm`). That is why ensuring them needs no npm
configuration, no sudo, and no operator state.

**Why this line is drawn.** The script used to install the binary and preferred
`mise install pi@latest` while its own error string claimed *"need mise or npm"* —
naming a fallback the function never had. It also opened with
`have pi && return 0`, so on a seat that already had any `pi` it did nothing and
reported success. A stale mise Pi therefore reached every seat while the
installer reported healthy. See `docs/fixes/install/`.

`pi-ensure.sh status` still prints the answering version and its **resolved**
origin. That is observation, not judgement: a second Pi on a box is the
operator's to resolve, and seeing two paths side by side is the whole value of
printing it.

## Configuration is never hardcoded (Rule 07)

Every port, host, endpoint, path, and credential is resolved from env/config with
**one documented default** — never a literal in shipped runtime. Ports read
`HLIDSKJALF_PORT` / `HLIDSKJALF_API_PORT` / `SMIDJA_VIZ_API_PORT`, the SPA bind
host reads `HLIDSKJALF_HOST`, and a deployment overrides them in its env file
(Quadlet/Compose), never by patching the core. Law: `RULES/07-config.md`.

## Container engine: Docker **or** rootless Podman

The core never assumes an engine binary. `bin/fleet/ymir-platform.sh` resolves whichever
this host can reach (`YMIR_CONTAINER_ENGINE` forces one) and exposes:

- `ymir_container_engine` / `ymir_container_engine_name` — `docker` or `podman`.
- `ymir_engine_is_podman` — true even when a `docker` binary fronts Podman (the
  podman-docker shim).
- `ymir_volume_suffix` — `:Z` whenever SELinux is enforcing (Docker and Podman
  both need the relabel), else empty.
- `ymir_rootless_podman` — rootless Podman needs `--userns=keep-id` so a bind
  mount lands owned by the invoking user.

`bin/forge/utgard.sh`, `bin/agents/einherjar-spawn.sh`, `bin/agents/valhalla.sh`, `bin/engine/ymir-validate.sh`,
this installer, and `bin/engine/prereq-ensure.sh` all use these; none names an engine
directly. **Quadlet**-managed containers (Podman + systemd) surface as
`systemd --user` units, which the process hall lists. A host-managed deployment
layer (Quadlet, compose, bare) sits **over** this agnostic core — never inside it.

## The visualizer UI

The Smíðja visualizer **API** runs on `:8437` and serves its **UI** from
`apps/visualizer/dist`. A fresh clone has no `dist`, so the API answers but shows
"No ./dist build found" — an install gap. The installer (and `scripts/start.sh`)
now build it when absent:

```bash
(cd apps/smidja-factory/apps/visualizer && bun run build)   # vue-tsc + vite
```

`bin/engine/ymir-validate.sh` reports `visualizer` FAIL when `./dist` is missing **and**
when the build exists but nothing is listening on `:8437`. A PASS means the UI is
built *and* the API is up — so a built-but-dead visualizer (a bad `CMD_DB`, a
crashed API) can no longer read as green.

## Desktop placement (Omarchy desktops, not monitors)

On Omarchy the numbered **desktops** (1 2 3 4 5 …) are the "screens" an operator
switches between. `bin/desktop/desktop-place.sh` gives each Ymir app its **own** desktop,
**preferring an empty one**, so the apps open separated and reachable with
`Super+<n>` rather than stacking on the active desktop.

```
bin/desktop/desktop-place.sh plan            # which desktop each app would take
bin/desktop/desktop-place.sh apply           # write the rules + hyprctl reload
bin/desktop/desktop-place.sh status          # what is installed
```

It writes `~/.config/hypr/ymir-desktops.lua` using Omarchy's own idiom —
`o.window({ class = "^ymir-hlidskjalf$" }, { workspace = "2" })` — and adds one
`require("hypr.ymir-desktops")` line to the user's `hyprland.lua`. It **never**
touches `/usr/share/omarchy/`. Verify with `hyprctl configerrors` (must be empty).
On a non-Omarchy host the step is a clean SKIP.

The class names come from `app_class` (`bin/desktop/app-lib.sh`) — one source. A change
to a class (the 2026-09-24 `ymir-sessrumnir` correction) needs `apply` re-run so
the generated rule is regenerated; a stale rule is caught by
`bin/desktop/desktop-verify.sh --class-only`.

### The install verifies the shelves can open (2026-09-24)

`bin/desktop/desktop-verify.sh` checks every surface — hlidskjalf · smidja · odrerir ·
sessrumnir — and its answer is the install's guarantee:

```bash
bin/desktop/desktop-verify.sh            # resolve + --version + the class invariant
bin/desktop/desktop-verify.sh --live     # with a compositor: a window of the class is held
bin/desktop/desktop-verify.sh --class-only
```

For each surface: (a) the runtime resolver (`bin/desktop/electron-lib.sh`) yields an
executable Electron; (b) it answers `--version`; (c) with a compositor present, a
window of the expected class is held; (d) the class invariant above. It **fails
loudly**, naming the surface and the resolved path — a runtime that is merely
absent is a FAILURE, never a silent SKIP. The desktop step of
`bin/engine/ymir-install.sh` runs it **before** any window is claimed (and again
`--live` after the raise); a broken surface exits the install nonzero.

## The Þjazi backend (herdr-first)

Ymir spawns agents into terminal panes, so a terminal backend must exist. Ymir is
**herdr-first**: `herdr` (Þjazi) is preferred, `tmux` is the accepted reference
backend, and a missing backend is reported — never a silent fallback.

```
backend_priority[3]{rank,backend,note}:
  "1","herdr","preferred; protocol 14+ for panes, 0.8.0+ for presentation spaces"
  "2","tmux","verified reference backend; always acceptable"
  "3","none","spawn is refused with a plain reason"
```

```
bin/seat/herdr-ensure.sh status            # what is present, and does it meet the floor
bin/seat/herdr-ensure.sh ensure --install  # install via the pinned, SHA-verified installer
```

`ensure` installs through `.agents/backend/fm-install-herdr.sh` (exact version +
protocol check), and falls back to reporting `tmux` when herdr cannot be fetched.
Selection order for the running system: `config/backend` → `BROKK_BACKEND` →
`HERDR_ENV=1` → else tmux. Full reference: the `ymir` skill, `assets/thjazi.md`.

## Suggested Omarchy plugins (offered, never forced)

Omarchy's shell is plugin-shaped, and a few registry plugins are Ymir's own organs
rendered on the desktop. `bin/host/omarchy-plugins.sh` suggests them and installs only
what the Allfather accepts.

```
bin/host/omarchy-plugins.sh list        # what Ymir suggests, and why
bin/host/omarchy-plugins.sh installed   # reads omarchy's own plugin list
bin/host/omarchy-plugins.sh suggest     # the offer (no install)
bin/host/omarchy-plugins.sh add <id>    # install one, with consent
```

The core three are Ymir's organs: **Herdr Watch** (Þjazi in the bar), **Hermes
Deck** (our worker runtime), **Skill Manager** (the Galdr family across harnesses).
Installation uses Omarchy's own verb — `omarchy plugin add <repo> --enable` — never
a raw clone.

**These run unsandboxed inside the shell.** The registry "validates listings, not
plugin security", so nothing installs without an explicit yes (`--yes` for
non-interactive callers; without it a non-interactive `add` refuses with exit 3).
The installer only *offers*.

## Consent
A real install prints **the plan it computed** (`bin/bridge/ymir-plan.sh`) and waits for
`[y/N]`. Declining changes nothing (exit 3). `--check` and `--plan` never prompt.
A non-interactive caller without `--yes` is refused rather than silently
proceeding.

The plan names every step with its state and the reason for it — including the
home the operator is asked to choose, the four app surfaces and whether each can
be installed at all, the terminal backend, and what will be skipped and why. The
state vocabulary is `DO · SKIP · INFO · BLOCKED · CONSENT`.

`--check` writes nothing — and that includes the migrations. `bin/engine/ymir-migrate.sh
apply` **moves private data**, so the step chain runs it only on a real run;
a preview leaves the home exactly as it found it. (It used to apply them even
under `--check`, which moved a home during a "report only" pass.)

`--check` writes nothing — and that includes the migrations. `bin/engine/ymir-migrate.sh
apply` **moves private data**, so the step chain runs it only on a real run;
a preview leaves the home exactly as it found it. (It used to apply them even
under `--check`, which moved a home during a "report only" pass.)

## The operator's way in (auth) — `bin/engine/ymir-setup-auth.sh`

A fresh checkout seeds **no credential**, so the gate has no way in until the
operator sets one. `step_auth` (interactive install prompts; `--yes`/non-tty
defers) covers two doors:

```bash
bin/engine/ymir-setup-auth.sh status            # which door (if any) is configured
bin/engine/ymir-setup-auth.sh set [--user U]    # a local password -> HLIDSKJALF_AUTH in .env.local
bin/engine/ymir-setup-auth.sh github            # GitHub sign-in -> GITHUB_CLIENT_ID + GITHUB_CLIENT_SECRET
```

Both write `.env.local` (0600, gitignored); a secret is never printed or put in a
child process's argv. The gate reads `HLIDSKJALF_AUTH` (`user:pass`) and the
GitHub OAuth keys (`/api/auth/github`; sign-in names a login but never grants
access on its own — an account/invite is still required). Restart the gate after
setting a credential. One login is meant to cover every surface — see the shared
session below.

## Letting someone else in (invites)

One operator owns the instance. The installer mints an **invite code**
(`step_invite`) and prints it at the end of the run; share that code and someone
else can create their own account at the gate login screen. Registration is
closed unless a live code exists, so an instance is never accidentally open.

```bash
bin/engine/ymir-invite.sh mint [--limit N]   # a new code (default ceiling 5 accounts)
bin/engine/ymir-invite.sh list               # every code, what is spent, who is in
bin/engine/ymir-invite.sh revoke <CODE>      # take one back, now
bin/engine/ymir-invite.sh where              # where the accounts live on this machine
```

Accounts are stored in `~/.config/ymir/accounts.json` (mode `0600`), machine
state that never enters the repo, with argon2id hashes only. The operator's own
credentials stay `HLIDSKJALF_AUTH` in `.env.local` — invites are for everyone
*else*. Full surface: the galdr `hlidskjalf-ui.md` asset.

## Validation

After the runtime is up, `bin/engine/ymir-validate.sh` observes the result: prerequisites,
the Utgard image, the gate API (`:3889`), the SPA (`:3888`), Bifrost (`:4603`),
Nornir cron, `smidja.db`, the desktop apps, the well (`:4602`), and the audit
ledger. A FAIL means the install is not usable; a WARN means a documented-optional
part is off. `--json` for machine consumption.

### The PR-time real-install gate (2026-09-24, `bin/forge/npm/pr-pretest.sh`)

The Allfather's law: *when PRs are made, do a REAL local npm installation for
testing, so the updates work when they are pushed to npm later.* One wrapper
stands at the PR door: `bin/forge/npm/pr-pretest.sh` packs the exact publish artifact
(what `npm pack` would push), installs it with a genuine `npm install
<tarball>` into a fresh sandbox prefix, and smokes the installed essence (bin
tools, `ymir.js --version`, the hull files, the desktop resolver shape over the
packaged tree — `bin/forge/npm/npm-pretest.sh local`). PASS, open the PR with the proof
line; FAIL, no PR — the pack is mended first (`bin/forge/npm/npm-pretest.sh` names the
wound). `--body` prints the proof block to paste under the PR description,
and the external publish gate (`bin/forge/npm/npm-pretest.sh` full) still runs the remote
seat legs before the shelf ever sails. **Bootability is proven, not assumed**
(2026-09-24): the same leg runs the launcher first-run install in the package
and verifies every surface resolves an executable electron that answers
`--version` plus a built web index — the electrons work and start, or the PR
never opens.

## What the system adopts (engines)

| Engine | Norse shell | Role |
|---|---|---|
| **treehouse** (`kunchenguid/treehouse`) | Yggdrasil | reusable worktree pool |
| **sandcastle** (`mattpocock/sandcastle`) | Utgard | Docker/Podman/Vercel sandboxes |
| **no-mistakes** (`kunchenguid/no-mistakes`) | Mjollnir · Glitnir | clean-PR validation gate |
| **Hermes** (`NousResearch/hermes-agent`, MIT) | — (product name) | worker agent runtime: own brain, memory, skills, subagents, sandbox backends |
| **pi-desktop** (`FaqFirebase/pi-desktop`, Apache-2.0) | **Sessrúmnir** (cloned from its own repo to `apps/sessrumnir` at install) | desktop GUI for the Pi/OMP coding agents — the seat-hall, themed with the Ymir way-of palette |

## Missing dependencies

- **Fixable in user space** (no sudo): `bun`, `uv`, `mcp<2>` — via
  `bin/engine/prereq-ensure.sh`. `treehouse`, `no-mistakes`, **Hermes**, and the **Þjazi
  backend** (herdr, or tmux) are installed by their own ensure/steps.
- **Needs a system package** (reported with the exact command): `git`,
  `python3`, `docker`, `gh`.
- **Optional, honest SKIP:** the `engram` memory engine. The published PyPI
  `engram` is **not** Ymir's engine (it is an unrelated scientific package), so
  the installer reports the well as off rather than installing the wrong thing.
- **Offline:** engine/Hermes/herdr installers fail gracefully and are reported;
  re-run when the network returns.

## Hermes specifically (`bin/engine/hermes-ensure.sh`)

```
hermes-ensure.sh status           # hermes[1]{installed,version,path,method}
hermes-ensure.sh ensure --install # install if absent, then report
hermes-ensure.sh install          # curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
```

A user who lacks Hermes gets it at setup (`hermes` step). Config/identity
(`hermes setup`, auth) stays the user's own; Ymir guarantees only the runtime.

## Heimdall specifically (`bin/host/heimdall-ensure.sh`, `bin/host/heimdall-ssh-keys.sh`)

```
heimdall-ensure.sh status             # heimdall[1]{ward,version,gh_users,keys,timer,linger,sshd}
heimdall-ensure.sh ensure --install   # arm the ward (may add openssh via sudo)
heimdall-ensure.sh install            # = ensure --install
heimdall-ssh-keys.sh status|add|harden|unharden|timer   # the ward's own surface
```

**Heimdall's law: one rune of introduction, all doors.** Every warded seat
fetches `github.com/<user>.keys`, validates every key, merges it into
`~/.ssh/authorized_keys`, and refreshes every 15 minutes on a systemd user
timer. Publish a public key to the operator's GitHub → it opens every warded
computer, Omarchy or Ubuntu. The ward is distro-portable (plain bash + curl +
ssh-keygen; Debian's `ssh` unit and Arch's `sshd` both handled) and is wired
into the install as the `heimdall` step, so a fresh seat is warded at setup.
Hardening (`harden`) disables password logins — a console sudo action, never
taken by an agent, and refused while zero keys are seated (a machine with no
key inside is a machine nobody can enter).

## Sessrúmnir specifically (`bin/desktop/sessrumnir-ensure.sh`, `bin/desktop/sessrumnir-launch.sh`)

```
sessrumnir-ensure.sh status           # sessrumnir[1]{dir,deps,built,electron}
sessrumnir-ensure.sh ensure --install # install deps + build when absent, then report
sessrumnir-ensure.sh install          # npm install + electron-binary heal + npm run build
sessrumnir.sh start [path]            # launch the seat-hall (deps installed on first run)
sessrumnir.sh status | stop
```

Deps are never committed; the ensure step installs them on first run, exactly as
`scripts/electron.sh` does for the other desktop apps. The external engine keeps
its product name `pi-desktop`; the GUI the user sees is Sessrúmnir, themed with
Ymir's deep-navy palette. The Omarchy launcher entry is rendered from
`apps/sessrumnir/resources/ymir-sessrumnir.desktop.in` by `bin/desktop/desktop-place.sh`
(placement + `SUPER+B`).

## Neutral tenant defaults — a fresh Ymir is a distro, not the company

A fresh install ships **no company of its own**. `bin/engine/ymir-install.sh` seeds one
`personal` workspace and an **empty** projects registry (a commented example
only); it never writes a company slug, a company remote, or a `work (company: …)`
line. The runtime resolves the active realm **neutrally** through
`bin/skuld/realm-lib.sh` (`ymir_active_realm`): `data/realm.md` (first line) → the first
non-example tenant under `svartalfaheim/` → `default`. **No script may fall back
to a company slug.** The reference tenant the distro was built for lives at
`svartalfaheim/examples/wayof/` — an example to copy, never the default. A `work`
workspace must name its own company: `workspace-provision.sh` requires
`--company <slug>`.

## Per-workspace provisioning

```
bin/agents/workspace-provision.sh <name> --kind work|personal [--domains a,b,c] [--company <slug>]
```

Creates `workspace/<name>/<domains>/`, registers it in `workspaces.yaml`, and
for a **work** workspace attaches it to the tenant container
`svartalfaheim/<company>/`. `--company` is required for a work workspace — the
company is the operator's to name; Ymir ships no default.

## Verify

```
bin/engine/ymir-install.sh --check          # all steps OK/WARN
bin/engine/ymir-validate.sh                 # the running system actually works
bin/seat/herdr-ensure.sh status           # the Þjazi backend and its protocol floor
bin/host/host-sense.sh                    # sense THIS machine (any host)
bin/host/omarchy-sense.sh status          # the Omarchy recording (Omarchy hosts)
bin/time/saga-session-start.sh            # the session digest
bash .agents/skills/galdr-ymirsystem/scripts/compliance-check.sh
```

On **every** host the installer senses the machine with `bin/host/host-sense.sh`. On
an **Omarchy** host the layer also *records* it (`bin/host/omarchy-sense.sh observe`)
and installs a `post-update` hook so Ymir re-learns it every time Omarchy
updates. On a non-Omarchy host that layer step is a clean SKIP.

Rule: the installer is **idempotent** — running it again changes nothing but
fills gaps. It never overwrites real user data.

## Node dependencies in a fresh clone — the postinstall trap

A clone never carries `node_modules`. Two components need them, and each has its
own package manager:

```bash
# Hlidskjalf (npm + package-lock.json) — what scripts/start.sh runs
cd apps/hlidskjalf && npm install --no-audit --no-fund
npm run typecheck && npm run build          # dist/ is what the SPA serves

# Smiðja visualizer (bun + bun.lock)
cd apps/smidja-factory/apps/visualizer && bun install && bun run build
```

The visualizer's `dist/` is not optional: its API serves the UI from `./dist`,
and without a build it answers the API but prints *"No ./dist build found"*.

### The trap: install scripts can be skipped silently

Newer npm versions gate package install scripts (`allowScripts`). When a script
is not approved the install still reports success, so you get a **half-broken
tree that passes its own build**:

```
2 packages have install scripts not yet covered by allowScripts:
  electron@33.4.11 (postinstall: node install.js)
  esbuild@0.25.12  (postinstall: node install.js)
```

- `esbuild` survives it (its binary arrives through the platform-specific
  package), so `npm run build` succeeds and everything looks healthy.
- **`electron` does not.** Its postinstall downloads the ~100 MB runtime; without
  it `node_modules/electron/dist/` is left partial and `path.txt` is never
  written, so the desktop shell cannot start — while the web app builds perfectly.

**Where the runtime actually lands, and the one resolver (2026-09-24).** The
root `package.json` declares a workspace (`apps/*`), so npm **HOISTS** each app's
electron to the ymir ROOT — `ymir/node_modules/electron` — and **never** creates
`apps/<app>/node_modules/electron`. A probe that looks only app-locally finds
nothing that can exist (this is what made the shells fail silently). Three rules
follow, all owned by `bin/desktop/electron-lib.sh`:

- **the resolver** — `electron_bin`/`electron_pkg_dir` search, in order: the
  app-local dir, the nearest ancestor hoist (walking up, halting at a foreign
  ymir root), then the sibling package. `electron_runtime_state` answers
  `ok` | `partial` | `absent`; **absence is never success** — every guard returns
  failure when nothing resolves (proven by `.agents/tests/electron-lib.test.sh`).
- **install at the workspace root** — an install INSIDE a member reconciles the
  tree and REMOVES the local `node_modules` the launcher was about to use
  (`electron_is_workspace_member`). Install at the root for a member, app-local
  only for a standalone app.
- **fetch into the resolved dir** — `electron_place_dir` returns the seat a fetch
  must use (the root hoist for a member). `electron_fetch_runtime`/
  `fetch_electron_zip` place the runtime there.

Detect it:

```bash
npm install-scripts ls                                        # what is unapproved
node_modules/electron/dist/electron --version                  # fails if skipped
cat node_modules/electron/path.txt                             # absent if skipped
```

Fix it:

```bash
npm install-scripts approve electron esbuild
npm rebuild electron
```

If the rebuild still exits **silently** and `dist/` stays partial, the download
is cached but was not re-extracted — complete it by hand, which is all the
package's own installer does:

```bash
ZIP=$(ls ~/.cache/electron/*/electron-v*-linux-x64.zip | head -1)
rm -rf node_modules/electron/dist && mkdir -p node_modules/electron/dist
unzip -q -o "$ZIP" -d node_modules/electron/dist
printf 'electron' > node_modules/electron/path.txt     # the linux binary name
chmod +x node_modules/electron/dist/electron
```

**Verify the install as a whole**, not just that a build passed: the electron and
esbuild binaries report versions, both `dist/` directories exist, and
`bin/engine/ymir-install.sh --check` reports the visualizer and smidja green.

## Platform support — Linux, macOS, Windows

Ymir runs on Linux (native), macOS (native) and Windows (through **WSL2**, with
MSYS/Git Bash as best-effort). The runtime is bash, so Windows means a POSIX
shell: WSL2 is the supported path, and it is also the only one where the Linux
GPU and service paths behave normally.

### One place knows the difference

`bin/fleet/ymir-platform.sh` is the portability layer. It defines functions only and is
sourced, never executed:

```bash
. "$ROOT/bin/fleet/ymir-platform.sh"     # scripts already do this via the shim block
```

| Need | Function | Why it exists |
|---|---|---|
| Which OS | `ymir_os` → `linux` \| `macos` \| `wsl` \| `msys` | branching, once |
| CPU count | `ymir_nproc` | `nproc` is GNU; macOS uses `sysctl -n hw.ncpu` |
| Resolve a path | `ymir_readlink_f` | BSD `readlink` has no `-f`; mirrors GNU semantics including the "parent must exist" rule |
| File facts | `ymir_stat_mtime`, `ymir_stat_size`, `ymir_stat_id`, `ymir_stat_birth`, `ymir_stat_mode` | GNU `stat -c` vs BSD `stat -f`, and birth time exists on both but differently |
| Timing | `ymir_epoch_ns` | BSD `date` has no `%N` |
| A pid's command line | `ymir_pid_cmdline`, `ymir_pid_matches` | `/proc` is Linux-only; falls back to `ps -o command=` |
| Signal a process by pattern | `ymir_kill_matching` | `pkill` is absent on some MSYS/WSL images; falls back to `ps` + `kill` |
| Detach a process | `ymir_detach` | `setsid` is absent on macOS; falls back to `nohup` |
| Exclusive lock | `ymir_lock` | `flock` is Linux; falls back to an atomic `mkdir` lock |
| Services | `ymir_service_backend`, `ymir_service_active` | `systemd` on Linux, `launchd` on macOS, neither elsewhere |
| GPUs | `ymir_gpu_name`, `ymir_gpu_mem_used` | never assume NVIDIA: `nvidia-smi`, then `rocm-smi`, then Apple's unified memory |
| Paths | `ymir_tmp`, `ymir_expand_tilde` | `TMPDIR`/`TEMP` vary; a leading `~` must be expanded explicitly |

Scripts that need any of these carry a short shim block near the top that finds
and sources the library, then marks it loaded so a second source is a no-op:

```bash
if [ -z "${YMIR_PLATFORM_LOADED:-}" ]; then
  _ymir_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  for _ymir_c in "$_ymir_dir/ymir-platform.sh" "$(dirname "$_ymir_dir")/bin/fleet/ymir-platform.sh"; do
    [ -r "$_ymir_c" ] && { . "$_ymir_c"; YMIR_PLATFORM_LOADED=1; break; }
  done
  unset _ymir_dir _ymir_c
fi
```

### Rules for new code

1. **Never call `readlink -f`, `stat -c`, `nproc`, `setsid`, `flock`, `date +%N`
   or read `/proc` directly.** Use the shim.
2. **Never assume NVIDIA.** Ask the shim; a machine may be AMD, Intel or Apple.
3. **Never hardcode a home directory.** Use `$HOME`, or `ymir_expand_tilde` for a
   user-supplied path, and keep machine-specific values in generated config
   rather than in the tree.
4. **Never assume a desktop.** `.desktop` files, `systemctl` and window managers
   are Linux-shaped; a launcher must be generated for the host, not shipped as
   one file for all.
5. **Test the fallback, not just the happy path.** Most of these functions exist
   because the Linux path already worked; the risk is the other branch.

Standalone tools that ship outside a Ymir checkout (for example
`.agents/skills/galdr-ymirsystem/scripts/bench-one.sh`) carry their own small portable
helpers instead of sourcing the library, so they run anywhere on their own.

### Machine config is rendered, never shipped

Two files must contain **absolute** paths (the engram MCP server's binary and its
database), so a tracked copy would hand every operator the previous one's home —
exactly what `/home/<user>/...` did in this tree. They follow the `.env.example`
pattern instead:

| Shipped (tracked) | Rendered (gitignored) |
|---|---|
| `opencode.json.example` | `opencode.json` |
| `.pi/mcp-adapter.json.example` | `.pi/mcp-adapter.json` |

Placeholders `__YMIR_HOME__` and `__YMIR_ROOT__` are substituted with `$HOME` and
the checkout root by `bin/seat/valknut-load.sh` (its `render_config`, run for both
`--pi` and `--opencode`). It is idempotent: identical content is left alone and
reported as `unchanged`.

Rule: **if a config must hold an absolute path, it is generated from an
`.example`, not committed.** The same applies to launchers — a `.desktop` file
is one OS's answer and must be produced for the host, not shipped for all.

## Omarchy-first: the core is portable, the desktop is Omarchy's

Ymir is an **Omarchy-first** system. That is a design statement, not a
restriction — it says which desktop integration is first-class, not which
machines may run the runtime.

**Two layers, deliberately separate:**

| Layer | Runs on | What it owns |
|---|---|---|
| **Portable core** | Linux, macOS, Windows (WSL2; MSYS best-effort) | the runtime — session digest, lock, watch, cron, skills — the installer's user-space prerequisites, the capability shim, generated machine config |
| **Omarchy layer** | Omarchy only | recording the host (`omarchy-sense observe`), placing each app on its own numbered Hyprland desktop (`desktop-place`), the launcher entries (`.desktop`), the suggested shell plugins, the post-update hook |

The core never grows a Hyprland branch, and the Omarchy layer is never stretched
into pretending it is portable. An Omarchy-specific step is gated on the host and
reports a clean skip anywhere else:

```bash
[ -d /usr/share/omarchy ] && ... || add host OK "... (not an Omarchy host)"
```

That is why the only Omarchy branches left in the core installer are the ones
that call the layer (`step_omarchy`) and desktop placement (`step_desktop`):
`step_host` senses the host portably with `host-sense`, and everywhere else the
same code path runs on any host.

The **consent preamble** the installer prints before it acts says the same thing —
*"learn this machine (OS, desktop, packages, configs, monitors, scale — Omarchy
hosts recorded first-class)"* — so the operator is told what will happen in the
portable terms the code now uses, not the Omarchy-only terms it used before.

### The machine's role — the install's component set (plan 51, P1)

**Role is resolved before the first step runs.** `bin/engine/ymir-install.sh` calls
`establish_roles` (`bin/skuld/role-lib.sh`) right after consent and **before** the step
chain, because the role is what selects the components the chain installs.

```
role_resolution[4]{source,when}:
  "--role <r> | $YMIR_ROLE","the operator names it for this run — the strongest statement; an unknown name is REFUSED (exit 2), never guessed"
  "the fleet registry","$YMIR_HOME/hodd/data/fleet.json, read by hostname (bin/skuld/role.sh)"
  "the machine card","the host's own row in $YMIR_HOME/hodd/data/machines.md — a role token in that row"
  "ask -> the safe body","a host in none of them is ASKED on a real interactive run; a run that cannot ask (--check, --yes, no tty) takes the documented safe body `dev` (owns no record, runs no record job) and says so — never the union of every role's parts"
```

Every role-owned step opens with a `role_gate` and, when this machine holds none
of the roles that own the component, emits a `SKIP` that names why:

```text
"record","SKIP","not this machine's role (heart only) — the record (fold · store · record crons) lives on the heart"
"omarchy","SKIP","not this machine's role (dev only) — the dev desktop layer"
"local-model","SKIP","not this machine's role (forge,dev only) — the model rail"
```

The components each role owes (the ONE table, `bin/skuld/role-lib.sh` `components_for`):

```
role_components[4]{role,components}:
  "heart","core · record · well · web · mesh — the record services, NO dev desktop layer and NO rail"
  "forge","core · rail · harness · sandbox — the rail, NO desktop and NO record"
  "dev","core · harness · rail · desktop · web · mesh · well · sandbox — a FULL body; it runs no heart office"
  "hand","core only — nothing persistent"
```

`step_role` then **records** what was resolved: `bin/skuld/role.sh set` writes the fleet
registry, and `machine_card_write` folds this machine into the ONE registry,
`hodd/data/machines.md` (plan 39's fold — no parallel card). The card is keyed by
a deterministic heading (`## Machine card — <host> (role: <roles>)`), so a repeat
install writes nothing and a role change APPENDS a new card — the registry's
history is never rewritten (Rule 06).

```bash
bin/engine/ymir-install.sh --check                 # this host's role + component set, no writes
bin/engine/ymir-install.sh --check --role heart    # read AS a heart: the dev desktop layer and the rail SKIP
bin/engine/ymir-install.sh --role forge            # declare it for the run (and record it)
bin/skuld/role.sh set <host> heart,forge          # change it afterwards
```

**Rule 05 holds:** the role layer is **host-neutral** — it selects components,
never platform behaviour — while the Omarchy/macOS/Windows layers stay gated on
the host. A host with no declared role is never silently given every part: it is
asked (interactively), or given the safe body and told. The roles and what each
owns are in `README.md` (*"The Fleet — many machines, one record"*) and Plan 51.

### The boot follows the same lines

The boot obeys the role too: **what a seat owes at boot is its roles'
programs** — the heart's offices, the forge's stone, a dev body's own web stack.
`bin/engine/ymir-autoboot.sh status` prints the per-role truth, and
`bin/engine/ymir-autoboot.sh verify` is the boot proof the install's final step runs.

### The dispatch profile is derived, never left as a template (D4)

`step_host` also runs `bin/fleet/dispatch-profile.sh derive` into
`$YMIR_HOME/hodd/config/eindri-dispatch.json` (once — a private override that
wins over the repo file thereafter). The derivation reads `config/agents.yaml`
plus the live pi catalog, so the rules carry the machine's real harness/model;
a template still holding unfilled model tokens is NOT active and steers
nothing (`bin/fleet/dispatch-profile.sh active` decides — see `eindri-orchestration.md` §5.1).

### The agents are declared, not scripted (plan 58 Phase 4)

WHO a figure is lives in the tree; WHAT MODEL it runs is the operator's. The two
halves have separate homes, and neither leaks into the other:

```
declared_agents[4]{what,where,read_by}:
  "the figure (prose + frontmatter)",".agents/agents/<figure>.md","the harnesses (symlinked), the roster"
  "the wiring (role → figure → tools)",".agents/roles.yaml","bin/agents/eindri-role.sh · bin/fleet/agents-config.sh roster"
  "the model (per figure)","$YMIR_HOME/config/agents.yaml (+ per-host overlay)","bin/fleet/agents-config.sh get <figure> model"
  "the resolved roster","bin/fleet/agents-config.sh roster","dispatch doors, reads only"
```

- **No model is pinned in the tree.** A figure card carries `role`,
  `norse_name`, `descriptor`, `capabilities`, `skills`, `ymir_tools` and
  `workspace_patterns` — never a `model:`. The model is resolved from the hoard
  **by figure name** at dispatch (`bin/fleet/agents-config.sh get <figure> model`),
  so one public tree runs on any hardware (Rule 04; plan 56).
- **`roles.yaml` is the decision table in data.** `bin/agents/eindri-role.sh` reads it
  — it declares no role in code — and `bin/fleet/agents-config.sh roster` joins it to
  the hoard, emitting `role → figure → harness → model → tools`. Two hoard
  YAMLs yield two rosters; the tracked tree never moves.
- **Apply writes nothing canonical.** `bin/fleet/agents-config.sh apply` publishes
  local providers and per-agent models into the *harness's own* config
  (`opencode.json`, untracked) and caches the resolution in state; it never
  rewrites `.agents/agents/*.md`. The roster is resolved, not stamped into the
  tree, and `bin/seat/valknut-load.sh` still binds every card by symlink.

```bash
bin/agents/eindri-role.sh list                 # the dispatch roles and their crafts
bin/agents/eindri-role.sh choose "<task>"      # the smith whose craft fits
bin/fleet/agents-config.sh roster             # role → figure → harness → model → tools
bin/fleet/agents-config.sh get sindri model   # one figure's model, from the hoard
```

### What the Omarchy layer installs

```bash
bin/host/omarchy-sense.sh observe          # learn packages, configs, Omarchy version
bin/host/omarchy-plugins.sh add            # the suggested shell plugins (never forced)
bin/host/omarchy-hook-install.sh install   # re-learn after every `omarchy update`
bin/desktop/desktop-place.sh apply            # Hyprland desktops + launcher entries
```

`desktop-place.sh apply` does both halves of the desktop integration: it writes
the Hyprland window rules that give each Ymir app its own numbered desktop, and
it renders the launcher templates into `~/.local/share/applications/`. The
templates (`apps/hlidskjalf/electron/*.desktop.in`) carry `__YMIR_ROOT__` rather
than an absolute path, because where the checkout lives is a fact about the
machine, not about Ymir.

**Rule:** `RULES/05-platforms.md` — a core change updates every
platform layer in the same change.

**Rule for a new desktop feature:** if it is Omarchy-specific, it belongs in the
Omarchy layer and is gated; if it is core, it must work on every platform. Do not
blur the two — a branch of Hyprland logic inside a core script is how a portable
runtime stops being portable.

### A move must carry the memory, not just the code

Rule 06 makes this explicit, because a home swap here dropped
`docs/append-only-log.md`, `docs/masterplan.md`, `docs/plans/` and the private
business set: the backup carried `state`, `.env.local`, `data`, the realm and
`workspace` — but not `docs/` or `assets/`. The code arrived; the memory did not.

Before and after any migration, re-clone or swap, check the sets **by name**:

```bash
for f in docs/fixes docs/append-only-log.md workspace/memory/runes_audit.md; do
  [ -e "$f" ] || echo "MISSING append-only artifact: $f"
done
ls "$YMIR_HOARD/docs" "$YMIR_HOARD/identity" 2>/dev/null    # the private set
```

A backup is only as good as its file list. If a directory is not named in the
backup, it is not carried.

### The memory engine is provisioned, not hinted (2026-09-12)

`bin/engine/ymir-install.sh` used to *check* for the well engine and, failing, print
`SKIP "optional — install engine then run bin/bridge/mimir-bridge.sh"`. A SKIP never
blocks, so the well was silently down on every install — and the hint named the
wrong package, so following it made things worse.

Now the installer provisions it: `bin/engine/prereq-ensure.sh engram` installs
**`engdbram`** (the distribution; the *module* is `engram`) into an interpreter
that can run it (>=3.11; uv supplies 3.12 when the distro's Python is unsuitable),
and records that interpreter in `~/.config/ymir/engram-python`. `bin/bridge/mimir-bridge.sh`
reads the same file, so the installer and the bridge always agree.

```bash
bin/engine/prereq-ensure.sh engram        # install and record the interpreter
bin/bridge/mimir-bridge.sh --start        # the :4602 face over the engine
curl -s 127.0.0.1:4602/health      # {"status": "up", "store": ".agents/memory/kaia.engram"}
```

**Never `pip install engram`.** PyPI's `engram` is an unrelated rendering library
(mitsuba/drjit/torch) whose install pulls gigabytes of CUDA wheels and still
leaves Ymir with no engine. The prerequisite target exists so nobody has to know
that: `bin/engine/prereq-ensure.sh engram`.

### The rename sweep broke governed paths, not just prose (2026-09-12)

The `smidja` → `smidja-factory` rename left `smidja-factory-factory` behind in
**seven** places — `scripts/start.sh` (`VIZ_DIR`), `bin/engine/ymir-validate.sh`,
`bin/engine/ymir-install.sh` (twice: the dist probe and the build dir),
`bin/time/saga-session-start.sh` (the governed-path TOON row), `AGENTS.md` (the
`governed[]` table, twice) and the guard's own `asset_for` pattern.

The damage was not cosmetic: a governed path that does not exist makes the
pretool guard stop matching, so the smidja rule protected nothing while every
check still passed. A `governed` check now exists in
`compliance-check.sh` for exactly this class (see `runtime-compliance.md` §G13);
it reports `all 25 governed paths exist`.

`bin/engine/ymir-install.sh` and `bin/engine/ymir-validate.sh` are the two files of this asset
that the sweep corrected. The visualizer path is
`apps/smidja-factory/apps/visualizer` (the smidja repo clone) — **not** the
skill tree (dropped 2026-09-17, the skill carries no copy), not a doubled
`smidja-factory-factory`, and not the abandoned `.agents/skills/smidja/` tree
(stale build output, moved aside).


## Planned — the fleet room (Gladsheim), and how it will be seated here

**Status: planned, not yet shipped (2026-10-12).** The room's engine is **proven** — a
continuwuity homeserver was raised by hand on one seat and a message was posted and read
back — but **no step installs it yet**, so a user who installs Ymir today gets **no room**.

When it lands, it takes its place in **this** document's pattern, as one more step and one
more role:

```
install   a step_room in bin/engine/ymir-install.sh, beside the other service steps
update    a migration .agents/migrations/0008-room — heals an old home forward
boot      a repo-owned unit + a fleet-ensure role (Rule 10 — never hand-placed)
heal      an *-ensure.sh surface composed by bin/agents/eir-doctor.sh
```

**Role-aware, because a fleet is not one machine.** The engine role runs **once, on the
heart**; every other seat runs the **client** role and speaks to the heart. A seat must
never raise a second homeserver. Token provisioning is **pinned, not scraped**: the
bootstrap registration token is written to the hoard *before* first boot (the live proof
showed the token changes across restarts, so reading it from a log races the server).

**The prerequisite is a word, not a step:** a Matrix `server_name` is **permanent** and is
what peers resolve to federate, so a fleet must choose a **stable name with DNS + TLS** —
never a tailnet IP, never a placeholder. That choice is the Allfather's, and it comes
before the first line of this step.

### The two shapes, and the install must know which it is in

**A single machine and a fleet are not the same install**, and the step must act
accordingly — never assume, always detect (the fleet already knows its role: `step_role`,
`config/agents.yaml`, `bin/fleet/topology.sh`).

```
shapes[3]{shape,how Ymir knows,what the install/update seats}
  "single machine","no fleet declared / one seat","engine + client on THIS machine"
  "fleet — the heart","this seat carries the heart role","the engine role, ONCE, here"
  "fleet — a seat","this seat is a body, not the heart","the CLIENT role only — never a second homeserver"
```

**The law that follows:** *the engine runs once per operator install.* On a single machine
that means here; in a fleet it means **the heart**, and every other seat is a **client**.
The **update** carries the same logic — the migration must be **role-aware**, so a seat
running it seats a client (or skips cleanly) and never raises a server the heart already
owns.

**Token provisioning follows the same split:** on a single machine the token is minted and
read locally; in a fleet the heart **mints once** and the **one hoard** carries it to every
seat (plan 37), so a new seat is a new *identity*, not a copied credential.

**See:** plan 75 (`Part 9` shipping law · `Part 10` identity & provisioning · `Part 11`
the fleet shape) · plan 73 (Gladsheim) · tickets ymir/55, ymir/57.

**One resolver, never a private check.** The answer to "which shape am I?" already ships:
**`bin/fleet/topology.sh`** reports `shape` (`single` | `fleet`), `roles`, `heart`, and
`link` (`standalone` | `attached` | `detached` | `offline`) from ONE registry, and degrades
cleanly to `single`/`standalone` on a box with no registry. Every shape‑dependent step —
this one included — **asks it**, and none re‑derives the shape by hand (plan 76, the shape
law; Rule 07's reason applied to topology).


## Codex receives the house tools on setup and update

`step_codex_plugin` runs `node bin/seat/codex-plugin-install.mjs` on a host with
Codex. Its computed-plan row is `codex-plugin`; `--check` proves the installed
source, enabled registration and cache instead of merely checking that a source
file exists. Missing Node or unsupported Codex plugin commands fail the step.

The same helper is called after every normal Gróa update and returns failure to
the updater if refresh or verification fails. It uses Codex's own local marketplace
and plugin commands, retains unrelated Codex config, and preserves an explicit
operator disable. Generated plugin paths live in `CODEX_HOME`, never in the public
Ymir source tree. See `harness-integration/codex.md` for layout and verification.

The npm package already includes `.agents/` and `bin/`, so clone installs and npm
installs receive the same Codex plugin source and deployment helper. Linux and
macOS use the same Node helper; Windows follows the existing WSL runtime layer.
A successful local CLI test does not establish that the entire Windows/WSL fleet
runtime is installed or working; its shell and service checks remain required.

## 2026-11-04 — the install seats the ARM, and the seat render writes only on change

Appended. Two changes to the install chain, both about the same fault: a capability that is committed
and correct but never seated by the install is a capability the machine does not have (plan 66 §7).

**`step_loaders` now arms the session side.** After `valknut-load.sh --all` (which seats the packets,
the skills and the extensions on Pi, OpenCode and Hermes), the install runs
`bin/pi/arm.sh hook hermes --install`: a stable shim at `~/.hermes/agent-hooks/`, two `hooks:` entries
(`on_session_start`, `pre_llm_call`) in `~/.hermes/config.yaml`, and the `(event, command)` consent
pairs in `~/.hermes/shell-hooks-allowlist.json`. The hook runs the Sága digest at session start and
returns it as context on the session's first turn — the session side of the Gná arm for a harness that
has no extension API. A host without Hermes is `SKIP "no Hermes on this host — no session hook to
seat"`, never a silent pass (RULES/25), and a hook that cannot be seated is a `WARN` naming the door.

```
install_arm[4]{step,what,skip,note}
  "step_loaders","bin/pi/arm.sh hook hermes --install","no hermes on this host","the arm's session side; the watch LOOP is the ymir-syn-watch unit and is untouched"
  "bin/agents/groa-update.sh","re-seats the same hook on every update","no hermes on this host","an update that moves the code under a hook's feet must re-point it — the shim resolves the house at run time, so it survives a worktree"
  "--check","writes nothing","-","a dry run that writes is not a dry run: the arm block sits in the APPLY path only"
  "honest limit","Codex/Cursor have no session hook surface","-","named as unarmable by the door itself; never faked"
```

**The seat render is idempotent by CONTENT.** `bin/seat/seat-surface.sh` writes `~/.hermes/SOUL.md`'s
marked block and the repo's `.hermes.md` only when the bytes differ, so the install's identity step
(`step_identity` → `seat-surface.sh`) and every Gróa run can repeat without churn — and "the renderer
delivered the seat" becomes provable by running it twice and watching the second run print
*already current (nothing written)*. The SOUL block's **door list is read from
`bin/mcp/ymir-mcp.py --selftest`**, not restated in the template: one list, so a seat file cannot name
fifteen doors while the packet registers thirty. `bin/gates/tests/test_hermes_seat.sh` compares the two
sets on every run.

Both facts are asserted, not asserted-about: `install` and `groa-update` are the two doors that deliver
the seat, the packet and `.hermes.md`, and the test renders from the tree it stands in — so a second
checkout re-rendering the machine's SOUL.md from older code shows up as a red row, not as a mystery.
