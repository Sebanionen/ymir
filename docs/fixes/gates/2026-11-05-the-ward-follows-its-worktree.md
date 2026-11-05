# The dead-code ward judges its worktree

The guard's shell-file exclusion matched any path containing `.yggdrasil`.
When the repository itself was a Yggdrasil worktree, every shell path matched,
so no shell definitions or callers were examined and the ward reported a false
pass. Both the judged roots and usage roots now prune nested `.yggdrasil` and
`node_modules` directories by name, independent of the checkout's own path.
The ward also refuses to pass when shell-file discovery yields nothing.

The newly effective check found `ylist` in the skill manifest command. A
tree-wide search found only its definition and no consumer, and the manifest
command does not call it. Remove the unused reader rather than allowlisting it.
The regression test compares the same called and uncalled shell functions in a
normal checkout and a `.yggdrasil` worktree, and verifies nested exclusions.
The common CI entry point runs this regression test on every host.
