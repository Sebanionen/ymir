## mail · unversioned · 2026-11-06 — the desk's port, said where the desk is described

PR #547 moved the mail desk to **8494** and declared it in the operator's `services.yaml`. It
updated the four places that *read* the port — `gna_desk.py`, `install.sh`, `fleet-ensure.sh`, the
nornir job — and left two places that only *say* it: the autoboot row and the Eir surface comment.

Measured on the heart after the merge: the unit re-templated correctly
(`--port 8494`, `Environment=GNA_DESK_PORT=8494`), the desk answered `/health` **200** on 8494, and
Gimlé's `gimle-share` still held 8490 untouched. But `systemctl cat gna-desk` and `fleet-ensure`'s
own report both still read *":8490"*, because they print the description string, not the binding.

A description that names the wrong port is the same class of fault as the original displacement —
one line of prose being trusted as a fact. Fixed here in both strings; the binding is unchanged.

## CHANGE LOG

- 2026-11-06 · the two prose strings corrected to 8494 (autoboot row, Eir surface comment); no
  binding, unit or default touched.
