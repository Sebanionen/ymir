"""Regression tests for the bridge recall contract, without touching a real well."""
import importlib.util
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch

sys.modules.setdefault("engram", types.SimpleNamespace(Engram=object))
path = Path(__file__).resolve().parents[1] / "bin" / "bridge" / "mimir-bridge.py"
spec = importlib.util.spec_from_file_location("mimir_bridge_recall_test", path)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class RecallLimit(unittest.TestCase):
    def call(self, query):
        handler = bridge.Handler.__new__(bridge.Handler)
        handler.path = "/recall?q=sentinel&" + query
        response = []
        handler._json = lambda code, body: response.append((code, body))
        # One inaccessible hit and a duplicate precede 35 valid ranked hits.
        ids = ["outside", "id0", "id0"] + [f"id{i}" for i in range(1, 35)]
        hits = [types.SimpleNamespace(
            episode={"id": value}, score=1, distance=0, importance=1
        ) for value in ids]
        eng = types.SimpleNamespace(recall=lambda *a, **k: hits)
        rows = [{"id": f"id{i}"} for i in range(35)]
        with patch.object(bridge, "build_slice", return_value=rows), \
             patch.object(bridge, "engine", return_value=eng), \
             patch.object(bridge, "ep_json", side_effect=lambda e: e), \
             patch.object(bridge, "flush_access"):
            handler.do_GET()
        return response[0]

    def test_scoped_unique_hits_are_capped_to_requested_limit(self):
        status, body = self.call("k=2")
        self.assertEqual(status, 200)
        self.assertEqual([r["episode"]["id"] for r in body["results"]], ["id0", "id1"])
        self.assertEqual(body["slice"], 35)

    def test_invalid_limits_are_rejected(self):
        for value in ("0", "-1", "1001", "bad"):
            with self.subTest(value=value):
                status, body = self.call("k=" + value)
                self.assertEqual(status, 400)
                self.assertIn("k must", body["error"])


if __name__ == "__main__":
    unittest.main()
