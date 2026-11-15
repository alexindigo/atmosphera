#!/usr/bin/env python3
"""Receipt/identifier failure canaries for the external-command runner (guest only)."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location('runner', Path(__file__).with_name('external-command-regression.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class HarnessTest(unittest.TestCase):
    def test_final_receipt_status(self):
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            for cleanup, timed_out, exit_code in [(False, False, 0), (True, True, 0), (True, False, 1), (True, False, 0)]:
                execution = dict(cleanup_complete=cleanup, timed_out=timed_out, exit_code=exit_code)
                passed = runner.finish_stage(work, True, execution)
                self.assertEqual(passed, cleanup and not timed_out and exit_code == 0)
                self.assertEqual(json.loads((work / 'result.json').read_text())['passed'], passed)

    def test_journal_identity(self):
        first = runner.journal_identifier(Path('/one/shared-name'))
        second = runner.journal_identifier(Path('/two/shared-name'))
        third = runner.journal_identifier(Path('/one/shared-name'))
        self.assertEqual(len({first, second, third}), 3)
        self.assertTrue(all('shared-name' in value for value in (first, second, third)))


if __name__ == '__main__':
    unittest.main()
