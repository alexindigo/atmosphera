#!/usr/bin/env python3
"""Observe actual owned-child argv and file hashes with default/custom XDG roots."""
import hashlib
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


class RetryObserver(unittest.TestCase):
    def test_configuration_root(self):
        for value in (None, '', 'custom-config'):
            with self.subTest(xdg=value), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                home = root / 'home'
                home.mkdir()
                environment = dict(os.environ, HOME=str(home))
                environment.pop('XDG_CONFIG_HOME', None)
                if value is not None:
                    environment['XDG_CONFIG_HOME'] = str(root / value) if value else ''
                configuration = (root / value if value else home / '.config') / 'xremap/atmosphera-xremap.yml'
                configuration.parent.mkdir(parents=True)
                configuration.write_text('keymap: []\n')
                unit = root / 'source/Scripts/systemd/xremap-atmosphera.service'
                unit.parent.mkdir(parents=True)
                unit.write_text('[Service]\nExecStart=xremap fixture\n')
                child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)', str(configuration)])
                receipts, calls = [], []
                try:
                    class Runner:
                        source = root / 'source'
                        case = root / 'case'

                        def save_failure(self):
                            calls.append('original causal schedule')

                        def check(self, ok, message):
                            if not ok:
                                raise AssertionError(message)

                    def run(argv):
                        return SimpleNamespace(returncode=0, stdout='MainPID=' + str(child.pid) + '\nActiveState=active\nFragmentPath=' + str(unit))

                    def digest(path):
                        return hashlib.sha256(path.read_bytes()).hexdigest()

                    module = SimpleNamespace(Runner=Runner, run=run, sha=digest,
                                             atomic_json=lambda path, data: receipts.append(data))
                    path = Path(__file__).with_name('fixtures') / 'xremap-retry-observer.py'
                    spec = importlib.util.spec_from_file_location('retry_observer', path)
                    observer = importlib.util.module_from_spec(spec)
                    spec.loader.exec_module(observer)
                    with patch.dict(os.environ, environment, clear=True):
                        observer.attach(module)
                        module.Runner().save_failure()
                    self.assertEqual(calls, ['original causal schedule'])
                    self.assertEqual(len(receipts), 1)
                    self.assertEqual(receipts[0]['configuration'], str(configuration))
                    self.assertEqual(receipts[0]['configuration_sha256'], digest(configuration))
                    self.assertIn(str(configuration), receipts[0]['argv'])
                finally:
                    child.terminate()
                    child.wait(timeout=5)


if __name__ == '__main__':
    unittest.main()
