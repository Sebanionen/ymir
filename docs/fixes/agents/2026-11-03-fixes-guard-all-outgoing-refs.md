# The fix-note gate judges every outgoing branch

The pre-push reader overwrote its candidate for every stdin row, then judged only the final ref. A batch could therefore hide an unrecorded branch behind a recorded sibling, or reject a valid batch when an already-public ancestor alias happened to come last.

The gate now judges each nondeleted branch independently and accumulates failures. It exempts pointer-only branch creation or updates only when Git proves that the tip contains no commits absent from already-fetched origin refs. A newly outgoing branch still needs an added fix note in its own range; an unrelated history uses the empty tree. Tags and deletions remain content-free, and protected branches remain the separate branch guard's responsibility. Manual --check retains its existing branch/base judgment without the public-pointer exemption.

The real-Git regression covers mixed good/bad refs in both orders, two recorded branches, public ancestor creation and pointer update, new unrecorded content, tags, deletions, a mixed tag/unrecorded batch, manual checking, and a new history without a shared base. No overrides, ref reordering or remote-history assumptions are used.
