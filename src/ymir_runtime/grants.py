"""The grants law — explicit, signed, cross-operator shares of a company namespace.

Plan 58, *Several Ymirs, one company*. Plan 42 federates ONE operator's machines;
this federates SEVERAL operators' Ymirs, each with its own private hoard. That
crosses the realm law (Rule 05): a shared company project is an **explicit grant**
between operators, never a blanket merge. This module is the registry shape and
the law that judges it — the data lives in the hoard, the validator lives here.

    <hoard>/identity/grants.yaml        the local grant registry
    config/grants.schema.json           its shape (the config layer's kind)

The law this module enforces (a semantic check JSON Schema cannot state):

  1. **Signed per Heimdall.** A grant that crosses operators must carry a
     signature from EACH party's Heimdall. A cross-operator grant with a missing
     signature is REFUSED, naming the Heimdall that did not sign.
     **Unless it is `pending`** — added 2026-11-03 with plan 172: two independent
     houses sign at different moments, so a grant signed by one party and awaiting
     the other's countersignature is `pending` and **may not be used**; `pending`
     is exempt from the missing-signature refusal and from nothing else (a foreign
     or duplicate signer is still refused). Only `activate` makes it `active`.
  2. **A card that says it is signed must be signed.** A party whose
     `card.signed` is true must have a signature from its own Heimdall — the
     card's claim and the registry's signatures can never disagree.
  3. **No foreign signer.** A signature must come from one of the two parties; a
     Heimdall outside the grant may not sign it.
  4. **No self-grant.** A grant whose two parties share a Heimdall is refused.

The `card` block is deliberately the SAME shape as the shared A2A agent-card
contract (packages/contracts `AgentInterface`: protocol · endpoint · signed) — one
contract for the card, one for the grant, never a second.

The door is `python3 -m ymir_runtime.grants` (and, through the config layer,
`bin/gates/checks/ymir-config-check.sh validate <grants.yaml>`). This module is not one of the
engine's four verbs; it is a support law beside them.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any, Mapping, Sequence

from .errors import EngineError

REGISTRY_KIND = "grants"
REGISTRY_RELPATH = ("identity", "grants.yaml")

EXIT_OK = 0
EXIT_REFUSED = 1
EXIT_USAGE = 2
EXIT_UNAVAILABLE = 3

_CROSS = "cross-operator"


class GrantLawError(EngineError):
    """A grant broke the realm law. `key` names the offending field, always."""

    def __init__(self, message: str, *, key: str = "<grant>", source: str = "") -> None:
        super().__init__(message)
        self.message = message
        self.key = key
        self.source = source

    def __str__(self) -> str:
        where = f"{self.source}: {self.key}" if self.source else self.key
        return f"{where}: {self.message}"


def _refuse(message: str, *, source: str, key: str) -> None:
    """Refuse in the config layer's own voice so the door prints one shape."""
    from .config.schema import ConfigValidationError

    raise ConfigValidationError(message, source=source, key=key, schema_name="grants.schema.json")


def default_registry(roots: Any) -> Path:
    """The one documented registry path: `<hoard>/identity/grants.yaml`."""
    hoard = getattr(roots, "hoard", None)
    if hoard is None:  # pragma: no cover - a caller passed the wrong shape
        raise GrantLawError("no hoard resolved for the grants registry", key="<root>")
    return Path(hoard).joinpath(*REGISTRY_RELPATH)


def parties(grant: Mapping[str, Any]) -> tuple[Mapping[str, Any], Mapping[str, Any]]:
    """The two sides of a grant, in order: grantor then grantee."""
    return grant["grantor"], grant["grantee"]


def is_cross_operator(grant: Mapping[str, Any]) -> bool:
    """Does this grant cross the realm boundary between two operators?"""
    grantor, grantee = parties(grant)
    return str(grantor.get("operator")) != str(grantee.get("operator"))


def required_signers(grant: Mapping[str, Any]) -> tuple[str, ...]:
    """The Heimdall key ids that MUST have signed this grant.

    Cross-operator: both parties. A party whose card claims `signed: true` is
    required even within one operator. The order is grantor, grantee.
    """
    grantor, grantee = parties(grant)
    cross = is_cross_operator(grant)
    needed: list[str] = []
    for party in (grantor, grantee):
        heimdall = str(party.get("heimdall", ""))
        if (cross or bool((party.get("card") or {}).get("signed"))) and heimdall:
            needed.append(heimdall)
    return tuple(needed)


def _signers(grant: Mapping[str, Any]) -> list[str]:
    return [str(sig.get("signer", "")) for sig in (grant.get("signatures") or [])]


def check_grant(grant: Mapping[str, Any], *, source: str, key: str) -> None:
    """Judge one grant against the realm law; refuse loudly, naming the field."""
    grantor, grantee = parties(grant)

    if str(grantor.get("heimdall")) == str(grantee.get("heimdall")):
        _refuse(
            f"grant {grant.get('grant_id', '?')!r} names one Heimdall on both sides; a grant is between two parties",
            source=source,
            key=f"{key}.grantee.heimdall",
        )

    heimdalls = {str(grantor.get("heimdall", "")), str(grantee.get("heimdall", ""))}
    signers = _signers(grant)

    for signer in signers:
        if signer not in heimdalls:
            _refuse(
                f"signature from {signer!r} is foreign to grant {grant.get('grant_id', '?')!r}; "
                f"only a party's Heimdall may sign",
                source=source,
                key=f"{key}.signatures",
            )
    duplicates = sorted({s for s in signers if signers.count(s) > 1})
    if duplicates:
        _refuse(
            f"grant {grant.get('grant_id', '?')!r} carries duplicate signatures from {', '.join(duplicates)}",
            source=source,
            key=f"{key}.signatures",
        )

    cross = is_cross_operator(grant)
    pending = str(grant.get("state", "")) == "pending"
    for party in (grantor, grantee):
        heimdall = str(party.get("heimdall", ""))
        signed = bool((party.get("card") or {}).get("signed"))
        if pending:
            continue
        if (cross or signed) and heimdall and heimdall not in signers:
            why = _CROSS if cross else "its card declares it signed"
            _refuse(
                f"grant {grant.get('grant_id', '?')!r} has no signature from Heimdall {heimdall!r} "
                f"({why}); the realm law requires the signature",
                source=source,
                key=f"{key}.signatures",
            )


