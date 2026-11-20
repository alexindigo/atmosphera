#!/usr/bin/env python3
"""P001 consumer gate after field-only supersession. Assigned guest only."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil

from guest_profile import activate_profile, profile_argument

SPEC = importlib.util.spec_from_file_location('host_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    profile.prepare_roots()
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh paths must belong to the verified guest profile')
    injector = Path(os.environ['PHA_INPUT_INJECTOR']).resolve()
    if not injector.is_relative_to(profile.work_base) or not injector.is_file():
        parser.error('task-owned input injector required')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(exist_ok=False)
        args.output.mkdir(exist_ok=False)
        # The 14-readback field witness supersedes the interim mutable-API
        # route fixture. Keep the existing command as the P001 entry point.
        receipts = [runner.todo_case(args, profile)]
        for kind, fixture_name, marker in (
            ('shared', 'plugin-settings-p001-shared.qml', 'P001_SHARED: PASS'),):
            case, out = args.work_root / kind, args.output / kind
            case.mkdir()
            out.mkdir()
            install = case / 'install'
            shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
            shared_path, expected = runner.seed_todo(case, args.plugins)
            before = shared_path.read_bytes()
            fixture = args.source / 'Scripts/dev/fixtures' / fixture_name
            env = dict(PHA_TODO_SHARED_SHA256=hashlib.sha256(before).hexdigest())
            try:
                text = runner.run_fixture(profile, install, case, out, fixture, extra_env=env)
            finally:
                (case / 'config/settings').chmod(0o700)
            bad = ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected', 'is not installed')
            if marker not in text or any(item in text for item in bad):
                raise RuntimeError(kind + ': missing endpoint or runtime diagnostics')
            expected['pages'][1]['name'] = 'Renamed'
            expected['exportEmptySections'] = True
            if json.loads(shared_path.read_text()) != expected:
                raise RuntimeError('shared explicit-command independent readback')
            cold = out / 'cold'
            cold.mkdir()
            text = runner.run_fixture(profile, install, case, cold, fixture, extra_env=dict(env, PHA_TODO_COLD='1'))
            if 'COLD_PASS' not in text or any(item in text for item in bad):
                raise RuntimeError(kind + ': independent cold consumer failed')
            receipts.append(dict(case=kind, status='PASS', independentPersistedReadback=True, separateColdConsumer=True))
            print('P001_SAFETY ' + kind + ': PASS', flush=True)
        inputs = {str(path.relative_to(args.source)): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in [args.source / 'Services/Plugins/PluginSettingsSession.qml',
                               args.source / 'Services/Plugins/PluginSettingsPageApi.qml',
                               args.source / 'Services/UI/DesktopWidgetRegistry.qml']}
        inputs['todo/Settings.qml'] = hashlib.sha256((args.plugins / 'todo/Settings.qml').read_bytes()).hexdigest()
        runner.write_json(args.output / 'result.json', dict(status='PASS', cases=receipts, inputs=inputs,
            genuineKeyboardInput=True, intermediatePersistedReadbacks=14, realIoFailureAndRetry=True,
            protectedConfigurationReset=True, fieldOnlySupersession=True, completeCatalog=False, inputInjectorSha256=hashlib.sha256(injector.read_bytes()).hexdigest()))
        print('PLUGIN_SETTINGS_P001_SAFETY: PASS', flush=True)


if __name__ == '__main__':
    main()
