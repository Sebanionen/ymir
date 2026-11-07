# Skills for collaborators — the skills MCP

**What it is.** A small door onto our skills: a collaborator's agent can *search* the skills we
have chosen to share, pull **one** of them when it is needed, and fetch the templates that make
it useful — without loading 196 skills, and without ever seeing our machines, our people, our
recordings or our model catalog.

It is deliberately tiny. The whole catalogue is four tool descriptions (about 300 tokens), not
196 entries, so a collaborator pays for a skill only at the moment they ask for one.

## What you need

- A Ymir home (`<home>`), because the door serves a **built copy** of the skills, not the live
  library. The built copy is `<home>/hodd/skills-share/published/`.
- Python with the MCP SDK: `python3 -m pip install --user mcp`.
- For a collaborator: an MCP client (Claude, Codex, Pi, Cursor — anything that speaks MCP) and
  a grant at Gimlé. The skills door is one door in Gimlé's hall; there is no separate URL or
  second password to remember.

## The commands

**Build the copy that may leave** — one `share.yaml` names each skill, why it may leave, and in
what form (`skill`, `method-only` or `templates-only`):

```sh
bin/skills/share-build.sh            # build published/ from share.yaml
bin/skills/share-build.sh --check    # build into a scratch tree; refuse on drift or on a finding
```

The build redacts what it can name — user paths, LAN and tailnet hosts, ports, our people, chat
ids, catalog model ids — and then a ward reads its own output and refuses anything private that
survived. A build that fails publishes nothing.

**Judge the skills themselves:**

```sh
bin/skills/manifest.sh scan                 # every shelf: which skills declare themselves
bin/skills/manifest.sh index                # write the index from the declarations
bin/skills/manifest.sh --migrate            # write a skill.yaml from existing front matter
bin/gates/guards/skills-share-guard.sh      # the ward, over published/
```

**Run the door:**

```sh
python3 tools/skills-mcp/skills-mcp.py --selftest        # what it holds, and where it reads
python3 tools/skills-mcp/skills-mcp.py --schema-tokens   # the load cost, in tokens
python3 tools/skills-mcp/skills-mcp.py                   # stdio, for a harness that spawns it
```

On the heart it runs as a user unit —
`tools/skills-mcp/systemd/skills-mcp.service` — bound to `127.0.0.1` and reached through
Gimlé's gate.

## What a collaborator's agent can do

- `skills_search("plan")` — one line per hit: name, one-line description, token estimate.
- `skills_get("word-weaving")` — that skill's front matter only; `full=true` adds the body.
- `skills_templates("plan")` — the template names, then `skills_file("word-weaving/templates/plan.md")`
  fetches exactly that file.

There is **no write** in the door. It cannot edit a skill, add one, run a command or fetch
anything from the network — it reads the published copy and nothing else.

## Limits

- **The door's availability is Gimlé's availability.** The skills door is part of Gimlé's hall,
  so if Gimlé is down the skills are down. That is the price of one surface instead of a second
  password to keep track of, and it is said here rather than discovered in a meeting.
- **Only what is declared leaves.** A skill that is not in `share.yaml` is not published, and a
  skill marked `visibility: private` cannot be added to `share.yaml` — the build refuses it.
- **Redaction is a copy, not a filter.** What leaves is built from the declared set and hashed;
  the live library is never served by symlink, and a collaborator's call never reaches back into
  the home.
- **A grant is per person and revocable.** Access is recorded at Gimlé by name; revoking is one
  entry, and the next call fails.
- **`method-only` cuts sections, by heading.** A results section titled something the build does
  not recognise still travels — which is why the ward reads the output too.

## If it does not answer

- `skills_search` says "no published skills at …" — the build has not run on this machine.
  Run `bin/skills/share-build.sh` and check that `published/` exists.
- `skills_get` names the skill but the body is withheld — that is the design: ask with
  `full=true`.
- The build refuses with *"the ward refused the built tree"* — something in the skill is private
  and the redactor could not rewrite it. Reword the skill, or teach
  `bin/skills/share-build.sh` to redact that shape and say why.
- A collaborator gets a connection failure — check that Gimlé is up, then the unit:
  `systemctl --user status skills-mcp.service`. The health probe is written in the unit's
  comments.
