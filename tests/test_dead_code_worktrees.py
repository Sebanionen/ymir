"""The dead-code ward must judge shell definitions in every checkout path."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

GUARD = Path(__file__).resolve().parents[1] / "bin/gates/guards/dead-code-guard.sh"


class CheckoutPath(unittest.TestCase):
    def fixture(self, root):
        for name in (".pi", "RULES", "bin/gates/guards", "scripts",
                     "bin/nested/.yggdrasil", "bin/nested/node_modules",
                     ".agents/skills/example"):
            (root / name).mkdir(parents=True, exist_ok=True)
        shutil.copyfile(GUARD, root / "bin/gates/guards/dead-code-guard.sh")
        (root / "bin/example.sh").write_text(
            "dead_function() { :; }\n"
            "called_function() { :; }\n"
            "agent_called() { :; }\n"
            "shielded_dead() { :; }\n", encoding="utf-8")
        (root / "scripts/caller.sh").write_text("called_function\n", encoding="utf-8")
        (root / ".agents/skills/example/caller.sh").write_text("agent_called\n", encoding="utf-8")
        for nested in (".yggdrasil", "node_modules"):
            (root / "bin/nested" / nested / "ignored.sh").write_text(
                "ignored_function() { :; }\nshielded_dead\n", encoding="utf-8")

    def test_regular_and_yggdrasil_checkout_report_same_real_findings(self):
        with tempfile.TemporaryDirectory(prefix="dead-code-checkout-") as tmp:
            root = Path(tmp)
            regular = root / "regular"
            worktree = root / ".yggdrasil" / "worker"
            verdicts = []
            for checkout in (regular, worktree):
                self.fixture(checkout)
                result = subprocess.run(
                    ["bash", str(checkout / "bin/gates/guards/dead-code-guard.sh"), "check"],
                    text=True, capture_output=True, check=False,
                )
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                findings = sorted(line for line in result.stdout.splitlines()
                                  if "DEAD FUNCTION" in line)
                self.assertEqual(len(findings), 2, result.stdout)
                self.assertTrue(any("dead_function" in line for line in findings), findings)
                self.assertTrue(any("shielded_dead" in line for line in findings), findings)
                self.assertFalse(any("ignored_function" in line for line in findings), findings)
                self.assertFalse(any("called_function" in line for line in findings), findings)
                self.assertFalse(any("agent_called" in line for line in findings), findings)
                verdicts.append(findings)
            self.assertEqual(*verdicts)


    def test_failed_file_discovery_is_not_reported_as_clean(self):
        with tempfile.TemporaryDirectory(prefix="dead-code-find-") as tmp:
            root = Path(tmp)
            checkout = root / "checkout"
            self.fixture(checkout)
            broken_bin = root / "broken-bin"
            broken_bin.mkdir()
            broken_find = broken_bin / "find"
            broken_find.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
            broken_find.chmod(0o755)
            result = subprocess.run(
                ["bash", str(checkout / "bin/gates/guards/dead-code-guard.sh"), "check"],
                text=True, capture_output=True, check=False,
                env={**os.environ, "PATH": str(broken_bin) + os.pathsep + os.environ["PATH"]},
            )
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("no shell files to judge", result.stderr)


if __name__ == "__main__":
    unittest.main()
