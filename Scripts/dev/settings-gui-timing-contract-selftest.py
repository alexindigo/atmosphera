#!/usr/bin/env python3
"""Clock and input-credential controls; run only in the assigned project VM."""
import ast
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from types import SimpleNamespace
import unittest

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


if __name__ == '__main__':
    unittest.main(verbosity=2)
