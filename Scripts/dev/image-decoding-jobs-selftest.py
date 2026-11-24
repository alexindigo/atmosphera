#!/usr/bin/env python3
"""Exercise durable image-job ownership and manager failure transitions."""
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import image_decoding_jobs as jobs


class JobTests(unittest.TestCase):
    def test_account_scope(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            a, b = home / 'journal-a', home / 'journal-b'
            a.mkdir()
            b.mkdir()
            pa = SimpleNamespace(home=home, uid=os.getuid(), journal_base=a)
            pb = SimpleNamespace(home=home, uid=os.getuid(), journal_base=b)
            linger = 'no'

            def login(argv, **_kwargs):
                nonlocal linger
                if 'enable-linger' in argv:
                    linger = 'yes'
                elif 'disable-linger' in argv:
                    linger = 'no'
                return SimpleNamespace(stdout=linger + '\n')

            with patch.object(jobs.subprocess, 'run', side_effect=login):
                self.assertEqual(jobs.linger_lease(pa, 'image-decoding-a', a, True), 'no')
                self.assertEqual(jobs.linger_lease(pb, 'image-decoding-b', b, True), 'no')
                jobs.linger_lease(pa, 'image-decoding-a', a, False)
                self.assertEqual(linger, 'yes')
                jobs.linger_lease(pb, 'image-decoding-b', b, False)
                self.assertEqual(linger, 'no')

    def launch_case(self, failure, observed, expected):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            profile = SimpleNamespace(home=base, uid=os.getuid(), journal_base=base, work_base=base)
            args = SimpleNamespace(job_control=None, case='plugins', output=base / 'results',
                                   work_root=base / 'work', source=base)
            control = base / 'results.control'
            phases = iter(observed)
            linger = 'no'

            def systemd(argv, **_kwargs):
                nonlocal linger
                if argv[0] == 'systemd-run':
                    if failure is not None:
                        raise failure
                elif argv[0] == 'systemctl':
                    return SimpleNamespace(stdout=next(phases) + '\n')
                elif 'enable-linger' in argv:
                    linger = 'yes'
                elif 'disable-linger' in argv:
                    linger = 'no'
                return SimpleNamespace(stdout=linger + '\n', stderr='', returncode=0)

            with (patch.object(jobs.subprocess, 'run', side_effect=systemd),
                  patch.object(jobs, 'identity', return_value={'inputs': {}}),
                  patch.object(jobs.time, 'sleep') as wait):
                with self.assertRaisesRegex((OSError, RuntimeError, subprocess.TimeoutExpired), expected):
                    jobs.supervise(args, profile)
                self.assertEqual(linger, 'no')
                self.assertFalse((control / 'exit.json').exists(), 'infrastructure failure must not look like an orderly exit')
                return wait.call_count

    def test_unstarted_launch(self):
        self.launch_case(FileNotFoundError('missing client'), ['inactive'], 'missing client')

    def test_terminal_worker_without_receipt(self):
        self.launch_case(None, ['failed'], 'without an exit receipt')

    def test_timed_out_client_can_have_started_unit(self):
        waited = self.launch_case(subprocess.TimeoutExpired('systemd-run', 30), ['active', 'active', 'failed'],
                                  'without an exit receipt')
        self.assertGreaterEqual(waited, 1)


if __name__ == '__main__':
    unittest.main()
