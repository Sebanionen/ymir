## agents · unversioned · 2026-11-04 — the skills door: three tools and a redactor

### Why

Plan 184 exists because of one arithmetic fact and one risk. The arithmetic: a skill read into
context costs 2–20 K tokens, and the library is 196 of them, so nothing can be loaded whole —
and an MCP that exposes one tool per skill would repeat the same bloat in tool schemas instead
of prose. The risk is the Allfather's own sentence: *"we also need to make sure we're not
putting our data out in the MCP — like in the model testing skill we have a lot of personal
testings and info."* A folder of skills copied to a collaborator carries hostnames, user paths,
bench runs and people; nothing in the house would have refused it.

Two structural faults stood in the way, both named in the plan's §7: a skill's **visibility was
implied by the directory it happened to sit in** (so "do not share" meant "move it"), and the
**index was hand-kept and could lie** (a skill with no `description:` was unfindable; a skill
inside an app was never listed at all).

### Now

Four pieces, each a command whose output is recorded:

- **`bin/skills/manifest.sh`** — `validate · scan · index · --migrate`. One directory = one
  skill = one `skill.yaml`. A directory without a manifest FAILS BY NAME, a manifest without a
  `SKILL.md` fails too, `description` is required and must be exactly one line (it is what
  `skills_search` returns), a duplicate name is an ERROR naming both paths, and an override is
  DECLARED (`shadows:` + `shadows_reason:`) rather than won by shelf order. `index` writes
  `index.yaml` from manifests only; `--migrate` writes only `skill.yaml` files, so the migration
  is reviewable as a diff and nothing is moved or renamed in the same pass.
- **`bin/skills/share-build.sh`** — reads `share.yaml` (name · reason · form) and writes
  `published/<skill>/` with a redacted `SKILL.md`, its `templates/` and `assets/`, and a
  `manifest.json` carrying `name · version · sha256 · source_rev · redactions[]`. The three
  forms matter: `skill` ships the whole craft, `method-only` cuts the RESULTS sections (the
  doctrine survives, the runs do not), `templates-only` ships the shapes and a stub body. The
  build refuses a `visibility: private` skill, and it runs the ward on its own output.
- **`bin/gates/guards/skills-share-guard.sh`** — the last word is a refusal, not a review:
  machine paths, any IPv4 literal, LAN/tailnet hosts, ports, a name from the house's registries
  (or an explicitly seeded one), a mailbox, a phone, a bench/test-run table, and our catalog's
  model ids. **The redactor rewrites what it can NAME; the ward refuses what it could only
  suspect** — so an unknown host is a build failure, never a leak.
- **`tools/skills-mcp/skills-mcp.py`** — three tools and one file fetcher: `skills_search`
  (names + one-line description + token estimate, never bodies), `skills_get` (front matter
  always, body only with `full=true`), `skills_templates` (template names by tag), and
  `skills_file` (one named file, path-confined — `..`, absolute paths and symlinks out of the
  tree are refused). No write path, no shell, no network call; it reads `published/` and
  nothing else.
- **`tools/skills-mcp/systemd/skills-mcp.service`** — the P3b packaging: a USER unit for the
  heart, loopback only, reading the published tree the heart pulls, with the MCP health probe
  written into the comments so the heart's operator does not have to invent one.

### Verified

- `bin/gates/tests/test_skills_mcp.sh` → **27 checks, 0 failures**, covering: a manifest-less
  directory fails by name; a duplicate name is refused naming both paths; a missing description
  and a wrapped description are both refused; a declared override is legal; `share-build --check`
  is clean on the fixture set and **non-zero on the seeded canary**; the ward catches the canary
  in all eight classes; `skills_search` returns one line per hit with no body; `skills_get
  full=false` withholds the body; `skills_file ../../etc/passwd` is refused.
- `python3 tools/skills-mcp/skills-mcp.py --selftest` → `"tools","4","skills_search,
  skills_get, skills_templates, skills_file"` and the published root resolved.
- `python3 tools/skills-mcp/skills-mcp.py --schema-tokens` → **305 tokens** of 400 (`"4","1217","305"`).
- `bin/gates/guards/skills-share-guard.sh --root <fixtures> --quiet` → `0 finding(s)`;
  the same ward over the seeded canary → `8 finding(s)` (machine path, address, port,
  mailbox, phone, bench table, model id, name).
- `bin/gates/checks/unit-template-check.sh --quiet` → passes; 27 templates verified, and the
  check was proved to bite by adding a bogus key to this unit and watching it FAIL.

### Files

- `bin/skills/manifest.sh` (new)
- `bin/skills/share-build.sh` (new)
- `bin/gates/guards/skills-share-guard.sh` (new)
- `bin/gates/guards.sh` (the new ward joins the ONE list)
- `bin/gates/tests/test_skills_mcp.sh` (new)
- `bin/gates/tests/fixtures/skills-mcp/` (new: three invented skills + their share list)
- `tools/skills-mcp/skills-mcp.py` (new)
- `tools/skills-mcp/systemd/skills-mcp.service` (new)
- `bin/gates/checks/unit-template-check.sh` (renders the new template)
- `docs/features/skills-mcp-for-collaborators.md` (new)
- `docs/features/_catalogue/entries/` (the catalogue row)
