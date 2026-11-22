#!/usr/bin/env python3
"""Actual selected popup geometry, field state and hidden override scroll. Guest only."""
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for key in ('source', 'work-root', 'output'):
        parser.add_argument('--' + key, type=Path, required=True)
    parser.add_argument('--install-source', type=Path)
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    profile.prepare_roots()
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or path == parent or not path.is_relative_to(parent):
            parser.error('fresh roots must belong to the verified profile')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        case, out = args.work_root, args.output
        case.mkdir(); out.mkdir()
        for part in ('config/settings/plugins', 'config/plugins/review-fixture', 'cache', 'state'):
            (case / part).mkdir(parents=True)
        install = case / 'install'
        shutil.copytree(args.install_source or args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '*.bak', '__pycache__'))
        fields = {name: dict(type='String', editorUsage='configuration') for name in ['message', *[f'hidden{i:02}' for i in range(24)]]}
        fields['hidden23']['sensitive'] = True
        manifest = dict(id='review-fixture', name='Review fixture', version='1.0.0', author='Atmosphera fixture', description='Native review fixture', entryPoints=dict(settings='Page.qml'), metadata=dict(defaultSettings={name: 'default' for name in fields}, settingsSchema=dict(version=1, fields=fields)))
        runner.write_json(case / 'config/plugins/review-fixture/manifest.json', manifest)
        runner.write_json(case / 'config/settings.json', dict(settingsVersion=62, general=dict(language='en')))
        runner.write_json(case / 'config/plugins.json', dict(version=6, states={}, sources=[]))
        runner.write_json(case / 'config/settings/plugins/review-fixture.json', dict(message='Plugin-level value'))
        runner.write_json(case / 'config/settings/bar.json', dict(widgets=dict(left=[dict(id='plugin:review-fixture', instanceSettings=dict(message='Instance value')), dict(id='plugin:review-fixture', instanceSettings={name: 'Another instance value' if name == 'message' else 'private-user-value' for name in fields}), dict(id='plugin:review-fixture')])))
        (case / 'config/plugins/review-fixture/Page.qml').write_text('''import QtQuick
import QtQuick.Layouts
import qs.Widgets
ColumnLayout {
  id: root
  property var pluginApi: null
  readonly property bool settingsDirty: false
  readonly property var message: pluginApi?.field("message") ?? null
  NPluginSettingsField {
    field: root.message
    NTextInput { id: input; label: "Message"; text: root.message?.value ?? ""; onEditCommitted: root.message.set(text) }
  }
  function edit() { input.inputItem.remove(0, input.text.length); input.inputItem.insert(0, "Pending user value"); input.editCommitted(); }
  function resetField() { message.reset(); }
  function rejectInput() { message.set({invalid: true}); }
  function saveSettings() { pluginApi.saveSettings(); }
}
''')
        before = {str(p.relative_to(case)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (case / 'config').rglob('*.json')}
        fixture = args.source / 'Scripts/dev/fixtures/plugin-settings-chrome.qml'
        runner.write_json(out / 'inputs.json', {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in (fixture, args.source / 'Widgets/NPluginSettingsPopup.qml', args.source / 'Widgets/NPluginSettingsField.qml')})
        text = runner.run_fixture(profile, install, case, out, fixture, extra_env=dict(PHA_CHROME_OUTPUT=str(out)), extra_lint=(install / 'Widgets/NPluginSettingsPopup.qml', install / 'Widgets/NPluginSettingsField.qml'), timeout=90)
        rows = [json.loads(line.split('CHROME_GEOMETRY ', 1)[1]) for line in text.splitlines() if 'CHROME_GEOMETRY ' in line]
        runner.write_json(out / 'geometry.json', rows)
        assert 'PLUGIN_SETTINGS_CHROME: CAPTURED' in text
        assert len(rows) == 11
        # The normal color owner may create its separate initial colors.json.
        # Every seeded preference/manifest still needs exact byte preservation.
        assert all(hashlib.sha256((case / name).read_bytes()).hexdigest() == digest for name, digest in before.items()), 'nonpublishing control/Reset/Discard preserves every seeded file'
        for row in rows:
            popup = row['popup']
            assert popup['height'] <= popup['maxHeight']
            for label in ('Apply', 'Close', 'Appliquer', 'Fermer'):
                buttons = [item for item in row['texts'] if item['text'] == label]
                if label in ('Apply', 'Appliquer'):
                    assert len(buttons) in (0, 2)
                for button in buttons:
                    assert popup['y'] <= button['y'] and button['y'] + button['height'] <= popup['y'] + popup['height'] + 0.5, 'footer actions remain inside bounded popup'
                    assert 0 <= button['y'] and button['y'] + button['height'] <= row['host']['height'] + 0.5, 'footer actions remain on screen'
            if row['undisplayed']:
                assert not any(item['text'] == 'private-user-value' for item in row['texts']), 'summary never renders secret values'
        states = {row['label']: row for row in rows}
        for label, wanted in [('en-instance', 'Instance value'), ('en-pending', 'Change pending'), ('en-reset-pending', 'Reset pending')]:
            assert any(item['text'] == wanted for item in states[label]['texts'])
        assert any(item['text'] == 'Plugin-level value' for item in states['en-reset-pending']['texts']), 'Reset presents inherited value without publishing'
        assert any(item['text'] == 'Inherited' for item in states['fr-inherited']['texts']), 'inherited state is explicit in the fallback locale'
        assert any(item['text'] == 'Could not save changes. Your edits are still here.' for item in states['en-failed']['texts']), 'failed input remains visible with truthful feedback'
        assert any('Shared content and other stored data are kept.' in item['text'] for item in states['en-reset-confirmation']['texts']), 'whole Reset describes its configuration-only boundary'
        for label in ('fr-many-overrides', 'fr-many-bottom', 'fr-hidden-reset'):
            assert states[label]['undisplayed'] == 24
        bottom = states['fr-many-bottom']
        hidden = next(item for item in bottom['texts'] if item['text'] == 'hidden23')
        assert bottom['popup']['y'] <= hidden['y'] < bottom['popup']['y'] + bottom['popup']['height'], 'last hidden field reachable by normal scroll'
        runner.write_json(out / 'result.json', dict(status='PASS', states=list(states), nativeOwners=True, hiddenOverrides=24, lastResetStaged=True, seededHashesUnchanged=before, geometryAssertions=True, visualReview=False, completePlanAcceptance=False))
        runner.remove_completed_installs(case, out)
        print('PLUGIN_SETTINGS_CHROME: PASS (geometry/scroll/native control state; visual review separate)', flush=True)


if __name__ == '__main__':
    main()
