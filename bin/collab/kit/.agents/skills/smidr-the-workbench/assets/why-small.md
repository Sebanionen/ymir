# Why small, and why the note

## The arithmetic a reviewer pays

A reader holds about a screenful in their head. A change of forty lines is read twice and understood; a change of eight
hundred in one component is skimmed, approved, and trusted — which is not review, it is a signature. The cost of a large
slice is not paid by the author, who already knows the answer; it is paid by the next hand, who must rediscover the whole
shape to check one line.

## What a fix note buys

A note under `docs/fixes/<component>/` is three short sections — what was wrong, what was done, how it was verified — and it
is the only artefact that survives a session. Six months later the diff says *what* changed; the note says *why*, which is
what a maintainer actually needs. That is why the gate demands it, and why a note written honestly is worth more than a long
commit message.

## The one exception

A change that cannot be small — a rename, a migration, a dependency upgrade — is announced in the pull request body, sliced
in the review order, and never mixed with a behaviour change. If the diff and the description disagree about what the change
is, the change is not ready.

## CHANGE LOG

- **2026-11-06** — Written for the workbench skill: the arithmetic a reviewer pays, and what a fix note buys.
