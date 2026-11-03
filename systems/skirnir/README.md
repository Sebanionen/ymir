# Skírnir — the Allfather's assistant, in his own house

Skírnir is Frey's messenger: he is sent on errands and returns with news. This folder is his domain —
the fourth thing to be lifted out of `bin/` by ownership rather than by layer (plan 129, plan 149).

**Who keeps him:** `skirnir` (`.agents/agents/skirnir-assistant.md`). **His declaration:**
`domain.yaml` — folder · board · memory · doors · called_by · never.

**What is here**

| part | doors |
|---|---|
| the voice | `services/ear.sh` · `mouth.sh` · `voice.sh` · `voice-handler.sh` · `speech-text.py` · `audio-tighten.py` |
| the knowledge | `services/skirnir.py` · `ground.py` · `research.py` · `learn*.sh` · `query.sh` · `report.sh` · `kb-export.sh` · `prune.sh` |
| the gate | `services/asks.sh` · `ask.sh` · `approve-fact.sh` · `ban.sh` · `group-allow.sh` · `escalate.sh` · `escalation-timer.sh` |
| the rooms | `services/room.sh` · `room-squad.sh` · `room-wall-test.sh` · `walls-test.sh` · `smoke.sh` · `canaries.txt` |

**The law he obeys:** nothing leaves the house without the outbound gate's approved word; he never
speaks for the Allfather in a room the Allfather has not opened; he carries no secret value — he
references the vault.

`bin/assistant/` holds **retired shims** that exec these doors, so a caller nobody has repointed yet
still works. They retire by a dated note, never silently.

Windows and WSL file voice and engine control: [operator guide](../../docs/features/voice-files-on-windows.md). The Kokoro adapter supports English. The [Hlidskjalf speech entry](../../docs/features/talk-to-skirnir.md) adds app-scoped F8/Escape and separate genuine Swedish Bengt speech.
