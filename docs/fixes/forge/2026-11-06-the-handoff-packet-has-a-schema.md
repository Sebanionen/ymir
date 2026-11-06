## forge · unversioned · 2026-11-06 — the handoff packet has a schema, and an example beside it

### Why

Plan 203 makes the **handoff packet** the one artefact that crosses the boundary between a
smith and a reviewer: *"No packet, no review"*, and §3 fixes its fields — `task` · `plan`,
`branch` · `base` · `head`, `changed[]`, `gates` (**output**, not the name), `tests`
(command and tail), `claims[]`, `not_done[]`, `needs[]`, *"written in the house's TOON face
so a human can read it and a script can diff it."*

The plan states the shape and nothing stateable was written down. The reviewer seat measured
the gap on 2026-11-06: `bin/forge/review-rules.sh` had just landed on
`feat/review-rules-floor`, the floor answered with ruleset `7332edd065bd1ff7`, and there was
still **no file a smith could copy**. A packet with no schema is re-invented per errand, and
a reviewer then argues with the form instead of the work.

### What

Two files, deliberately beside each other, both in the TOON face:

| file | what it is |
|---|---|
| `schemas/handoff-packet.toon` | the schema: six rules a writer must honour, the field list with the meaning of each, and the empty block set a packet fills |
| `schemas/handoff-packet.example.toon` | a **worked** packet — one task, two changed files, three gates, two tests, three claims, two deliberate omissions, one need — so a smith copies the form rather than inventing it |

Three things the schema makes non-negotiable, each because the alternative already cost this
house a review:

1. **`head` is what the reviewer compares.** The correction of 2026-11-06 put fetch-then-compare
   into the pipeline; a packet whose `head` differs from the fetched head sha is refused, so
   `head` is a required field with its own rule, not a comment.
2. **`gates` and `tests` carry output.** *"All pass" is not evidence* (§3), and a tail is what
   a reviewer quotes back. The schema says so where a writer will read it.
3. **`review[]` is a separate block the smith may not write.** It is absent until a review has
   run, and it records the reviewer, the ruleset hash, the gate and test output, the verdict,
   the PR, the merge and the resulting commit — so the packet ends up carrying both the
   promise and the proof, in one file, in the order they happened.

### Not done, and why

- No parser or writer ships with this note. The schema is a declaration; `bin/forge/ship.sh`
  (plan 203 M3) is the door that will read it, and it does not exist yet. A validator written
  before the door would encode guesses.
- The example's file paths are the game's (`game/camera/cockpit.js`), because the game is the
  project the review seat is sitting for; the schema itself is project-agnostic.

### The refusal this note does not remove

The reviewer still cannot **merge**: the only credential on the heart is a classic PAT whose
scopes include `repo`, so it can force-push, delete and administer. Plan 203 §12 named the two
things needed — a fine-grained token scoped to Contents:write + Pull requests:write, and a
repository ruleset blocking force-push, deletion and direct push to `main` — and both remain
the Allfather's hand. Until they exist: review, open PRs, never merge.

## CHANGE LOG

- 2026-11-06 · first cut: `schemas/handoff-packet.toon` and its worked example beside it, written
  against plan 203 §3's own field list; the review block kept out of the smith's reach. Blocked on
  `rules-compliance-guard` once (no CHANGE LOG), mended rather than waived.
