# The constellation road — talking to another fleet's agent

**What it is.** A way for your Ymir to answer another house's Ymir, and only what you
have agreed to answer. Two houses that share nothing — no login, no database, no
fleet — can still exchange a question and an answer, because each side publishes a
**card**, writes a **grant** in its own home, and signs a short-lived **token** for
one named skill. Nothing crosses that a grant does not name.

This is not a chat. A chat carries conversation; a grant carries capability. If you
want two agents to talk freely, open a shared room ([Brimir](brimir-the-hall-of-allfathers.md));
if you want one house's agent to be able to ask another house's agent for
something specific, this is the road.

**What you need.** Node (the shipped card contract is validated by it), Python 3 with
PyYAML (the grants shelf), and — on your side only — a key pair and a card of your
own. The other house needs the same, and the two of you need to have exchanged cards
by hand or through a registry both can read.

**The commands.**

Start by giving your house a key and a card. The card is the sign on your door: your
name, where you answer, and the skills you offer.

```
bin/bridge/constellation.sh keygen <your-house>          # writes a key pair under the hoard
bin/bridge/constellation.sh publish <your-house> \
    --endpoint https://your.host/a2a \
    --skill ask:Ask a question --pub <your-house>.ed25519.pub
```

Put the other house's card in the registry (the same directory — by default
`<hoard>/data/constellation/agents`, or wherever `CONSTELLATION_REGISTRY` points), and
look at who is there:

```
bin/bridge/constellation.sh list
bin/bridge/constellation.sh show <peer>
```

Grant them a skill — only one their card actually declares, or the door refuses and
names what it does declare. A grant starts as **pending** until the other house
countersigns the same body with its own key:

```
bin/bridge/constellation.sh grant <peer> ask --self <your-house> --expires 2027-01-01T00:00:00Z
bin/bridge/constellation.sh countersign <grant-id> --sig <their-signature> --pub <their>.ed25519.pub
bin/bridge/constellation.sh grants
```

Mint a token for one call, and verify one you receive:

```
bin/bridge/constellation.sh mint --peer <peer> --skill ask --self <your-house> --minutes 5
bin/bridge/constellation.sh verify --pub <their>.ed25519.pub --token <token> --aud <your-house> --skill ask
```

Withdraw a grant at any moment — the next token for it fails:

```
bin/bridge/constellation.sh revoke <peer>          # or revoke <grant-id>
```

To check the shelf against the cards it names, run the ward:

```
bin/bridge/constellation.sh guard
```

**Limits, stated plainly.** A token lives at most 24 hours and five minutes by
default, and never longer than you ask; expiry is checked with a 60-second tolerance
for clock skew. A grant opens **only** the skills it names, and only after both
houses have signed. The road carries a request and its answer — not your hoard, not
your memory, not your files, not a secret. Your card is public metadata: it must
never carry a token, a password or a private key, and the door refuses a card that
does. Nothing here enrols the other house in your fleet, and nothing here opens your
Gimlé suite to them: a person of another house who needs the suite is a **guest**
with a place-scoped token, never a member of your team.

**If it does not work.**

- *"no registry at …"* — the registry is unconfigured, which is reported as unknown,
  never as "no peers". Set `CONSTELLATION_REGISTRY` or publish a card first.
- *"does not declare skill …"* — the peer's card does not offer that skill. Publish or
  correct their card; the message lists what it does offer.
- *"no active grant names skill …"* — minting refuses to claim what the shelf does not
  hold. Countersign the pending grant, or grant the skill first.
- *"cannot be activated: no signature from …"* — one house has signed and the other
  has not. That is the law, not a fault.
- *"the signature does not verify"* — you are verifying against the wrong key, or the
  token/signature was made over different bytes. Compare the `kid` printed by
  `keygen` with the `kid` on the card.
- *"node is required"* / *"PyYAML is required"* — install them; the door names the
  missing piece rather than guessing.
