#!/usr/bin/env python3
"""Actual native placement incarnation/read/action admission across all families."""
import argparse
from copy import deepcopy
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil

from guest_profile import activate_profile, profile_argument
spec = importlib.util.spec_from_file_location('incarnation_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'plugins', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--original', action='store_true')
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile); profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-context-incarnation-regression.py':
        parser.error('execute supplied source')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh owned guest roots required')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(); args.output.mkdir()
        inputs = ['Services/Plugins/' + name for name in ('PluginInstanceApi.qml', 'PluginInstances.qml', 'PluginSettingsRead.js', 'Service.qml')]
        inputs += ['Scripts/dev/plugin-settings-context-incarnation-regression.py', 'Scripts/dev/fixtures/plugin-settings-context-incarnation.qml']
        runner.write_json(args.output / 'inputs.json', {name: hashlib.sha256((args.source / name).read_bytes()).hexdigest() for name in inputs})
        results = []
        for family in ('global', 'monitor', 'control', 'desktop'):
            for change in (('remove',) if args.original else ('remove', 'reorder', 'insert', 'identity', 'absent')):
                label = family + '-' + change
                case, out = args.work_root / label, args.output / label
                case.mkdir(); out.mkdir()
                for name in ('config/settings/plugins', 'cache', 'state'):
                    (case / name).mkdir(parents=True)
                shutil.copytree(args.plugins / 'catwalk', case / 'config/plugins/catwalk')
                rows = [dict(id='plugin:catwalk', tag='selected', instanceSettings=dict(minimumThreshold=30, opaque='selected')),
                        dict(id='plugin:catwalk', tag='sibling', instanceSettings=dict(minimumThreshold=40, opaque='sibling'))]
                shared = dict(minimumThreshold=20, hideBackground=True, opaque=dict(keep=True))
                documents = {'settings.json': dict(settingsVersion=62), 'plugins.json': dict(version=6, states={}, sources=[]),
                    'settings/plugins/catwalk.json': shared}
                if family == 'global': documents['settings/bar.json'] = dict(widgets=dict(left=rows))
                elif family == 'monitor': documents['settings/bar.json'] = dict(screenOverrides=[dict(name='INCARNATION', enabled=True, widgets=dict(left=rows, center=[], right=[]))])
                elif family == 'control': documents['settings/controlCenter.json'] = dict(shortcuts=dict(left=rows))
                else: documents['settings/desktopWidgets.json'] = dict(enabled=True, monitorWidgets=[dict(name='INCARNATION', widgets=rows)])
                for name, data in documents.items(): runner.write_json(case / 'config' / name, data)
                shutil.copy2(args.source / 'Assets/ColorScheme/MacOS/MacOS.json', case / 'config/colors.json')
                install = case / 'install'
                shutil.copytree(args.source, install, copy_function=os.link, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
                text = runner.run_fixture(profile, install, case, out, args.source / 'Scripts/dev/fixtures/plugin-settings-context-incarnation.qml',
                    extra_env=dict(PHA_INCARNATION_FAMILY=family, PHA_INCARNATION_CHANGE=change, PHA_INCARNATION_ORIGINAL='1' if args.original else '0'),
                    extra_lint=tuple(install / name for name in inputs[:4] if name.endswith('.qml')), timeout=90)
                assert not any(word in text for word in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected')), text[-4000:]
                assert ('INCARNATION_RED: REPRODUCED ' + family if args.original else 'INCARNATION: PASS ' + family + '/' + change) in text
                expected = deepcopy(documents)
                expected['settings/plugins/catwalk.json']['hideBackground'] = False
                rows[0]['tag'] = 'member-edited'; rows[0]['instanceSettings']['minimumThreshold'] = 35
                changed = deepcopy(rows)
                if change == 'remove': changed.pop(0)
                elif change == 'reorder': changed.reverse()
                elif change == 'insert': changed.insert(0, dict(id='plugin:catwalk', tag='inserted', instanceSettings=dict(minimumThreshold=50)))
                elif change == 'identity': changed[0]['id'] = 'plugin:other'
                else: changed = []
                filename = next(name for name in documents if name in ('settings/bar.json', 'settings/controlCenter.json', 'settings/desktopWidgets.json'))
                if family == 'global': expected[filename]['widgets']['left'] = changed
                elif family == 'monitor': expected[filename]['screenOverrides'][0]['widgets']['left'] = changed
                elif family == 'control': expected[filename]['shortcuts']['left'] = changed
                else: expected[filename]['monitorWidgets'][0]['widgets'] = changed
                actual = {name: json.loads((case / 'config' / name).read_text()) for name in documents}
                assert actual == expected, (label, actual, expected)
                runner.write_json(out / 'result.json', dict(status='PASS', family=family, change=change, original=args.original, documents=actual, replacementWrite=False))
                results.append(label); runner.remove_completed_installs(case, out)
        runner.write_json(args.output / 'result.json', dict(status='PASS', cases=results, original=args.original, actualNativeApis=True))
        print('CONTEXT_INCARNATION: PASS', flush=True)


if __name__ == '__main__':
    main()
