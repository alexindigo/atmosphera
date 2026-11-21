#!/usr/bin/env python3
"""Git/index ownership contracts for both staged-format hook entry points."""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class StagedFormatting(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='staged-format-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.git('init', '-q')
        (self.root / 'Scripts/dev').mkdir(parents=True)
        (self.root / 'Scripts/dev/qml-format-staged.sh').write_bytes((ROOT / 'Scripts/dev/qml-format-staged.sh').read_bytes())
        (self.root / '.devcontainer').mkdir()
        launcher = self.root / '.devcontainer/container-run.sh'
        launcher.write_text('#!/usr/bin/env python3\nimport sys\nfrom pathlib import Path\n'
                            'assert sys.argv[1:3] == ["--plain", ".devcontainer/precommit-check.sh"]\n'
                            'for name in sys.argv[3:]:\n'
                            ' p = Path(name); p.write_text(p.read_text() + "// formatted\\n")\n')
        launcher.chmod(0o755)
        (self.root / 'Old Name.qml').write_text('import QtQuick\nItem {}\n')
        (self.root / 'README.md').write_text('original\n')
        self.git('add', '.')
        tree = self.git('write-tree').strip()
        # Synthetic local object for rename detection, not a delivered commit.
        commit = self.git('hash-object', '-t', 'commit', '-w', '--stdin', input=(
            f'tree {tree}\nauthor Fixture <fixture@example.test> 1 +0000\n'
            'committer Fixture <fixture@example.test> 1 +0000\n\nfixture\n')).strip()
        self.git('update-ref', 'HEAD', commit)

    def git(self, *args, **kwargs):
        return subprocess.run(['git', *args], cwd=self.root, check=True,
                              capture_output=True, text=True, timeout=15, **kwargs).stdout

    def format(self, optional=False):
        if optional:
            text = (ROOT / 'lefthook.yml').read_text()
            command = re.search(r'    - name: format qml\n      run: ([^\n]+)', text).group(1)
            argv = ['sh', '-c', command]
        else:
            argv = ['bash', 'Scripts/dev/qml-format-staged.sh']
        subprocess.run(argv, cwd=self.root, check=True, capture_output=True, timeout=15)

    def test_both_entries_preserve_unrelated_partial_index(self):
        for optional in (False, True):
            with self.subTest(optional=optional):
                readme = self.root / 'README.md'
                readme.write_text('staged\n')
                self.git('add', 'README.md')
                readme.write_text('staged\nunstaged\n')
                for name in ('One Space.qml', 'Two\nLines.qml'):
                    (self.root / name).write_text('import QtQuick\nItem {}\n')
                    self.git('add', name)
                self.format(optional)
                self.assertEqual(self.git('show', ':README.md'), 'staged\n')
                self.assertEqual(readme.read_text(), 'staged\nunstaged\n')
                for name in ('One Space.qml', 'Two\nLines.qml'):
                    self.assertTrue(self.git('show', ':' + name).endswith('// formatted\n'))

    def test_renamed_qml_is_formatted(self):
        self.git('mv', 'Old Name.qml', 'New Name.qml')
        self.assertTrue(self.git('diff', '--cached', '--name-status').startswith('R'))
        self.format()
        self.assertTrue(self.git('show', ':New Name.qml').endswith('// formatted\n'))

    def test_no_qml_is_a_noop(self):
        self.format(optional=True)
        self.assertEqual(self.git('diff', '--cached', '--name-only'), '')


if __name__ == '__main__':
    unittest.main()
