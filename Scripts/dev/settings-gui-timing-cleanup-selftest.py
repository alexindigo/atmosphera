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
import threading
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from workspace_guard import require_disk_backed_paths

HERE = Path(__file__).resolve().parent


class CleanupTests(unittest.TestCase):
    def run_cleanup(self, *, observer_failure=False, capture_failure=False, scheduler_failure=False, ipc_failure=False, term_resistant=False, receipt_delay=False, partial_receipt=False):
        require_disk_backed_paths(os.environ['TMPDIR'])
        tree = ast.parse((HERE / 'settings-gui-timing.py').read_text())
        main = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'main')
        stop = next(n for n in main.body if isinstance(n, ast.FunctionDef) and n.name == 'stop')
        final = next(n.finalbody for n in main.body if isinstance(n, ast.Try) and n.finalbody)
        # Bind the extracted closures' actual cells, not a stale handwritten
        # subset. New owned resources must still have an explicit test double.
        captures = sorted({name for node in ast.walk(ast.Module(body=[stop, *final], type_ignores=[]))
                           if isinstance(node, ast.Nonlocal) for name in node.names})
        function = ast.parse('def invoke(result, '+', '.join(captures)+'):\n    pass\n').body[0]
        function.body = [stop, *final, ast.parse('return result').body[0]]
        functions = [n for n in tree.body if isinstance(n, ast.FunctionDef) and
                     n.name in ('cleanup_steps', 'require_shell_settled')]
        compiled = compile(ast.fix_missing_locations(ast.Module(body=[*functions, function], type_ignores=[])),
                           'actual-timing-cleanup', 'exec')
        events = []
        partial_seen = threading.Event()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            out = root / 'out'; out.mkdir()
            work = root / 'work'; work.mkdir()
            runtime = root / 'runtime'; runtime.mkdir()
            restore = root / 'config.kdl'; restore.write_text('original config')
            ready, release = root / 'ready', root / 'release'
            script = ('import pathlib,signal,sys,time;'
                      'signal.signal(signal.SIGTERM,signal.SIG_IGN);'
                      'pathlib.Path(sys.argv[1]).touch();'
                      'exec("while not pathlib.Path(sys.argv[2]).exists(): time.sleep(.01)")')
            releaser = None
            child = subprocess.Popen([sys.executable, '-B', '-c', script, str(ready), str(release)] if term_resistant else
                                     [sys.executable, '-B', '-c', 'import time;time.sleep(60)'],
                                     start_new_session=True)
            try:
                if term_resistant:
                    deadline = time.monotonic() + 5
                    while not ready.exists() and time.monotonic() < deadline:
                        time.sleep(.01)
                    self.assertTrue(ready.exists(), 'TERM-resistant child did not arm')
                    # Observe the actual waiting state before cooperative release;
                    # scheduler delay and a partial receipt cannot release early.
                    def release_after_observation():
                        try:
                            deadline = time.monotonic() + 5
                            while time.monotonic() < deadline:
                                try:
                                    pending = json.loads((out / 'result.json').read_text())
                                except (OSError, ValueError) as error:
                                    if partial_receipt and isinstance(error, ValueError):
                                        partial_seen.set()
                                    time.sleep(.05)
                                    continue
                                if (pending['status'] == 'FAIL' and pending.get('settlement', {}).get('state') ==
                                        'waiting-after-term-deadline' and runtime.exists() and child.poll() is None):
                                    events.append('waiting-state-preserves-live-dependencies')
                                    break
                                time.sleep(.05)
                        finally:
                            release.touch()
                    releaser = threading.Thread(target=release_after_observation)
                    releaser.start()

                class Child:
                    pid = child.pid

                    def poll(self):
                        return child.poll()

                    def wait(self, timeout=None):
                        if receipt_delay and timeout == 20:
                            time.sleep(1)
                        return child.wait(timeout=min(timeout, .1) if timeout is not None else 5)

                    @property
                    def returncode(self):
                        return child.returncode

                class Capture:
                    def finish(self):
                        events.append('capture')
                        if child.poll() is None:
                            events.append('capture-before-settlement')
                        if capture_failure:
                            raise OSError('injected console collector failure')
                        return {'bytes': 0}

                class Log:
                    def close(self):
                        events.append('observer-log-closed')

                class Scheduler:
                    finished = False

                    def __init__(self):
                        self.process = SimpleNamespace(poll=lambda: 0 if self.finished else None)

                    def finish(self):
                        events.append('scheduler-capture')
                        if child.poll() is None:
                            events.append('scheduler-before-settlement')
                        self.finished = True
                        if scheduler_failure:
                            raise OSError('injected scheduler collector failure')

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
                    if 'load-config-file' in argv and child.poll() is None:
                        events.append('restore-before-settlement')
                    return SimpleNamespace(stdout=b'not-found', returncode=0)

                profile = SimpleNamespace(session_environment=lambda: {},
                                          console=SimpleNamespace(verify=lambda: events.append('console-verified')))
                def write_json(path, value):
                    if partial_receipt and value.get('settlement', {}).get('state') == 'waiting-after-term-deadline':
                        path.write_text('{')
                        self.assertTrue(partial_seen.wait(timeout=2), 'observer did not tolerate partial receipt')
                    path.write_text(json.dumps(value))

                scope = dict(Path=Path, hashlib=hashlib, shutil=shutil, os=os, signal=signal,
                             subprocess=subprocess, ipc=ipc, command=command, out=out, work=work,
                             private_runtime=runtime, profile=profile, env={}, restore_config=restore,
                             restore_hash=hashlib.sha256(restore.read_bytes()).hexdigest(),
                             input_started=True, input_unit='owned-input-selftest', observer=observer,
                             observer_log=Log(), profiler=None, profiler_log=None, typing_process=None,
                             write_json=write_json)
                exec(compiled, scope)
                bindings = dict(process=Child(), log=Capture(), scheduler_capture=Scheduler())
                self.assertFalse(set(captures)-bindings.keys(), 'new cleanup capture needs an explicit owned-resource double')
                result = scope['invoke'](dict(status='PASS', checks={}, errors=[], windows=[]),
                                         **{name: bindings[name] for name in captures})
                self.assertIsNotNone(child.poll(), 'owned shell child survived diagnostic failure')
                self.assertNotIn('capture-before-settlement', events)
                self.assertNotIn('restore-before-settlement', events)
                self.assertNotIn('scheduler-before-settlement', events)
                self.assertEqual(events.count('scheduler-capture'), 1)
                if term_resistant:
                    self.assertIn('waiting-state-preserves-live-dependencies', events)
                if partial_receipt:
                    self.assertTrue(partial_seen.is_set())
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
                release.touch()
                if releaser and releaser.ident is not None:
                    releaser.join(timeout=6)
                if child.poll() is None:
                    child.terminate()
                child.wait(timeout=5)
                if releaser:
                    self.assertFalse(releaser.is_alive(), 'owned settlement observer did not finish')

    def test_observer_failure_cannot_skip_owned_cleanup(self):
        self.run_cleanup(observer_failure=True)

    def test_capture_failure_cannot_skip_restoration(self):
        self.run_cleanup(capture_failure=True)

    def test_scheduler_capture_failure_cannot_skip_restoration(self):
        result = self.run_cleanup(scheduler_failure=True)
        self.assertIn('scheduler collector failure', str(result['errors']))

    def test_ipc_failure_still_settles_owned_child(self):
        self.run_cleanup(ipc_failure=True)

    def test_independent_errors_are_all_retained(self):
        result = self.run_cleanup(observer_failure=True, capture_failure=True)
        self.assertIn('observer', str(result['errors']))
        self.assertIn('collector', str(result['errors']))

    def test_term_timeout_retains_dependencies_until_owned_child_releases(self):
        result = self.run_cleanup(term_resistant=True)
        self.assertTrue(result['checks']['shellSettled'])
        self.assertIn('TERM settlement deadline', str(result['errors']))

    def test_delayed_settlement_receipt_is_observed_before_child_release(self):
        result = self.run_cleanup(term_resistant=True, receipt_delay=True)
        self.assertTrue(result['checks']['shellSettled'])
        self.assertIn('TERM settlement deadline', str(result['errors']))

    def test_partial_settlement_receipt_is_retried_before_child_release(self):
        result = self.run_cleanup(term_resistant=True, partial_receipt=True)
        self.assertTrue(result['checks']['shellSettled'])

    def setup_failure_settles_child(self, mode):
        children = []
        launch = subprocess.Popen
        original_assert = self.assertTrue

        def capture(*args, **kwargs):
            child = launch(*args, **kwargs)
            children.append(child)
            return child

        def readiness(value, msg=None):
            if msg == 'TERM-resistant child did not arm':
                raise AssertionError('injected readiness failure')
            return original_assert(value, msg)

        try:
            with patch.object(subprocess, 'Popen', capture):
                if mode == 'readiness':
                    with patch.object(self, 'assertTrue', readiness), self.assertRaisesRegex(AssertionError, 'injected readiness'):
                        self.run_cleanup(term_resistant=True)
                else:
                    with patch.object(threading.Thread, 'start', side_effect=RuntimeError('injected observer start')), \
                            self.assertRaisesRegex(RuntimeError, 'injected observer start'):
                        self.run_cleanup(term_resistant=True)
            self.assertEqual(len(children), 1)
            self.assertIsNotNone(children[0].poll(), 'setup failure stranded its owned TERM-resistant child')
        finally:
            # Never strand the synthetic red's child. This is not the cleanup
            # under test and runs only after its settlement assertion above.
            for child in children:
                if child.poll() is None:
                    child.kill()
                child.wait(timeout=5)

    def test_readiness_failure_settles_owned_child(self):
        self.setup_failure_settles_child('readiness')

    def test_observer_start_failure_settles_owned_child(self):
        self.setup_failure_settles_child('observer-start')


if __name__ == '__main__':
    unittest.main(verbosity=2)
