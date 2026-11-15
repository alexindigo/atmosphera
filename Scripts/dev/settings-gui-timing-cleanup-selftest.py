#!/usr/bin/env python3
"""Failure-first teardown controls; run only inside the assigned project VM."""
import ast
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest

from workspace_guard import require_disk_backed_paths

HERE = Path(__file__).resolve().parent


class CleanupTests(unittest.TestCase):
    def run_cleanup(self, *, observer_failure=False, capture_failure=False, ipc_failure=False):
        require_disk_backed_paths(os.environ['TMPDIR'])
        tree = ast.parse((HERE / 'settings-gui-timing.py').read_text())
        main = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'main')
        stop = next(n for n in main.body if isinstance(n, ast.FunctionDef) and n.name == 'stop')
        final = next(n.finalbody for n in main.body if isinstance(n, ast.Try) and n.finalbody)
        function = ast.parse('def invoke(process, log, result):\n    pass\n').body[0]
        function.body = [stop, *final, ast.parse('return result').body[0]]
        functions = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'cleanup_steps']
        compiled = compile(ast.fix_missing_locations(ast.Module(body=[*functions, function], type_ignores=[])),
                           'actual-timing-cleanup', 'exec')
        events = []
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            out = root / 'out'; out.mkdir()
            work = root / 'work'; work.mkdir()
            runtime = root / 'runtime'; runtime.mkdir()
            restore = root / 'config.kdl'; restore.write_text('original config')
            child = subprocess.Popen([sys.executable, '-B', '-c', 'import time;time.sleep(60)'],
                                     start_new_session=True)

            class Child:
                pid = child.pid

                def poll(self):
                    return child.poll()

                def wait(self, timeout):
                    return child.wait(timeout=min(timeout, .1))

                @property
                def returncode(self):
                    return child.returncode

            class Capture:
                def finish(self):
                    events.append('capture')
                    if capture_failure:
                        raise OSError('injected console collector failure')
                    return {'bytes': 0}

            class Log:
                def close(self):
                    events.append('observer-log-closed')

            observer = SimpleNamespace(wait=lambda timeout: events.append('observer-wait'),
                                       returncode=1 if observer_failure else 0,
                                       stderr=io.BytesIO(b'injected observer failure'))

            def ipc(*args, **kwargs):
                events.append('shell-quit')
                if ipc_failure:
                    raise OSError('injected IPC transport failure')
                child.terminate()

            def command(argv, *args, **kwargs):
                events.append(' '.join(map(str, argv)))
                return SimpleNamespace(stdout=b'not-found', returncode=0)

            profile = SimpleNamespace(session_environment=lambda: {},
                                      console=SimpleNamespace(verify=lambda: events.append('console-verified')))
            scope = dict(Path=Path, hashlib=hashlib, shutil=shutil, os=os, signal=signal,
                         subprocess=subprocess, ipc=ipc, command=command, out=out, work=work,
                         private_runtime=runtime, profile=profile, env={}, restore_config=restore,
                         restore_hash=hashlib.sha256(restore.read_bytes()).hexdigest(),
                         input_started=True, input_unit='owned-input-selftest', observer=observer,
                         observer_log=Log(), profiler=None, profiler_log=None, typing_process=None,
                         write_json=lambda path, value: path.write_text(json.dumps(value)))
            try:
                exec(compiled, scope)
                result = scope['invoke'](Child(), Capture(), dict(status='PASS', checks={}, errors=[], windows=[]))
                self.assertIsNotNone(child.poll(), 'owned shell child survived diagnostic failure')
                self.assertFalse(runtime.exists(), 'private runtime was not retired')
                self.assertIn('niri msg action load-config-file --path ' + str(restore), events)
                self.assertIn('sudo -n systemctl stop owned-input-selftest', events)
                self.assertIn('observer-log-closed', events)
                self.assertEqual(json.loads((out / 'result.json').read_text())['status'], 'FAIL')
                self.assertEqual(result['status'], 'FAIL')
                self.assertTrue(result['errors'])
                self.assertTrue(result['checks']['niriConfigRestored'])
                self.assertTrue(result['checks']['cleanup'])
                return result
            finally:
                if child.poll() is None:
                    child.terminate()
                child.wait(timeout=5)

    def test_observer_failure_cannot_skip_owned_cleanup(self):
        self.run_cleanup(observer_failure=True)

    def test_capture_failure_cannot_skip_restoration(self):
        self.run_cleanup(capture_failure=True)

    def test_ipc_failure_still_settles_owned_child(self):
        self.run_cleanup(ipc_failure=True)

    def test_independent_errors_are_all_retained(self):
        result = self.run_cleanup(observer_failure=True, capture_failure=True)
        self.assertIn('observer', str(result['errors']))
        self.assertIn('collector', str(result['errors']))


if __name__ == '__main__':
    unittest.main(verbosity=2)
