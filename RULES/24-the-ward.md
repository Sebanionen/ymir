# 24 — The ward: a door is named, or it is closed

**Appended 2026-10-18** at the Allfather's word — *"we need to add some security systems to see
if we are having insecure open ports or other things and if someone trying to come in to us …
make a security plan for ymir"*, and then *"build the warden"*.

**Why it exists.** On 2026-10-18 an agent measured this house by hand and found: a **public tunnel
answering HTTP 200 with no login**, ssh on every interface with password authentication at its
compiled default, a control plane allowed from **any** address, the vault's own key world-readable,
and **nothing at all watching the host** — no ban for brute force, no audit rules, no file-integrity
baseline, no vulnerability scan. The house had 16 laws for its agents and none for its doors.

```
ward_law[7]{rule,what it means}:
  "A DOOR IS NAMED","every socket listening on a non-loopback address has a written reason — where it is documented, for whom, and why it cannot be loopback. An unnamed wide bind is a finding, not a preference."
  "PUBLIC MEANS AUTHENTICATED","anything reachable from the internet — a tunnel, a published port, a tunnel's origin — either asks for a credential or does not exist. The refusal is the feature."
  "THE ROADS ARE THE LAN AND THE TAILNET","ssh answers the LAN subnet and `tailscale0`, never 'any'. The tailnet is the road that works from anywhere; a hotel is not an exception to this."
  "KEYS, NOT PASSWORDS","sshd accepts keys only. A password that crosses a network is a password that can be guessed at leisure."
  "THE AUDIT IS A CRON, NOT A MOOD","the warden reports on a schedule (`bin/ward/verdr.sh`), writes the report where records live, and speaks when something is HIGH. Security that needs a person to start it is not security."
  "SECRETS AT REST ARE 0600","a plaintext secret, or the key that opens the vault, is readable by its owner and nobody else."
  "A MEND THAT CAN LOCK THE OPERATOR OUT IS HIS","the warden writes the command, the risk and the revert line; the Allfather closes a door that could close behind him."
```

**Also part of the ward, because a record with a wrong clock is a record nobody can trust:** the
clock is synchronised, or the warden's report says it is not (Sól's `check`, Rule 20's neighbour).

**What it forbids:** an unnamed wide bind; a public door without a credential; `PasswordAuthentication
yes`; a `0600`-less secret; a security task that exists only as prose; a change to the firewall or
sshd made *for* the operator instead of *reported to* him.

**Enforced by:** `bin/ward/security-audit.sh` (the eyes — measures and reports, changes nothing;
exit 1 on HIGH or CRITICAL) · `bin/ward/verdr.sh` (**Vörðr**, the warden — walks the house, writes
`hodd/memory/ward/<date>.md`, speaks on HIGH) · `bin/ward/harden.sh` (the mends, written out;
`--sshd` and `--ssh-keys-perm` are safe and validated, `--ufw` refuses without the Allfather's
explicit word) · and the **`ward` surface of Eir**, so a house with an open door is never reported
green. Plan **81** carries the phases (S0–S8) and the stack to adopt (CrowdSec or fail2ban, Lynis,
AIDE, auditd, trivy/grype, gitleaks, and the agent-sandbox work).

## 2026-10-20 — a kill names a pid, never a pattern (appended)

**The ward's law gains its process form.** Measured twice in one session: `pkill -f "<pattern>"`
matched **the shell that ran it**, because `pkill -f` matches the whole command line and the
caller's own command line carries the pattern. A blanket kill does not know what it is killing —
it takes an agent's own process tree, a sibling's pane, or the next unrelated process that happens
to carry the name.

```
kill_law[3]{rule,why}:
  "kill the pid that OWNS the thing","a unit, a pane id, the pid holding the port — all name a target; pkill -f names a guess"
  "a blanket kill is refused at the gate","bin/gates/guards/pkill-guard.sh blocks a push whose added lines invoke pkill or killall"
  "an escape is written on the same line","`# pkill-allowed: <why a pid will not do>` — or YMIR_ALLOW_PKILL=1 for one push, loudly"
```

The same law covers `killall`. `--scan` audits the tree and tells an invocation apart from a mention
(a comment, a vendored banned-pattern list, the tool's own name).

## Appended 2026-11-03 — a road between houses is a grant, never a reachability

Written while building the constellation road (plan 172, `bin/bridge/constellation.sh`). The ward above governs
doors into *this* house. A door *between* houses needs one more sentence, because the temptation is always to
confuse it with network access:

```
cross_house_law[5]{rule,why}:
  "a card is public metadata","name · endpoint · protocol · skills · public key — validated against the one shared agent-card contract, and REFUSED if it carries a secret. A card is a sign on a door, never a share of the house"
  "a grant lives in the house that may be ASKED","per pair, per skill, with an expiry, signed by each house's own key. It is written in the receiving house's hoard, and revoking is deleting a line — the next token fails"
  "a token is short and narrow","EdDSA, an audience, an expiry in minutes, a scope of the skills the grant names; verified against the public key already on the sender's card, so no shared secret exists anywhere between the houses"
  "reachability confers nothing","an address, a DNS name, a port that answers, an agent that 'knew the URL' — none of these is trust, and none may be treated as one"
  "nothing else crosses","not the hoard, not the well or its index, not a calendar or Google grant, not a secret, not a fleet membership. A person of another house is a GUEST with a place-scoped token, never a member of the team group"
```

Two houses that share nothing still each keep their own gate, their own suite and their own law. The road
carries the one request a grant names and its answer, and both sides file the same message as a rune — a road
with one ledger is a rumour.
