#!/usr/bin/env python3
"""Clock and input-credential controls; run only in the assigned project VM."""
import ast
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from gui_timing_scheduler import EVENTS, proven_sleeps
from workspace_guard import require_disk_backed_paths

HERE = Path(__file__).resolve().parent


class TimingContractTests(unittest.TestCase):
    def setUp(self):
        self.tree = ast.parse((HERE / 'settings-gui-timing.py').read_text())
        require_disk_backed_paths(os.environ['TMPDIR'])

    def test_wall_timed_sensitivity_retains_descheduled_control(self):
        assertion = next(n for n in ast.walk(self.tree) if isinstance(n, ast.Assert)
                         and n.msg and 'insensitive native instrument' in ast.unparse(n.msg))
        code = compile(ast.Module(body=[assertion], type_ignores=[]), 'actual-sensitivity', 'exec')
        exec(code, dict(proof={'spans': [{'wallMs': 80, 'cpuMs': 60}]}, dispatcher='control'))
        with self.assertRaises(AssertionError):
            exec(code, dict(proof={'spans': [{'wallMs': 30, 'cpuMs': 30}]}, dispatcher='control'))

    def test_socket_ownership_uses_profile_uid_and_client_gid(self):
        launch = next(n for n in ast.walk(self.tree) if isinstance(n, ast.Expr)
                      and isinstance(n.value, ast.Call) and isinstance(n.value.func, ast.Name)
                      and n.value.func.id == 'command' and '/usr/bin/ydotoold' in ast.unparse(n))
        code = compile(ast.Module(body=[launch], type_ignores=[]), 'actual-input-launch', 'exec')
        calls = []
        with tempfile.TemporaryDirectory() as temporary:
            for uid in (1000, 2001):
                exec(code, dict(command=lambda argv, env: calls.append(argv), input_unit='owned-input',
                                work=Path(temporary), env={}, profile=SimpleNamespace(uid=uid), os=os))
                self.assertIn(f'--socket-own={uid}:{os.getgid()}', calls[-1])

    def test_failed_final_noop_is_rejected(self):
        main = next(n for n in self.tree.body if isinstance(n, ast.FunctionDef) and n.name == 'main')
        loop = next(n for n in ast.walk(main) if isinstance(n, ast.For) and ast.unparse(n.target) == 'number')
        begin = next(i for i, n in enumerate(loop.body) if ast.unparse(n) == "ipc('guiTiming', 'noop')")
        end = next(i for i, n in enumerate(loop.body) if isinstance(n, ast.For) and ast.unparse(n.target) == 'section')
        actual = compile(ast.Module(body=loop.body[begin:end], type_ignores=[]), 'actual-final-noop', 'exec')
        for status in ('saved', 'nothing_to_save', 'failed'):
            scope = dict(before=0, ipc=lambda *args: None, wait_for=lambda predicate: predicate(),
                         status=lambda: {'completions': [{'status': 'saved'}, {'status': 'saved'}, {'status': status}]})
            if status == 'failed':
                with self.assertRaises(AssertionError):
                    exec(actual, scope)
            else:
                exec(actual, scope)

    def timing_module(self):
        spec = importlib.util.spec_from_file_location('actual_gui_timing', HERE / 'settings-gui-timing.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_profiled_control_refuses_before_activation_or_output(self):
        module = self.timing_module()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for flags in ([], ['--profile'], ['--expect-old-stall'], ['--profile', '--expect-old-stall']):
                with self.subTest(flags=flags):
                    argv = ['settings-gui-timing.py', '--source', str(HERE.parents[1]),
                            '--output', str(root/'out'), '--work-root', str(root/'work'),
                            '--guest-profile', str(root/'profile.json'),
                            '--restore-niri-config', str(root/'niri.kdl'), *flags]
                    stderr = io.StringIO()
                    with patch.object(sys, 'argv', argv), contextlib.redirect_stderr(stderr), \
                            patch.object(module, 'activate_profile', side_effect=RuntimeError('activation-boundary')) as activate:
                        if len(flags) == 2:
                            with self.assertRaises(SystemExit) as failure:
                                module.main()
                            self.assertEqual(failure.exception.code, 2)
                            self.assertIn('--profile', stderr.getvalue())
                            self.assertIn('--expect-old-stall', stderr.getvalue())
                            activate.assert_not_called()
                        else:
                            with self.assertRaisesRegex(RuntimeError, 'activation-boundary'):
                                module.main()
                            activate.assert_called_once()
                    self.assertFalse((root/'out').exists())
                    self.assertFalse((root/'work').exists())

    def test_heartbeat_ignores_wall_adjustments_but_observes_monotonic_delay(self):
        spec = importlib.util.spec_from_file_location('qml_identifiers', HERE/'qml-identifiers.py')
        lexer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(lexer)
        source = (HERE/'fixtures/settings-gui-timing.qml').read_text()
        _, spans = lexer.lex(source)
        masked = list(source)
        for _, start, end in spans:
            masked[start:end] = ' ' * (end-start)
        masked = ''.join(masked)

        def block(opening):
            depth = 0
            for offset in range(opening, len(masked)):
                if masked[offset] == '{':
                    depth += 1
                elif masked[offset] == '}':
                    depth -= 1
                    if depth == 0:
                        return offset + 1
            raise AssertionError('unclosed actual heartbeat block')

        starts = list(re.finditer(r'\bfunction\s+start\s*\(', masked))
        handlers = list(re.finditer(r'\bonTriggered\s*:\s*\{', masked))
        self.assertEqual(len(starts), 1)
        self.assertEqual(len(handlers), 1)
        opening = masked.index('{', starts[0].end())
        start = source[starts[0].start():block(opening)]
        opening = masked.index('{', handlers[0].start())
        tick = source[opening+1:block(opening)-1]
        # A lexical Date double avoids QML's optimized builtin Date.now calls.
        # Only QML's return annotation is erased; execute the actual JS bodies.
        actual = re.sub(r'\)\s*:\s*void\s*\{', ') {', start)
        actual += '\nfunction tick() {' + tick + '}\nreturn {start:start,tick:tick};'
        qml = '''import QtQml
QtObject {
  Component.onCompleted: {
    const clock = {monoNs: 1000000000, wallMs: 1700000000000};
    const probe = {lastTick: 0, worstLate: 0, ticks: 0, measuring: false,
      lateTicks: [], latenessDistribution: {}, nativeClock: {
        nowNs: function() { return String(clock.monoNs); }
      }};
    const actual = (new Function("probe", "Date", "interval", ACTUAL))(probe,
      {now: function() { return clock.wallMs; }}, 5);
    try {
      actual.start();
      const failures = [];
      if (probe.lastTick !== clock.monoNs/1000000) failures.push("start clock domain");
      for (const jump of [0, 5000, -7000, 15000]) {
        clock.monoNs += 5000000;
        clock.wallMs += 5 + jump;
        actual.tick();
      }
      if (probe.worstLate !== 0) failures.push("wall adjustment: " + probe.worstLate);
      clock.monoNs += 85000000;
      clock.wallMs += 5;
      probe.worstLate = 0;
      actual.tick();
      if (probe.worstLate !== 80) failures.push("monotonic delay: " + probe.worstLate);
      if (failures.length) throw new Error(failures.join("; "));
      console.log("HEARTBEAT_CLOCK: PASS");
      Qt.quit();
    } catch (error) { console.error("HEARTBEAT_CLOCK_ASSERT: " + error); Qt.exit(2); }
  }
}
'''.replace('ACTUAL', json.dumps(actual))
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)/'actual-heartbeat.qml'
            path.write_text(qml)
            result = subprocess.run(['/usr/lib/qt6/bin/qml', '-a', 'core', str(path)],
                                    env=dict(os.environ, LC_ALL='C.UTF-8', QT_FORCE_STDERR_LOGGING='1'),
                                    capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('HEARTBEAT_CLOCK: PASS', result.stdout + result.stderr)

    def test_positive_control_requires_stall_inside_save_burst(self):
        assertion = next(n for n in ast.walk(self.tree) if isinstance(n, ast.Assert)
                         and n.msg and 'old-owner positive control did not reproduce' in ast.unparse(n.msg))
        code = compile(ast.Module(body=[assertion], type_ignores=[]), 'actual-positive-control', 'exec')
        windows = [dict(id='save-burst-0', startNs=100_000_000, endNs=200_000_000)]
        module = self.timing_module()
        for start, end, accepted in ((0, 80_000_000, False), (85_000_000, 105_000_000, False),
                                     (110_000_000, 190_000_000, True)):
            spans = [dict(startNs=start, endNs=end, wallMs=(end-start)/1e6, windows=['complete-workload'])]
            scope = dict(violations=spans, native_report={'spans': spans}, result={'saveBurstWindows': windows},
                         args=SimpleNamespace(max_busy_ms=16),
                         save_burst_violations=getattr(module, 'save_burst_violations', None))
            if accepted:
                exec(code, scope)
            else:
                with self.assertRaises(AssertionError):
                    exec(code, scope)

    def test_physical_keys_must_overlap_actual_outstanding_burst(self):
        module = self.timing_module()
        check = getattr(module, 'require_input_overlap', None)
        if check is None:
            # Original actual acceptance checks only that some key was observed.
            node = next(n for n in ast.walk(self.tree) if isinstance(n, ast.Assert)
                        and ast.unparse(n.test) == 'len(raw_keys) > 0')
            actual = compile(ast.Module(body=[node], type_ignores=[]), 'actual-key-acceptance', 'exec')
            check = lambda keys, window: exec(actual, dict(raw_keys=keys))
        window = dict(startNs=100_000_000, endNs=200_000_000)
        check([dict(atNs=150_000_000, value=1)], window)
        for at in (99_999_999, 250_000_000):
            with self.assertRaises(AssertionError):
                check([dict(atNs=at, value=1)], window)

    def test_old_source_receives_runner_fixture_dependency_closure(self):
        provision = next((n for n in self.tree.body if isinstance(n, ast.FunctionDef) and
                          n.name == 'provision_timing_fixtures'), None)
        if provision:
            code = compile(ast.Module(body=[provision], type_ignores=[]), 'actual-fixture-provision', 'exec')
            scope = dict(HERE=HERE, shutil=shutil)
            exec(code, scope)
            copy_fixtures = scope['provision_timing_fixtures']
        else:
            # Execute the original actual copy boundary for the red control.
            main = next(n for n in self.tree.body if isinstance(n, ast.FunctionDef) and n.name == 'main')
            block = next(n for n in main.body if isinstance(n, ast.For) and
                         'settings-gui-timing.qml' in ast.unparse(n))
            code = compile(ast.Module(body=[block], type_ignores=[]), 'actual-fixture-provision', 'exec')
            copy_fixtures = lambda shell: exec(code, dict(HERE=HERE, shutil=shutil, shell=shell))
        with tempfile.TemporaryDirectory() as directory:
            shell = Path(directory)
            (shell / 'Scripts/dev/fixtures').mkdir(parents=True)
            copy_fixtures(shell)
            fixture = shell / 'Scripts/dev/fixtures/Migration62.qml'
            import_line = next(line for line in fixture.read_text().splitlines() if 'SettingsMigrationSource.js' in line)
            dependency = (fixture.parent / import_line.split('"')[1]).resolve()
            self.assertTrue(dependency.is_file(), 'runner-owned migration wrapper lacks its imported JS dependency on old sources')
            self.assertEqual(dependency.read_bytes(), (HERE.parents[1] / 'Commons/Migrations/SettingsMigrationSource.js').read_bytes())
            self.assertNotIn('.import ', dependency.read_text(), 'extend the runner-owned fixture closure for new JS dependencies')
            probe = shell / 'probe.qml'
            probe.write_text('''import QtQuick
import Quickshell
import "Scripts/dev/fixtures" as Fixtures
ShellRoot {
  Fixtures.Migration62 { id: migration }
  Timer { interval: 10; running: true; onTriggered: {
    const adapter = {general: {keybinds: {keyRemove: ["Del"]}}};
    migration.migrate(adapter, {i: function() {}}, {general: {keybinds: {keyRemove: ["Del"]}}});
    if (JSON.stringify(adapter.general.keybinds.keyRemove) !== '["Shift+Del"]')
      throw new Error("fixture dependency consumer mismatch");
    console.log("TIMING_FIXTURE_CLOSURE: PASS");
    Qt.quit();
  } }
}
''')
            result = subprocess.run(['qs', '-p', str(probe), '--no-color'],
                                    env=dict(os.environ, QT_QPA_PLATFORM='offscreen'),
                                    capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('TIMING_FIXTURE_CLOSURE: PASS', result.stdout + result.stderr)


class SchedulerEvidenceTests(unittest.TestCase):
    def setUp(self):
        require_disk_backed_paths(os.environ['TMPDIR'])
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.trace = Path(self.directory.name)/'native.trace'
        self.root = Path(str(self.trace)+'.scheduler')
        self.root.mkdir()
        self.lines = [
            ' qs-42 [000] ..... 1.000001: sys_poll(ufds: 0x1, nfds: 1, timeout_msecs: 0x64)',
            ' qs-42 [000] d..2. 1.000002: sched_switch: prev_comm=qs prev_pid=42 prev_prio=120 prev_state=S ==> next_comm=other next_pid=43 next_prio=120',
            ' other-43 [000] d..2. 1.030000: sched_waking: comm=qs pid=42 prio=120 target_cpu=000',
            ' other-43 [000] d..2. 1.030001: sched_wakeup: comm=qs pid=42 prio=120 target_cpu=000',
            ' other-43 [000] d..2. 1.110000: sched_switch: prev_comm=other prev_pid=43 prev_prio=120 prev_state=R ==> next_comm=qs next_pid=42 next_prio=120',
            ' qs-42 [000] ..... 1.110001: sys_poll -> 0x1',
        ]
        self.receipt = dict(status='PASS', removed=True, pid=42, clock='mono', timestampResolutionNs=1000,
                            startNs=1_000_000_000, endNs=1_200_000_000,
                            filters={name: rule.format(pid=42) for name, rule in EVENTS.items()},
                            cpuStats={'cpu0': 'entries: 6\noverrun: 0\ncommit overrun: 0\ndropped events: 0\n'})

    def analyze(self):
        (self.root/'trace').write_text('\n'.join(self.lines)+'\n')
        (self.root/'receipt.json').write_text(json.dumps(self.receipt))
        return proven_sleeps(self.trace, 42, 1_000_000_000, 1_120_000_000)

    def test_sleep_credit_ends_at_first_waking_not_switch_in(self):
        calls, sleeps, _ = self.analyze()
        self.assertEqual(calls, [dict(kind='poll', startNs=1_000_002_000, endNs=1_110_001_000)])
        self.assertEqual(sleeps, [(1_000_003_000, 1_030_000_000)])

    def test_runnable_preemption_earns_no_sleep(self):
        self.lines[1] = self.lines[1].replace('prev_state=S', 'prev_state=R+')
        self.assertEqual(self.analyze()[1], [])

    def test_waking_racing_switch_out_never_earns_idle_credit(self):
        self.lines.insert(1, ' other-43 [000] d..2. 1.000001: sched_waking: comm=qs pid=42 prio=120 target_cpu=000')
        self.receipt['cpuStats']['cpu0'] = self.receipt['cpuStats']['cpu0'].replace('entries: 6', 'entries: 7')
        self.assertEqual(self.analyze()[1], [])

    def test_loss_and_incomplete_coverage_are_rejected(self):
        original = dict(self.receipt)
        for key, value in [('status', 'FAIL'), ('removed', False), ('pid', 43), ('clock', 'local'),
                           ('startNs', 1_000_000_001), ('endNs', 1_100_000_000),
                           ('cpuStats', {'cpu0': 'entries: 6\noverrun: 1\ncommit overrun: 0\ndropped events: 0\n'}),
                           ('cpuStats', {'cpu0': 'entries: 7\noverrun: 0\ncommit overrun: 0\ndropped events: 0\n'})]:
            self.receipt = dict(original, **{key: value})
            with self.subTest(key=key, value=value), self.assertRaises(AssertionError):
                self.analyze()

    def test_missing_wake_refuses_instead_of_crediting_until_run(self):
        self.lines = [line for line in self.lines if 'sched_wak' not in line]
        self.receipt['cpuStats']['cpu0'] = self.receipt['cpuStats']['cpu0'].replace('entries: 6', 'entries: 4')
        with self.assertRaisesRegex(AssertionError, 'without a captured wake'):
            self.analyze()

    def test_unmatched_kernel_return_is_rejected(self):
        self.lines[0] = self.lines[0].replace('sys_poll(', 'sys_ppoll(')
        with self.assertRaisesRegex(AssertionError, 'unmatched kernel poll'):
            self.analyze()

    def test_unmatched_kernel_entry_is_not_accepted_as_terminal(self):
        self.lines.pop()
        self.receipt['cpuStats']['cpu0'] = self.receipt['cpuStats']['cpu0'].replace('entries: 6', 'entries: 5')
        with self.assertRaisesRegex(AssertionError, 'unmatched kernel poll'):
            self.analyze()


if __name__ == '__main__':
    unittest.main(verbosity=2)
