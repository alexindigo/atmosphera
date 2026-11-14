#!/usr/bin/env python3
"""Check runner subprocess boundaries with relative and absolute CLI paths."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'Scripts/dev' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class BoundaryObserved(Exception):
    pass


class RunnerPaths(unittest.TestCase):
    def test_plugin_runners(self):
        for runner in ('plugin-settings-schema-regression', 'plugin-settings-contract-regression'):
            for relative in (True, False):
                with self.subTest(runner=runner, relative=relative), tempfile.TemporaryDirectory() as temporary:
                    root = Path(temporary)
                    cli_root = Path(os.path.relpath(root)) if relative else root
                    current = root / 'plugins/hello-world/manifest.json'
                    old = root / 'frozen/hello-world/manifest.json'
                    for path in (current, old):
                        path.parent.mkdir(parents=True)
                    manifest = {'id': 'hello-world', 'version': '1.2.6', 'metadata': {
                        'defaultSettings': {'message': 'Hello World', 'iconColor': 'primary'},
                        'settingsSchema': {'version': 1, 'fields': {
                            'message': {'type': 'String'}, 'iconColor': {'type': 'String'}}}}}
                    current.write_text(json.dumps(manifest))
                    old.write_text(json.dumps({'id': 'hello-world', 'version': '1.2.5',
                                               'metadata': {'defaultSettings': manifest['metadata']['defaultSettings']}}))
                    args = ['runner', '--output', str(cli_root / 'output'), '--work-root', str(cli_root / 'work')]
                    if runner == 'plugin-settings-schema-regression':
                        args += ['--manifest', str(cli_root / 'plugins/hello-world/manifest.json'),
                                 '--old-manifest', str(cli_root / 'frozen/hello-world/manifest.json')]
                    else:
                        args += ['--plugins', str(cli_root / 'plugins'), '--frozen-plugins', str(cli_root / 'frozen')]

                    def observe(argv, *, cwd, env, **kwargs):
                        # The OS resolves these after chdir(cwd), not in the
                        # invoking runner's original working directory.
                        fixture = Path(argv[argv.index('-p') + 1])
                        self.assertTrue(fixture.is_absolute(), str(fixture))
                        self.assertTrue(fixture.is_file())
                        self.assertTrue(Path(cwd).is_absolute())
                        self.assertTrue(Path(env['XDG_RUNTIME_DIR']).is_absolute())
                        for key in ('SCHEMA_LEGACY', 'SCHEMA_USER', 'CONTRACT_LEGACY', 'CONTRACT_USER'):
                            if key in env:
                                self.assertTrue(Path(env[key]).is_absolute(), key)
                        raise BoundaryObserved

                    module = load(runner)
                    with patch.object(sys, 'argv', args), patch.object(module.subprocess, 'run', observe):
                        with self.assertRaises(BoundaryObserved):
                            module.main()

    def test_contract_root(self):
        module = load('settings-contract-check')
        for relative in (True, False):
            root = Path(os.path.relpath(ROOT)) if relative else ROOT

            def observe(argv, *, cwd, **kwargs):
                self.assertTrue(Path(cwd).is_absolute())
                script = Path(argv[2])
                self.assertTrue(script.is_absolute())
                self.assertTrue(script.is_file())
                return type('Result', (), {'returncode': 0})()

            with self.subTest(relative=relative), patch.object(module.subprocess, 'run', observe):
                self.assertEqual(module.check(root), 0)


if __name__ == '__main__':
    unittest.main()
