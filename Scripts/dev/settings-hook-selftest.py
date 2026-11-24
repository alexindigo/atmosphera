#!/usr/bin/env python3
"""Keep fast commit sanity separate from the complete, bounded CI suite."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('contracts', Path(__file__).with_name('settings-contract-check.py'))
contracts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contracts)


class HookSplit(unittest.TestCase):
    def test_quick_is_sanity_only(self):
        self.assertEqual([name for name, _ in contracts.QUICK_CHECKS], [
            'build-settings-schema.py', 'build-settings-search-index.py',
            'builtin-plugin-settings-check.py'])
        with patch.object(contracts, 'run_command', return_value=0) as run:
            self.assertEqual(contracts.check(contracts.ROOT, quick=True), 0)
        self.assertEqual(run.call_count, 3)
        self.assertTrue(all(call.args[2] == 10 for call in run.call_args_list))

    def test_full_keeps_every_original_check(self):
        required = {name for name, _ in contracts.QUICK_CHECKS} | {
            'check-settings-writes.py', 'settings-schema-selftest.py',
            'settings-formatter-selftest.py', 'settings-writes-selftest.py', 'settings-writes-parallel-selftest.py',
            'settings-staged-selftest.py', 'settings-runner-paths-selftest.py'}
        with patch.object(contracts, 'run_command', return_value=0) as run:
            self.assertEqual(contracts.check(contracts.ROOT), 0)
        observed = {Path(call.args[0][2]).name: call.args[2] for call in run.call_args_list}
        self.assertTrue(required <= observed.keys())
        self.assertEqual(observed['check-settings-writes.py'], 300)
        self.assertTrue(all(0 < deadline <= 300 for deadline in observed.values()))

    def test_each_sanity_failure_blocks(self):
        for index in range(len(contracts.QUICK_CHECKS)):
            with self.subTest(index=index), patch.object(contracts, 'run_command', side_effect=[0] * index + [7]) as run:
                self.assertEqual(contracts.check(contracts.ROOT, quick=True), 7)
                self.assertEqual(run.call_count, index + 1)

    def test_timeout_blocks(self):
        with patch.object(contracts, 'run_command', side_effect=subprocess.TimeoutExpired('check', 10)):
            self.assertEqual(contracts.check(contracts.ROOT, quick=True), 1)

    def test_staged_preserves_mode(self):
        for quick in (False, True):
            with self.subTest(quick=quick), tempfile.TemporaryDirectory() as temporary:
                argv = ['contracts', '--root', temporary, '--staged'] + (['--quick'] if quick else [])
                with patch.object(sys, 'argv', argv), patch.object(contracts, 'staged_snapshot', return_value='tree'), \
                        patch.object(contracts.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as run:
                    self.assertEqual(contracts.main(), 0)
                self.assertEqual('--quick' in run.call_args.args[0], quick)
                self.assertEqual(run.call_args.kwargs['timeout'], 60 if quick else 600)


if __name__ == '__main__':
    unittest.main()
