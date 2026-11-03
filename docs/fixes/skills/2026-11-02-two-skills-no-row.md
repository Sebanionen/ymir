# Two skills were on disk and on nobody's shelf — main could not pass its own gate

**Date:** 2026-11-02 · **Component:** skills

## What was wrong

`compliance-check.sh` compares the skill directories found on disk with the rows in `.agents/skills/README.md`
and fails on a difference. **`main` itself failed it:**

```
"skillindex","skill index + cited skill paths","FAIL","unindexed skills:maestro-video vingolf "
```

Both directories exist on `origin/main` (`.agents/skills/maestro-video/`, `.agents/skills/vingolf/`) and
neither has a row. That is not a fault any single pull request introduced — it is the merged state of the tree,
so **every** PR was blocked by it, and the block looked like the PR's own failure.

A skill that ships without a row is a skill no agent can find: the index is the door (`skill-find.sh` reads
it), and an unindexed skill is invisible in exactly the way a missing `description:` is.

## What changed

One row each, in the file's own shape (name · what it is · the figure it belongs to):

- `vingolf` — the assembly hall: who collaborates with the house, the six rungs, the baton shelf, the letter,
  the ship door.
- `maestro-video` — the video forge: Maestro over REST (t2v, i2v, music, voice) and the provision road for a
  seat.

## Measured

```
"skillindex","skill index + cited skill paths","PASS","30 skills, all indexed and cited paths resolve"
```

and no other row of the compliance surface fails on this tree.
