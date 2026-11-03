"""Exercise the real path guard with invalid UTF-8, without suppressing matches."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = os.environ.get('YMIR_BASH') or shutil.which('bash')


@unittest.skipUnless(BASH, 'requires Bash with grep')
class PathLedgerBytesTest(unittest.TestCase):
    def test_paired_moves_and_stale_references_keep_line_context(self):
        with tempfile.TemporaryDirectory(prefix='path-ledger-bytes-') as temporary:
            root = Path(temporary)
            (root/'.agents').mkdir()
            (root/'RULES').mkdir()
            (root/'.agents/paths-ledger.yaml').write_text(
                'moves:\n  - old: bin/old-path/\n    new: systems/new-path/\n', encoding='utf-8')
            sample = root/'.agents/sample.md'
            fixture_root = root.as_posix()
            if os.name == 'nt':
                fixture_root = subprocess.check_output(
                    [BASH, '-c', 'cygpath -u "$1"', '_', str(root)], text=True).strip()
            env = {**os.environ, 'YMIR_GUARD_ROOT': fixture_root,
                   'TEST_PYTHON': Path(sys.executable).as_posix(), 'LC_ALL': 'C.UTF-8'}
            cases = (
                ('invalid paired', b'\xff bin/old-path/item -> systems/new-path/item\n', 0),
                ('invalid stale', b'\xff bin/old-path/item\n', 1),
                ('valid paired', b'bin/old-path/item -> systems/new-path/item\n', 0),
                ('valid stale', b'bin/old-path/item\n', 1),
            )
            for name, body, expected in cases:
                with self.subTest(name=name):
                    sample.write_bytes(body)
                    result = subprocess.run(
                        [BASH, '-c', 'python3() { "$TEST_PYTHON" "$@"; }; export -f python3; exec bash "$1" check',
                         '_', (ROOT/'bin/gates/guards/path-ledger-guard.sh').as_posix()],
                        env=env, capture_output=True)
                    output = (result.stdout + result.stderr).decode('utf-8', errors='replace')
                    self.assertEqual(result.returncode, expected, output)
                    self.assertNotIn('Binary file', output)
                    if expected:
                        self.assertIn('.agents/sample.md', output)
                        self.assertIn('1 stale reference(s)', output)


if __name__ == '__main__':
    unittest.main()
