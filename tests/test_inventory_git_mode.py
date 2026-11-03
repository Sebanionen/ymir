"""Run the real generator against a small Git index with divergent host modes."""
import csv
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class InventoryGitModeTest(unittest.TestCase):
    @unittest.skipUnless(shutil.which('bash') and shutil.which('git'), 'requires Bash and Git')
    def test_git_modes_and_whitespace_paths_survive_host_permission_variance(self):
        with tempfile.TemporaryDirectory(prefix='inventory-mode-') as temporary:
            root = Path(temporary)
            for name in ('.pi', 'RULES', 'bin/gates', '.agents/backend'):
                (root/name).mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT/'bin/gates/inventory.sh', root/'bin/gates/inventory.sh')
            files = {
                'bin/README.md': '# Initial inventory.\n',
                '.agents/backend/README.md': '# Initial backend.\n',
                'bin/tool.sh': '# Actual tool.\n',
                'bin/data.md': '# Ordinary data.\n',
                'bin/A-upper.md': '# Upper case.\n',
                'bin/a-lower.md': '# Lower case.\n',
                'bin/reference with spaces.md': '# Space filename.\n',
            }
            if os.name != 'nt':
                files['bin/reference\twith\nwhitespace.md'] = '# Unusual filename.\n'
            for name, text in files.items():
                (root/name).write_text(text)
            def git(*args):
                subprocess.run(['git', *args], cwd=root, check=True, capture_output=True)
            git('init', '-q')
            git('add', '--', '.')
            git('update-index', '--chmod=-x', '--', *files, 'bin/gates/inventory.sh')
            git('update-index', '--chmod=+x', '--', 'bin/tool.sh')
            def render():
                subprocess.run(['bash', 'bin/gates/inventory.sh'], cwd=root, check=True, capture_output=True)
                return tuple((root/p).read_bytes() for p in ('bin/README.md', '.agents/backend/README.md'))
            # Invert real filesystem permissions without changing the Git index.
            for name in files:
                (root/name).chmod(0o755)
            (root/'bin/tool.sh').chmod(0o644)
            render()  # settle the output's own header, which is inventoried too
            first = render()
            rows = {}
            for line in first[0].decode().splitlines():
                if line.startswith('  "'):
                    row = next(csv.reader([line.strip()]))
                    rows[row[0]] = row
            self.assertEqual(rows['tool.sh'][2], 'tool')
            self.assertLess(list(rows).index('A-upper.md'), list(rows).index('a-lower.md'))
            for name in ('README.md', 'data.md', 'reference with spaces.md'):
                self.assertEqual(rows[name][2], 'data')
            if os.name != 'nt':
                self.assertEqual(rows['reference\twith whitespace.md'][2], 'data')
            for name in files:
                (root/name).chmod(0o644)
            (root/'bin/tool.sh').chmod(0o755)
            self.assertEqual(first, render())
            subprocess.run(['bash', 'bin/gates/inventory.sh', '--check'], cwd=root, check=True, capture_output=True)


if __name__ == '__main__':
    unittest.main()