def check_registry(doc: Mapping[str, Any], *, source: str, **_ignored: Any) -> None:
    """The config layer's semantic check: every grant obeys the realm law."""
    seen: dict[str, int] = {}
    for index, grant in enumerate(doc.get("grants") or []):
        grant_id = str(grant.get("grant_id", ""))
        if grant_id in seen:
            _refuse(
                f"grant_id {grant_id!r} is declared twice (grants[{seen[grant_id]}] and grants[{index}]); "
                f"a replayed id is refused, never silently applied",
                source=source,
                key=f"grants[{index}].grant_id",
            )
        seen[grant_id] = index
        check_grant(grant, source=source, key=f"grants[{index}]")


def load_registry(
    path: str | Path | None = None,
    *,
    roots: Any = None,
    env: Mapping[str, str] | None = None,
    root: str | Path | None = None,
    schema_dir: str | Path | None = None,
) -> Any:
    """Load and judge the grant registry — or refuse loudly.

    `path` defaults to {@link default_registry} from the resolved roots; the file
    is read, parsed and validated by the config layer (kind `grants`) before a
    single value is trusted.
    """
    if path is None:
        from . import paths

        roots = roots if roots is not None else paths.resolve(env)
        source = default_registry(roots)
    else:
        source = Path(path).expanduser()
    from .config import load_config

    return load_config(source, kind=REGISTRY_KIND, root=root, schema_dir=schema_dir)


# ── the door ─────────────────────────────────────────────────────────────────


def _row(header: str, cells: Sequence[str]) -> str:
    return f"{header}:\n  " + ",".join(f'"{cell}"' for cell in cells) + "\n"


def _judge(path: str | Path | None) -> int:
    from .config.schema import ConfigError, ConfigUnavailable, available

    if not available():
        print(_row("grants-check[1]{status,detail}", ("unavailable", "jsonschema missing — bin/engine/ymir-engine-ensure.sh ensure")), end="")
        return EXIT_UNAVAILABLE
    try:
        data = load_registry(path)
    except ConfigUnavailable as exc:
        print(_row("grants-check[1]{status,detail}", ("unavailable", f"{exc.dependency} missing — {exc.remedy}")), end="")
        return EXIT_UNAVAILABLE
    except ConfigError as exc:
        print(_row("grants-check[1]{status,detail}", ("refuse", str(exc))), end="")
        return EXIT_REFUSED
    grants = data.get("grants") or []
    cross = sum(1 for grant in grants if is_cross_operator(grant))
    print(_row(
        "grants-check[1]{status,grants,cross_operator,detail}",
        ("ok", str(len(grants)), str(cross), "every grant obeys the realm law"),
    ), end="")
    return EXIT_OK


def _print_signers(path: str | Path | None, grant_id: str) -> int:
    from .config.schema import ConfigError

    try:
        data = load_registry(path)
    except ConfigError as exc:
        print(_row("grants-signers[1]{status,detail}", ("refuse", str(exc))), end="")
        return EXIT_REFUSED
    rows: list[tuple[str, ...]] = []
    for grant in data.get("grants") or []:
        if grant_id and str(grant.get("grant_id")) != grant_id:
            continue
        needed = required_signers(grant)
        have = _signers(grant)
        rows.append((
            str(grant.get("grant_id", "")),
            str(grant.get("namespace", "")),
            "yes" if is_cross_operator(grant) else "no",
            ",".join(needed) or "-",
            ",".join(have) or "-",
            "yes" if set(needed).issubset(set(have)) else "no",
        ))
    body = "\n".join("  " + ",".join(f'"{cell}"' for cell in row) for row in rows)
    print(f"grant_signers[{len(rows)}]{{grant_id,namespace,cross_operator,required,have,signed}}:\n{body}\n", end="")
    return EXIT_OK


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="ymir_runtime.grants", description="the grants law — explicit, signed, cross-operator namespace shares")
    parser.add_argument("--version", action="version", version="1.0.0")
    parser.add_argument("mode", nargs="?", default="check", choices=("check", "signers", "default"))
    parser.add_argument("file", nargs="?", default="", help="the registry YAML (default: the hoard's)")
    parser.add_argument("--grant-id", default="", help="restrict `signers` to one grant")
    parser.add_argument("--root", default="", help="the code tree holding config/*.schema.json")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(list(argv) if argv is not None else None)
    if args.mode == "default":
        from . import paths

        print(default_registry(paths.resolve()))
        return EXIT_OK
    if args.mode == "signers":
        return _print_signers(args.file or None, args.grant_id)
    return _judge(args.file or None)


if __name__ == "__main__":  # pragma: no cover - the door's entry
    raise SystemExit(main())
