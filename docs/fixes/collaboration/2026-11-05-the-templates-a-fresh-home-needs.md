# The templates a fresh home needs for the collaborator doors

**2026-11-05 · component: collaboration · `.agents/config/*.example`**

His word: *"do we need to ad d more templates in ymir to be used in ymir home to be used on installations and updates for ymir."*

## Why

Three files this session made real on this box had **no template**: the skills grant table, the collaborator doors register, and the A2A front environment. A fresh install would leave a new machine with doors and no shape for them.

## Added

`skills-grants.yaml.example` · `doors.yaml.example` · `a2a-front.env.example` — shape only, never a value: no host, no token, no mailbox. The `transport:` field exists so no door can be described without saying which network it uses (home RULES/network.md N6).

## CHANGE LOG

- **2026-11-05** — three templates added (Hœnir).
