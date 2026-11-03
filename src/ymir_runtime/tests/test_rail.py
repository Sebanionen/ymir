"""fleet/rail.py — the living rail resolver (plan 51, Parts 9a/9b/9c).

A synthetic registry and a scripted liveness stand in for the fleet, so the
DECISION is asserted — which strong box serves, which is dropped, and what a
declined answer looks like — with no network and no private registry touched.
"""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from ymir_runtime.fleet import (
    KEY_REF,
    Probe,
    Target,
    candidates,
    read_key,
    read_registry,
    resolve,
    status,
    strong_boxes,
)

# Three strong boxes in rank order, plus a heart that is not a rail.
SYNTHETIC = {
    "heart": "heartbox",
    "rails": ["railbox", "backupbox", "deadbox"],
    "hosts": {
        "railbox": {"roles": ["dev"], "tailnet": "railbox.<host>.tailnet.ts.net"},
        "backupbox": {"roles": ["forge"], "lan": "192.0.2.0.2"},
        "deadbox": {"roles": ["dev"], "tailnet": "deadbox.<host>.tailnet.ts.net"},
        "heartbox": {"roles": ["heart"], "tailnet": "heartbox.<host>.tailnet.ts.net"},
    },
}


def scripted(table: dict[str, Probe]):
    """A probe answering from a per-host table; an unlisted host is dead."""
    def probe(target: Target) -> Probe:
        return table.get(target.host, Probe(False, "timeout"))
    return probe


class StrongBoxTest(unittest.TestCase):
    """Which boxes the registry names, and which it never invents."""

    def test_rails_list_wins_and_keeps_its_order(self) -> None:
        doc = dict(SYNTHETIC)
        doc["ear"] = ["deadbox", "railbox"]
        self.assertEqual(strong_boxes(doc), ["railbox", "backupbox", "deadbox"])

    def test_ear_is_the_fallback_when_rails_is_absent(self) -> None:
        doc = {"hosts": SYNTHETIC["hosts"], "ear": ["heimdall-like", "railbox"]}
        self.assertEqual(strong_boxes(doc), ["railbox"])

    def test_forge_hosts_are_the_last_fallback(self) -> None:
        doc = {"hosts": SYNTHETIC["hosts"]}
        self.assertEqual(strong_boxes(doc), ["backupbox"])

    def test_an_undeclared_box_is_never_invented(self) -> None:
        doc = {"hosts": SYNTHETIC["hosts"], "rails": ["ghost", "backupbox"]}
        self.assertEqual(strong_boxes(doc), ["backupbox"])

    def test_a_rails_list_of_only_ghosts_falls_through(self) -> None:
        doc = {"hosts": SYNTHETIC["hosts"], "rails": ["ghost"], "ear": ["railbox"]}
        self.assertEqual(strong_boxes(doc), ["railbox"])


class CandidateTest(unittest.TestCase):
    """Address resolution: loopback on the box itself, tailnet then LAN."""

    def test_this_box_answers_on_loopback(self) -> None:
        targets = candidates(SYNTHETIC, "railbox")
        self.assertEqual(targets[0].address, "127.0.0.1")
        self.assertEqual(targets[0].url, "http://127.0.0.1:8080/v1")

    def test_a_remote_box_prefers_tailnet_then_lan(self) -> None:
        targets = candidates(SYNTHETIC, "heartbox")
        self.assertEqual(targets[0].address, "railbox.<host>.tailnet.ts.net")
        self.assertEqual(targets[1].address, "192.0.2.0.2")

    def test_the_registry_order_is_kept(self) -> None:
        self.assertEqual([t.host for t in candidates(SYNTHETIC, "heartbox")],
                         ["railbox", "backupbox", "deadbox"])


