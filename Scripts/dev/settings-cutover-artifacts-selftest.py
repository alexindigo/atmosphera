#!/usr/bin/env python3
"""The native cutover ships no obsolete owner or test-only migration wrapper."""
import ast
from pathlib import Path
import shutil
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
OBSOLETE = ('Helpers/SettingsModel.js', 'Helpers/SettingsEditor.js',
            'Helpers/PluginSettingsEditor.js', 'Scripts/python/src/settings/plugin-settings-save.py',
            'Commons/Migrations/Migration62.qml', 'Scripts/dev/fixtures/settings-model-invariants.qml')


class CutoverArtifacts(unittest.TestCase):
    def test_obsolete_files_are_absent(self):
        self.assertEqual([name for name in OBSOLETE if (ROOT / name).exists()], [])

    def test_both_migration_consumers_use_the_test_only_wrapper(self):
        fixture = ROOT / 'Scripts/dev/fixtures/Migration62.qml'
        self.assertTrue(fixture.is_file())
        self.assertIn('../../../Commons/Migrations/SettingsMigrationSource.js', fixture.read_text())
        launcher = (ROOT / 'Scripts/dev/fixtures/launcher-key-owner-probe.qml').read_text()
        projection = (ROOT / 'Scripts/dev/fixtures/settings-migration-projection.qml').read_text()
        self.assertIn('/Scripts/dev/fixtures/Migration62.qml', launcher)
        self.assertIn('./i5-migration62.qml', projection)
        self.assertNotIn('/Commons/Migrations/Migration62.qml', launcher + projection)

    def test_timing_runner_provisions_the_wrapper_for_older_sources(self):
        timing = ROOT / 'Scripts/dev/settings-gui-timing.py'
        if not timing.exists():
            self.skipTest('timing runner belongs to the top stack')
        loop = next(node for node in ast.walk(ast.parse(timing.read_text())) if isinstance(node, ast.For)
                    and isinstance(node.iter, ast.Tuple) and 'launcher-key-owner-probe.qml' in ast.unparse(node.iter))
        with tempfile.TemporaryDirectory() as temporary:
            shell = Path(temporary)
            (shell / 'Scripts/dev/fixtures').mkdir(parents=True)
            exec(compile(ast.Module(body=[loop], type_ignores=[]), str(timing), 'exec'),
                 dict(HERE=timing.parent, shell=shell, shutil=shutil))
            wrapper = Path('Scripts/dev/fixtures/Migration62.qml')
            self.assertEqual((shell / wrapper).read_bytes(), (ROOT / wrapper).read_bytes())


if __name__ == '__main__':
    unittest.main()
