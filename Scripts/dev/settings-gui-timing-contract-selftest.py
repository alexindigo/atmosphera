#!/usr/bin/env python3
"""Clock and input-credential controls; run only in the assigned project VM."""
import ast
import os
from pathlib import Path
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


if __name__ == '__main__':
    unittest.main(verbosity=2)
