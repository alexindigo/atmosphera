#!/usr/bin/env python3
"""Mutation controls for the migration regression's execution receipts (VM only)."""
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('migration_regression', Path(__file__).with_name('hot-corners-migration-regression.py'))
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)


class OracleTests(unittest.TestCase):
    def test_planner_nonzero_after_all_markers(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            _, expected = M.plan_cases()
            lines = []
            for name, value in expected.items():
                value = dict(value, warnings=['warning'] * value['warnings'])
                lines.append('HOT_CORNERS_PLAN|' + name + '|' + json.dumps(value))
            lines.append('HOT_CORNERS_PLAN_DONE')
            result = SimpleNamespace(stdout='\n'.join(lines), stderr='', returncode=7)
            with patch.object(M.subprocess, 'run', return_value=result):
                rows = M.run_planner(Path(__file__).resolve().parents[2], work, {})
            completion = next(row for row in rows if row['case'] == 'planner:completed')
            self.assertFalse(completion['passed'], 'nonzero qs exit was certified')

    def test_each_cold_start_checks_cleanup(self):
        def start(profile, shell, env):
            return dict(state={'corners': dict(M.EMPTY, delayMs=200), 'loaded': []}, text='', errors=[],
                        execution=dict(exit_code=0, timed_out=False, cleanup_complete=False))
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(M.Profile, 'start', start):
                rows = M.cold_starts(Path(directory), Path(directory), {})
            cleanup = [row for row in rows if row['case'].endswith(':namespace cleanup')]
            self.assertEqual(len(cleanup), 12, 'not every profile start records teardown')
            self.assertTrue(all(not row['passed'] for row in cleanup))

    def test_aggregate_does_not_invent_cleanup(self):
        def cold(shell, work, env, executions=None):
            if executions is not None:
                executions.append(dict(exit_code=0, timed_out=False, cleanup_complete=False))
            return [dict(case='controlled consumer', observed=True, expected=True, passed=True)]
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'source'
            source.mkdir()
            (source / 'shell.qml').write_text('import QtQuick\nItem {}')
            work = Path(directory) / 'run'
            with patch('sys.argv', ['proof', '--source', str(source), '--workspace', str(work)]), \
                 patch.object(M, 'check_execution_paths'), patch.object(M, 'probe_owner_path', return_value=source / 'shell.qml'), \
                 patch.object(M, 'inject_probe', side_effect=lambda text, probe: text), \
                 patch.object(M, 'run_planner', return_value=[]), patch.object(M, 'cold_starts', side_effect=cold):
                status = M.main()
            receipt = json.loads((work / 'result.json').read_text())
            self.assertFalse(receipt['execution']['cleanup_complete'], 'aggregate forged cleanup')
            self.assertFalse(receipt['passed'])
            self.assertNotEqual(status, 0)


if __name__ == '__main__':
    unittest.main()
