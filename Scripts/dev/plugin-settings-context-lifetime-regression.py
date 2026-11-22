#!/usr/bin/env python3
"""Retained actual shared/placement context callbacks after API destruction."""
import argparse
import fcntl
import hashlib
import importlib.util
import os
from pathlib import Path
import shutil

from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('host_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def hashes(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob('*.json')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--original', action='store_true')
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-context-lifetime-regression.py':
        parser.error('execute supplied source')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh owned guest roots required')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(); args.output.mkdir()
        inputs = ['Services/Plugins/' + name for name in ('PluginInstanceApi.qml', 'PluginSettingsRead.js', 'Service.qml')]
        inputs += ['Scripts/dev/' + name for name in ('plugin-settings-context-lifetime-regression.py', 'fixtures/plugin-settings-context-lifetime.qml', 'plugin-settings-host-assets-regression.py', 'guest_profile.py')]
        runner.write_json(args.output / 'inputs.json', {name: hashlib.sha256((args.source / name).read_bytes()).hexdigest() for name in inputs})
        for scope in ('instance', 'shared'):
            case, out = args.work_root / scope, args.output / scope
            case.mkdir(); out.mkdir()
            for name in ('config/settings/plugins', 'cache', 'state'):
                (case / name).mkdir(parents=True)
            shutil.copytree(args.plugins / 'catwalk', case / 'config/plugins/catwalk')
            runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
            runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
            runner.write_json(case / 'config/settings/plugins/catwalk.json', dict(minimumThreshold=20, hideBackground=True, opaque=dict(keep=True)))
            runner.write_json(case / 'config/settings/bar.json', dict(widgets=dict(left=[dict(id='plugin:catwalk', instanceSettings=dict(minimumThreshold=30, opaque='placement'))])))
            shutil.copy2(args.source / 'Assets/ColorScheme/MacOS/MacOS.json', case / 'config/colors.json')
            before = hashes(case / 'config')
            install = case / 'install'
            shutil.copytree(args.source, install, copy_function=os.link, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
            text = runner.run_fixture(profile, install, case, out, args.source / 'Scripts/dev/fixtures/plugin-settings-context-lifetime.qml',
                extra_env=dict(PHA_CONTEXT_SCOPE=scope, PHA_CONTEXT_ORIGINAL='1' if args.original else '0'),
                extra_lint=tuple(install / name for name in inputs[:3]), timeout=60)
            assert 'CONTEXT_LIFETIME: PASS ' + scope in text
            diagnostics = '\n'.join(line for line in text.splitlines() if 'CONTEXT_ORIGINAL_OBSERVATION ' not in line)
            assert not any(word in diagnostics for word in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected'))
            if args.original:
                assert 'CONTEXT_RED: ' + scope + ' reproduced' in text
            assert before == hashes(case / 'config'), 'retained capability tests must not publish'
            runner.write_json(out / 'configuration-hashes.json', dict(before=before, after=hashes(case / 'config')))
            runner.write_json(out / 'result.json', dict(status='PASS', scope=scope, original=args.original, callbacks=['current', 'settingsView'], nonpublishing=True, replacementRetargeting=False if not args.original else None))
            runner.remove_completed_installs(case, out)
        runner.write_json(args.output / 'result.json', dict(status='PASS', original=args.original, scopes=['instance', 'shared'], callbacksPerScope=2, actualNativeApis=True))
        print('CONTEXT_LIFETIME: PASS (both actual API scopes, both callbacks)', flush=True)


if __name__ == '__main__':
    main()
