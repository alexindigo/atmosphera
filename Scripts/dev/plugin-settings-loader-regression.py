#!/usr/bin/env python3
"""Real selected-session loader role and context matrix, in the named guest.

Production admission is exercised through createObject, PluginView and a
caller-owned Loader. Root, inherited and absent context declarations run with
a real field-page capability and both real runtime API kinds. The negative
controls mutate disposable installs only, never canonical source.
"""
from fixture_receipts import receipt_run, stage_receipt
import argparse
import fcntl
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil

from guest_profile import activate_profile, profile_argument

SPEC = importlib.util.spec_from_file_location('host_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)

CONTROLS = {
    'admission': ('Services/Plugins/PluginLoader.qml',
                  'if (!PluginContract.acceptsApi(entryPoint, api))', 'if (false)'),
    'direct': ('Services/Plugins/PluginLoader.qml',
               'initial = initialProperties(entryPoint, component.url, api, context);', 'initial = {pluginApi: api};'),
    'view': ('Services/Plugins/PluginView.qml',
             'props = PluginLoader.initialProperties(entryPoint, url, api, context);', 'props = {pluginApi: api};'),
}


def seed(case):
    for name in ('config/settings/plugins', 'config/plugins/loader-matrix', 'cache', 'state'):
        (case / name).mkdir(parents=True, exist_ok=True)
    runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
    runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
    shared = case / 'config/settings/plugins/loader-matrix.json'
    runner.write_json(shared, dict(label='P', opaque=dict(keep=True)))
    plugin = case / 'config/plugins/loader-matrix'
    runner.write_json(plugin / 'manifest.json', dict(id='loader-matrix', name='Loader matrix', version='1.0.0',
                      author='Atmosphera fixture', description='Selected settings construction contract',
                      entryPoints=dict(settings='declares.qml'), metadata=dict(defaultSettings=dict(label='D'),
                      settingsSchema=dict(version=1, fields=dict(label=dict(type='String', editorUsage='configuration'))))))
    base = '''import QtQuick
Item {
  property var pluginApi: null
  property var screen: null
  property bool completedApi: false
  property var completedScreen: null
  Component.onCompleted: {
    completedApi = pluginApi !== null;
    completedScreen = screen;
    console.log("LOADER_CONSTRUCTED");
  }
}
'''
    (plugin / 'declares.qml').write_text(base)
    (plugin / 'ContextBase.qml').write_text(base)
    (plugin / 'inherits.qml').write_text('import QtQuick\nContextBase {}\n')
    (plugin / 'bare.qml').write_text(base.replace('  property var screen: null\n', '').replace('completedScreen = screen;', 'completedScreen = null;'))
    return shared


@receipt_run
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--plugins', type=Path, help='paired-driver compatibility; no catalog Main is run')
    parser.add_argument('--negative-control', choices=CONTROLS)
    parser.add_argument('--path', choices=('direct', 'view', 'loader'), help='one construction cohort')
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    profile.prepare_roots()
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh roots must belong to the verified profile')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(exist_ok=False)
        args.output.mkdir(exist_ok=False)
        install = args.work_root / 'install'
        shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
        shared = seed(args.work_root)
        before = shared.read_bytes()
        mutation = None
        if args.negative_control:
            name, old, new = CONTROLS[args.negative_control]
            path = install / name
            original = path.read_text()
            if original.count(old) != 1:
                raise RuntimeError('review changed rejecting-control boundary: ' + name)
            path.write_text(original.replace(old, new))
            mutation = dict(file=name, originalSha256=hashlib.sha256(original.encode()).hexdigest(),
                            mutatedSha256=hashlib.sha256(path.read_bytes()).hexdigest())
        error = None
        fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-loader-matrix.qml'
        try:
            text = runner.run_fixture(profile, install, args.work_root, args.output, fixture, timeout=100,
                                      extra_env=dict(PHA_LOADER_PATH=args.path or ''),
                                      extra_lint=[install / 'Services/Plugins/PluginLoader.qml', install / 'Services/Plugins/PluginView.qml'])
        except RuntimeError as failure:
            error = str(failure)
            text = (args.output / 'runtime.log').read_text()
        rows = [json.loads(line.split('LOADER_ROW ', 1)[1]) for line in text.splitlines() if 'LOADER_ROW ' in line]
        expected = {(path, style, role, 'settings') for path in ('direct', 'view', 'loader')
                    for style in ('declares', 'inherits', 'bare') for role in ('editor', 'shared', 'instance')}
        expected |= {(path, style, 'shared', 'panel') for path in ('direct', 'view', 'loader') for style in ('declares', 'inherits', 'bare')}
        if args.path:
            expected = {row for row in expected if row[0] == args.path}
        actual = {(row['path'], row['style'], row['role'], row['entry']) for row in rows}
        unchanged = shared.read_bytes() == before
        bar = args.work_root / 'config/settings/bar.json'
        placement = json.loads(bar.read_text())['widgets']['left'] == [dict(id='plugin:loader-matrix')]
        constructed = sum('LOADER_CONSTRUCTED' in line for line in text.splitlines())
        diagnostics = [line for line in text.splitlines() if any(value in line for value in
                       ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Cannot assign to non-existent property'))]
        if args.negative_control:
            endpoint = 'runtime shared API rejected before ' + (args.path or ('view' if args.negative_control == 'view' else 'direct')) + ' creation'
            passed = error is not None and 'LOADER_ASSERT: ' + endpoint in text and unchanged and placement
        else:
            passed = not error and len(rows) == len(expected) and actual == expected and all(row['status'] == 'PASS' for row in rows) and \
                     constructed == (6 if args.path else 18) and unchanged and placement and not diagnostics and 'PLUGIN_SETTINGS_LOADER_MATRIX: PASS' in text
        result = dict(status='PASS' if passed else 'FAIL', rows=rows, expectedRows=len(expected), constructed=constructed,
                      sharedBytesUnchanged=unchanged, independentPlacementReadback=placement, fixtureError=error,
                      diagnostics=diagnostics, negativeControl=args.negative_control, mutation=mutation,
                      inputs={name: hashlib.sha256((args.source / name).read_bytes()).hexdigest() for name in
                              ('Services/Plugins/PluginLoader.qml', 'Services/Plugins/PluginView.qml',
                               'Services/Plugins/PluginContract.js', 'Services/Plugins/PluginSettingsSession.qml',
                               'Services/Plugins/PluginSettingsPageApi.qml', 'Services/Plugins/PluginSettingsFields.qml',
                               'Scripts/dev/fixtures/plugin-settings-loader-matrix.qml',
                               'Scripts/dev/plugin-settings-loader-regression.py')},
                      witness='production admission/context delivery with actual native selected page API; no catalog consumer claim')
        stage_receipt(args.output / 'result.json', result)
        print('PLUGIN_SETTINGS_LOADER: ' + result['status'], flush=True)
        if passed:
            runner.remove_completed_installs(args.work_root, args.output)
        else:
            raise SystemExit(1)


if __name__ == '__main__':
    main()
