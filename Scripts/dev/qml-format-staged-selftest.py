#!/usr/bin/env python3
"""Git/index ownership contracts for both staged-format hook entry points."""
from pathlib import Path
import importlib.util
import re
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

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

    def test_literal_paths_do_not_stage_untracked_matches(self):
        (self.root / 'View*.qml').write_text('import QtQuick\nItem {}\n')
        self.git('--literal-pathspecs', 'add', 'View*.qml')
        (self.root / 'ViewDraft.qml').write_text('import QtQuick\nItem {}\n')
        self.format()
        self.assertNotIn('ViewDraft.qml', self.git('diff', '--cached', '--name-only'))

    def test_real_formatter_preserves_newline_paths(self):
        path = self.root / 'Two\nLines.qml'
        path.write_text('import QtQuick\nItem{width:1}\n')
        subprocess.run(['bash', str(ROOT / 'Scripts/dev/qmlfmt.sh'), str(path)],
                       cwd=self.root, check=True, capture_output=True, timeout=15)
        self.assertIn('width: 1', path.read_text())

    def test_profile_exec_requires_success_and_a_format_delta(self):
        spec = importlib.util.spec_from_file_location('integration', ROOT / '.devcontainer/tests/integration.py')
        integration = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(integration)
        target = self.root / '.devcontainer/tests/fixtures/valid.qml'
        target.parent.mkdir(parents=True)
        ctx = SimpleNamespace(repo=self.root, engine='podman', log_file=lambda *args: None)
        for status, formatted, expected in ((0, True, True), (1, True, False), (0, False, False)):
            with self.subTest(status=status, formatted=formatted):
                target.write_text(integration.VALID_QML)

                def execute(command):
                    if formatted:
                        target.write_text('import QtQuick\nItem {\n  width: 100\n  height: 50\n}\n')
                    return subprocess.CompletedProcess(command, status, b'Formatting 1 files...\nDone\n', b'')

                with patch.object(integration, 'sh', execute), patch.object(integration, 'record'):
                    self.assertEqual(integration.leg_profile_exec(ctx), expected)


if __name__ == '__main__':
    unittest.main()
