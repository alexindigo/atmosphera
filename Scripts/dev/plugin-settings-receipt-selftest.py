#!/usr/bin/env python3
"""Exercise the real teardown/survivor gates with inert fixture payloads."""
import ast
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


DEV = Path(__file__).resolve().parent


def load(member):
    source = DEV / f'plugin-settings-{member}-regression.py'
    spec = importlib.util.spec_from_file_location(member, source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ReceiptTests(unittest.TestCase):
    def test_final_result_paths_use_the_receipt_boundary(self):
        for source in sorted(DEV.glob('plugin-settings-*.py')):
            tree = ast.parse(source.read_text(), filename=str(source))
            for call in (node for node in ast.walk(tree) if isinstance(node, ast.Call)):
                operation = getattr(call.func, 'attr', getattr(call.func, 'id', ''))
                if operation not in {'write_json', 'write', 'write_text', 'open'}:
                    continue
                path = call.args[0] if operation == 'write_json' and call.args else call.func
                if operation == 'write' and len(call.args) == 2:
                    path = call.args[0]
                has_result_path = any(isinstance(node, ast.Constant) and node.value == 'result.json'
                                      for node in ast.walk(path))
                self.assertFalse(has_result_path, f'{source.name}:{call.lineno}: use stage_receipt')

    def test_owned_survivor_invalidates_receipt(self):
        for member, scenario, diagnostic in (
            ('hermes-agent', 'timers', 'owned actual helper survived'),
            ('spotify', 'instance', 'Spotify endpoint survived engine'),
        ):
            for surviving in (True, False):
                with self.subTest(member=member, surviving=surviving), tempfile.TemporaryDirectory() as temp:
                    self.prove(member, scenario, diagnostic, Path(temp), surviving)

    def prove(self, member, scenario, diagnostic, root, surviving):
        driver = load(member)
        source = root / 'shell'
        (source / 'Scripts/dev/fixtures').mkdir(parents=True)
        (source / 'shell.qml').touch()
        # Hermes fingerprints the executing driver relative to the supplied source.
        driver.__file__ = str(source / 'Scripts/dev/driver.py')
        Path(driver.__file__).touch()
        for name in ('hermes.qml', 'spotify-endpoint.py', 'spotify-disk.py'):
            (source / 'Scripts/dev/fixtures' / ('plugin-settings-' + name)).touch()
        plugin = root / 'plugins/spotify-player'
        plugin.mkdir(parents=True)
        (plugin / 'Auth.js').write_text('"https://accounts.spotify.com/api/token"\n')
        (plugin / 'callback_server.py').touch()
        work, output = root / 'work', root / 'output'
        work.mkdir(); output.mkdir()
        args = SimpleNamespace(source=source, plugins=root / 'plugins', work_root=work,
                               output=output, old_red=False, control=None, actions_only=True)
        receipt = output / scenario / 'result.json'
        case = work / scenario
        process = None
        remove_install = driver.runner.remove_completed_installs

        def cleanup(*args):
            self.assertFalse(receipt.exists(), 'verdict visible during install cleanup')
            return remove_install(*args)

        def fixture(*unused, extra_env, **kwargs):
            nonlocal process
            self.assertFalse(receipt.exists(), 'verdict visible during fixture body')
            if surviving and process is None:
                process = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)',
                                            'hermes_bridge.py', str(case)])
                pid = process.pid
                start = Path(f'/proc/{pid}/stat').read_text().split(') ', 1)[1].split()[19]
                (case / 'endpoint-pids.jsonl').write_text(json.dumps(dict(pid=pid, start=start)) + '\n')
            if member == 'hermes-agent':
                return 'HERMES_CONTRACT: PASS ' + scenario
            return 'SPOTIFY_NATIVE: PASS ' + scenario + ' ' + extra_env['PHA_SPOTIFY_MODE']

        try:
            with (patch.object(driver.runner, 'run_fixture', fixture),
                  patch.object(driver.runner, 'remove_completed_installs', cleanup)):
                if surviving:
                    with self.assertRaisesRegex((AssertionError, RuntimeError), diagnostic):
                        driver.run(args, None, scenario)
                    self.assertIsNone(process.poll(), 'survivor must still be live at adjudication')
                    status = json.loads(receipt.read_text())['status']
                    self.assertEqual(status, 'FAIL', 'live survivor must not leave a PASS receipt')
                else:
                    driver.run(args, None, scenario)
                    self.assertEqual(json.loads(receipt.read_text())['status'], 'PASS')
                    self.assertTrue((output / scenario / 'install-cleanup.json').is_file())
        finally:
            if process is not None:
                process.terminate()
                process.wait(timeout=5)


if __name__ == '__main__':
    unittest.main()
