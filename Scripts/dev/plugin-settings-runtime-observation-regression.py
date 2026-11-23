#!/usr/bin/env python3
"""Selected session writer/read acknowledgment contract, named guest only."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
from guest_profile import activate_profile, profile_argument

spec = importlib.util.spec_from_file_location('observation_runner', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'work-root', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--scenario', choices=('hold', 'failure', 'noop', 'owner-loss', 'destroy', 'preview', 'inherited-preview', 'preview-refused', 'newer-apply', 'newer-check', 'changed-draft', 'popup-check'), required=True)
    parser.add_argument('--scope', choices=('instance', 'shared'), required=True)
    parser.add_argument('--bypass-observation', action='store_true', help='disposable old-boundary negative control')
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    profile.prepare_roots()
    if Path(__file__).resolve() != args.source.resolve() / 'Scripts/dev/plugin-settings-runtime-observation-regression.py':
        parser.error('execute supplied source')
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh owned guest roots required')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        case, out = args.work_root, args.output
        case.mkdir()
        out.mkdir()
        install = case / 'install'
        shutil.copytree(args.source, install, copy_function=os.link, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
        if args.bypass_observation:
            target = install / 'Services/Plugins/PluginSettingsSession.qml'
            original = target.read_text()
            old = 'root._observe(result, reset);'
            assert original.count(old) == 1
            target.unlink()
            target.write_text(original.replace(old, 'root._finish(result, reset);'))
        for part in ('config/settings/plugins', 'config/plugins/observation-fixture', 'cache', 'state'):
            (case / part).mkdir(parents=True)
        manifest = dict(id='observation-fixture', name='Observation fixture', author='Atmosphera fixture', description='Native observation fixture', version='1.0.0', entryPoints=dict(settings='Page.qml'), metadata=dict(defaultSettings=dict(label='default'), settingsSchema=dict(version=1, fields=dict(label=dict(type='String', editorUsage='configuration')))))
        runner.write_json(case / 'config/plugins/observation-fixture/manifest.json', manifest)
        page = args.source / 'Scripts/dev/fixtures/plugin-settings-session-page.qml'
        if args.scenario == 'popup-check':
            shutil.copy2(page, case / 'config/plugins/observation-fixture/Page.qml')
        runner.write_json(case / 'config/settings.json', dict(settingsVersion=62, general=dict(language='en')))
        runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
        shared = dict(label='shared', opaque=dict(keep=True))
        bar = dict(widgets=dict(left=[dict(id='plugin:observation-fixture', instanceSettings=dict(opaque='selected')), dict(id='plugin:observation-fixture', instanceSettings=dict(label='sibling'))]))
        runner.write_json(case / 'config/settings/plugins/observation-fixture.json', shared)
        runner.write_json(case / 'config/settings/bar.json', bar)
        fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-runtime-observation.qml'
        a11y_helper = args.source / 'Scripts/dev/fixtures/plugin-settings-observation-a11y.py'
        qml = ['Services/Plugins/' + name for name in ('PluginSettingsSession.qml', 'PluginSettingsPageApi.qml', 'PluginSettingsPreview.qml', 'PluginInstanceApi.qml', 'Service.qml')]
        if args.scenario == 'popup-check':
            qml.extend(('Widgets/NPluginSettingsPopup.qml', 'Widgets/NButton.qml', str(page.relative_to(args.source))))
        try:
            text = runner.run_fixture(profile, install, case, out, fixture, extra_env=dict(PHA_OBSERVATION_SCOPE=args.scope, PHA_OBSERVATION_SCENARIO=args.scenario, PHA_OBSERVATION_OUTPUT=str(out), PHA_OBSERVATION_A11Y_HELPER=str(a11y_helper), QT_LINUX_ACCESSIBILITY_ALWAYS_ON='1', QT_FORCE_STDERR_LOGGING='1'), extra_lint=tuple(install / name for name in qml))
        except RuntimeError:
            text = (out / 'runtime.log').read_text()
            if not args.bypass_observation or 'OBSERVATION_ASSERT: native read receipt accompanies success' not in text:
                raise
            runner.write_json(out / 'result.json', dict(status='PASS', kind='bypassed-observation-rejected', originalConsumerFailure='native read receipt accompanies success', runtimeExit=(out / 'runtime.exit').read_text().strip()))
            print('SETTINGS_OBSERVATION_CONTROL: REJECTED ' + args.scope)
            return
        assert not args.bypass_observation, 'bypassed observation escaped'
        assert 'SETTINGS_OBSERVATION: PASS ' + args.scope + ' ' + args.scenario in text
        assert not any(marker in text for marker in ('TypeError:', 'ReferenceError:', 'SyntaxError:', 'Binding loop detected'))
        if args.scenario == 'popup-check':
            a11y = json.loads((out / 'a11y.json').read_text())
            if a11y.get('status') != 'PASS' or a11y.get('realAtSpi') is not True or a11y.get('name') != 'Check again':
                raise RuntimeError('actual AT-SPI activation receipt missing')
        if args.scenario not in ('owner-loss', 'destroy', 'changed-draft', 'popup-check'):
            # Successful acquisition has a real native result. Do not accept a
            # diagnostic whose undefined field was silently omitted by JSON.
            diagnostics = [json.loads(line.split('SETTINGS_OBSERVATION_RESULT ', 1)[1])
                           for line in text.splitlines() if 'SETTINGS_OBSERVATION_RESULT ' in line]
            if not diagnostics or any(row.get('readerStateValid') is not True for row in diagnostics):
                raise RuntimeError('native read-state diagnostic missing or not valid')
        saved = 'newer-input' if args.scenario == 'newer-apply' else 'saved'
        if args.scope == 'shared':
            shared['label'] = saved
        else:
            bar['widgets']['left'][0]['instanceSettings']['label'] = saved
        assert json.loads((case / 'config/settings/plugins/observation-fixture.json').read_text()) == shared
        assert json.loads((case / 'config/settings/bar.json').read_text()) == bar
        inputs = {str(p.relative_to(args.source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__), fixture, *(args.source / name for name in qml))}
        if args.scenario == 'popup-check':
            inputs[str(a11y_helper.relative_to(args.source))] = hashlib.sha256(a11y_helper.read_bytes()).hexdigest()
        runner.write_json(out / 'result.json', dict(status='PASS', scope=args.scope, scenario=args.scenario, inputs=inputs, shared=shared, bar=bar, independentNativeFiles=True, controlledReader=True, physicalProof=False))
        runner.remove_completed_installs(case, out)
        print('SETTINGS_OBSERVATION: PASS ' + args.scope + ' ' + args.scenario)


if __name__ == '__main__':
    main()
