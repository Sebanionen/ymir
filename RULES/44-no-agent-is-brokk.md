# Rule 44 — No agent is Brokk; every agent names itself, and says whose it is

**Appended 2026-11-03, by the Allfather's word:** *"brokk can not be called brokk on any users
machine or any fleet. it needs to be custom names. otherwise there will be several of brokks from
different fleets. that will be very confusing. every agent needs also present what house/fleet/machine
they come from … and who their Allfathers are … all this must come in updates and installations."*

## The law

1. **Brokk is a ROLE, never a name.** The counsellor's role — plan, steer, review, dispatch — is
   Brokk's. No machine, no seat, no fleet and no user's installation may name an agent `Brokk`.
   A fleet with two agents called Brokk cannot say which house spoke, and the operator cannot tell.
2. **Every machine names its own agents**, by the naming law's role sentence
   (`galdr-ymirsystem/assets/norse-naming.md` §3.1b): the *seat primary* works inside Ymir, and the
   *machine agent* keeps the computer. They are two different agents on one machine, each with its
   own name — and each named per host, never shared across the fleet.
3. **Every agent declares whose it is** whenever it introduces itself: **house · fleet · machine ·
   Allfather**. A name alone is not an identity; the four lines are.
4. **An unsealed name is said as unnamed.** A host whose roster carries no name renders *unnamed —
   the roster has not sealed a name*, never an invented one.
5. **The refusal is mechanical.** `bin/seat/seat-surface.sh` refuses to render a seat whose roster
   primary or machine agent is `brokk`, and its `--check` fails a surface that does not declare the
   four lines. The names come from the operator's own config (`hodd/identity/seats.yaml` and
   `operator.yaml`), never from a shipped default.
6. **It ships with Ymir.** The identity is written by the **install** and by **every update** (Gróa)
   — through the one core (`seat-surface.sh`), which the Windows door reaches inside WSL and macOS
   and Linux run directly (Rule 05). A user who installs Ymir gets their own names; a user who
   updates it gets them re-rendered.

## Where it lives

| Piece | Path |
|---|---|
| the roster: every seat, its primary, its machine agent, the fleet block | `$YMIR_HOME/hodd/identity/seats.yaml` |
| the fleet address and the Allfather's name | `$YMIR_HOME/hodd/identity/operator.yaml` |
| the renderer (seat file · `.hermes.md` · `SOUL.md`) | `bin/seat/seat-surface.sh` + `bin/seat/assets/hermes-soul.md.in` |
| the MCP door every harness reads | `bin/mcp/ymir-mcp.py` (`ymir_where` answers the seat, the house, the fleet) |
| the figure table for machine agents | `norse-naming.md` §3.1b |

**Related:** Rule 43 (the tongues), Rule 25 (agnostic by construction: a clean skip is a pass),
Rule 05 (one core, every platform), Rule 02 (agents: `.agents/agents` is canonical).
