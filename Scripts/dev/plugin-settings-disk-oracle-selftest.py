#!/usr/bin/env python3
"""Exercise real disk oracle entry points with optimized Python."""
import json
import os
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest


class DiskOracleTests(unittest.TestCase):
    def check_oracle(self, script, prefix, observed, expected, verdict):
        with TemporaryDirectory() as tmp:
            case = Path(tmp)
            (case / 'persisted').mkdir()
            (case / 'config/settings/plugins').mkdir(parents=True)
            for file, contents in observed.items():
                path = case / file
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps(contents))
            (case / 'expectations.json').write_text(json.dumps({'edited': expected}))
            entry = Path(__file__).parent / 'fixtures' / script
            env = dict(os.environ, **{prefix + '_CASE': tmp, prefix + '_OUTPUT': tmp})
            result = subprocess.run([sys.executable, '-B', '-O', str(entry), 'edited'],
                                    env=env, text=True, capture_output=True, timeout=10)
            receipt = case / 'persisted/edited.json'
            if verdict:
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(receipt.read_text())['status'], 'PASS')
            else:
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn('edited', result.stderr)
                self.assertFalse(receipt.exists())

    def test_battery_rejects_wrong_value_under_optimization(self):
        self.battery(89, 90, False)

    def test_battery_accepts_matching_documents(self):
        self.battery(90, 90, True)

    def battery(self, actual, expected, verdict):
        self.check_oracle('plugin-settings-battery-disk.py', 'PHA_BATTERY', {
            'config/settings/plugins/battery-threshold.json': {'limit': actual},
            'config/settings/bar.json': {},
            'devices/BAT0/charge_control_end_threshold': 60,
            'devices/BAT1/charge_control_end_threshold': 70,
        }, dict(shared={'limit': expected}, bar={}, batteries={'BAT0': 60, 'BAT1': 70}), verdict)

    def test_shared_routes_rejects_boolean_number_substitution(self):
        self.shared_routes([1], [True], False)
        self.shared_routes([False], [0], False)

    def test_shared_routes_accepts_same_json_number(self):
        self.shared_routes([9.0, {'ready': True}], [9, {'ready': True}], True)

    def shared_routes(self, actual, expected, verdict):
        self.check_oracle('plugin-settings-shared-routes-disk.py', 'PHA_SHARED_ROUTE', {
            'config/bar.json': {'nested': actual},
        }, {'bar.json': {'nested': expected}}, verdict)


if __name__ == '__main__':
    unittest.main()
