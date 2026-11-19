#!/usr/bin/env python3
"""The native cutover ships no obsolete owner or test-only migration wrapper."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
OBSOLETE = ('Helpers/SettingsModel.js', 'Helpers/SettingsEditor.js',
            'Helpers/PluginSettingsEditor.js', 'Scripts/python/src/settings/plugin-settings-save.py',
            'Commons/Migrations/Migration62.qml', 'Scripts/dev/fixtures/settings-model-invariants.qml',
            'Scripts/dev/fixtures/plugin-settings-editors.qml',
            'Scripts/dev/fixtures/plugin-settings-receipts.qml')


class CutoverArtifacts(unittest.TestCase):
    def test_obsolete_files_are_absent(self):
        self.assertEqual([name for name in OBSOLETE if (ROOT / name).exists()], [])

    def test_native_editor_and_receipt_witnesses_remain(self):
        for name in ('settings-plugin-editors-native.qml', 'settings-plugin-receipts-native.qml'):
            with self.subTest(fixture=name):
                self.assertTrue((ROOT / 'Scripts/dev/fixtures' / name).is_file())

    def test_both_migration_consumers_use_the_test_only_wrapper(self):
        fixture = ROOT / 'Scripts/dev/fixtures/Migration62.qml'
        self.assertTrue(fixture.is_file())
        self.assertIn('../../../Commons/Migrations/SettingsMigrationSource.js', fixture.read_text())
        launcher = (ROOT / 'Scripts/dev/fixtures/launcher-key-owner-probe.qml').read_text()
        projection = (ROOT / 'Scripts/dev/fixtures/settings-migration-projection.qml').read_text()
        self.assertIn('/Scripts/dev/fixtures/Migration62.qml', launcher)
        self.assertIn('./i5-migration62.qml', projection)
        self.assertNotIn('/Commons/Migrations/Migration62.qml', launcher + projection)


if __name__ == '__main__':
    unittest.main()