class ResolutionTest(unittest.TestCase):
    """One box up and one down: the UP one serves. Both down: a declined answer."""

    def test_the_first_live_box_serves(self) -> None:
        probe = scripted({
            "railbox": Probe(False, "timeout"),
            "backupbox": Probe(True, "health", ("beta@q4",)),
            "deadbox": Probe(False, "refused"),
        })
        result = status(doc=SYNTHETIC, self_host="heartbox", probe=probe)
        self.assertFalse(result.declined)
        self.assertEqual(result.serving.host, "backupbox")
        self.assertEqual(result.serving.url, "http://192.0.2.0.2:8080/v1")
        self.assertEqual(result.serving.key_ref, KEY_REF)
        self.assertEqual([r.host for r in result.live], ["backupbox"])

    def test_the_rank_order_decides_between_two_live_boxes(self) -> None:
        probe = scripted({
            "railbox": Probe(True, "health", ("alpha@q4",)),
            "backupbox": Probe(True, "health", ("beta@q4",)),
        })
        result = status(doc=SYNTHETIC, self_host="heartbox", probe=probe)
        self.assertEqual(result.serving.host, "railbox")

    def test_both_down_is_a_declined_answer_never_a_fake(self) -> None:
        probe = scripted({
            "railbox": Probe(False, "timeout"),
            "backupbox": Probe(False, "unreachable"),
            "deadbox": Probe(False, "refused"),
        })
        result = status(doc=SYNTHETIC, self_host="heartbox", probe=probe)
        self.assertTrue(result.declined)
        self.assertIsNone(result.serving)
        self.assertIn("no registered rail is alive", result.reason)
        self.assertTrue(all(not rail.live for rail in result.rails))

    def test_a_raising_probe_is_a_dead_box_not_a_crash(self) -> None:
        def probe(target: Target) -> Probe:
            if target.host == "railbox":
                raise OSError("boom")
            return Probe(True, "health")

        result = status(doc=SYNTHETIC, self_host="heartbox", probe=probe)
        self.assertEqual(result.serving.host, "backupbox")
        self.assertEqual(result.rails[0].reason, "unreachable")

    def test_an_empty_registry_declines(self) -> None:
        result = status(doc={}, self_host="heartbox", probe=scripted({}))
        self.assertTrue(result.declined)
        self.assertIn("names no strong box", result.reason)


class AliasTest(unittest.TestCase):
    """A seat's name resolves against the box that SERVES it, by liveness."""

    def test_the_alias_selects_the_box_that_serves_it(self) -> None:
        probe = scripted({
            "railbox": Probe(True, "health", ("alpha@q4",)),
            "backupbox": Probe(True, "health", ("beta@q4",)),
        })
        result = resolve("beta@q4", doc=SYNTHETIC, self_host="heartbox", probe=probe)
        self.assertEqual(result.serving.host, "backupbox")
        self.assertTrue(result.serving.alias_verified)

    def test_the_first_alive_box_serves_an_alias_it_carries(self) -> None:
        probe = scripted({
            "railbox": Probe(True, "health", ("alpha@q4", "beta@q4")),
            "backupbox": Probe(True, "health", ("beta@q4",)),
        })
        result = resolve("beta@q4", doc=SYNTHETIC, self_host="heartbox", probe=probe)
        self.assertEqual(result.serving.host, "railbox")

    def test_no_live_box_serving_the_alias_declines(self) -> None:
        probe = scripted({
            "railbox": Probe(True, "health", ("alpha@q4",)),
            "backupbox": Probe(True, "health", ("beta@q4",)),
        })
        result = resolve("gamma@q4", doc=SYNTHETIC, self_host="heartbox", probe=probe)
        self.assertTrue(result.declined)
        self.assertIn("gamma@q4", result.reason)

    def test_a_key_refused_box_serves_unverified_not_failed(self) -> None:
        probe = scripted({"railbox": Probe(True, "reachable (key refused)", (), True)})
        result = resolve("alpha@q4", doc=SYNTHETIC, self_host="heartbox", probe=probe)
        self.assertFalse(result.declined)
        self.assertEqual(result.serving.host, "railbox")
        self.assertFalse(result.serving.alias_verified)


class RegistryTest(unittest.TestCase):
    """The private registry is read at runtime; a fault degrades, never raises."""

    def test_a_missing_registry_reads_empty(self) -> None:
        missing = Path(tempfile.mkdtemp()) / "nope.json"
        self.assertEqual(read_registry(missing), {})

    def test_a_registry_round_trips(self) -> None:
        path = Path(tempfile.mkdtemp()) / "fleet.json"
        path.write_text(json.dumps(SYNTHETIC), encoding="utf-8")
        self.assertEqual(read_registry(path)["heart"], "heartbox")

    def test_the_key_is_a_reference_from_the_environment(self) -> None:
        value, source = read_key({"LLAMA_SWAP_API_KEY": "not-a-real-key"})
        self.assertEqual(source, "environment")
        self.assertEqual(value, "not-a-real-key")
        value, source = read_key({})
        self.assertIn(source, ("hoard", "pi-auth", "absent"))


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
