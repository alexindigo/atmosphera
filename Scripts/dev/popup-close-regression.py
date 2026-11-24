#!/usr/bin/env python3
"""Actual host/popup close, replacement and held-completion controls, guest only."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil

from guest_profile import activate_profile, profile_argument

SPEC = importlib.util.spec_from_file_location('host_regression', Path(__file__).with_name('plugin-settings-host-assets-regression.py'))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    profile_argument(parser)
    for name in ('source', 'output', 'work-root'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--plugins', type=Path, help='paired-wrapper compatibility; this case uses a synthetic plugin')
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    profile.prepare_roots()
    for path, parent in ((args.work_root, profile.work_base), (args.output, profile.journal_base)):
        if path != path.resolve() or not path.is_relative_to(parent) or path == parent:
            parser.error('fresh roots must belong to the explicit guest profile')
    with (profile.work_base / '.plugin-settings-host-assets.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        args.work_root.mkdir(exist_ok=False)
        args.output.mkdir(exist_ok=False)
        case, out = args.work_root, args.output
        install = case / 'install'
        shutil.copytree(args.source, install, ignore=shutil.ignore_patterns('.git', '.envrc', '__pycache__'))
        for name in ('config/settings/plugins', 'config/plugins/close-fixture', 'cache', 'state'):
            (case / name).mkdir(parents=True)
        manifest = dict(id='close-fixture', name='Close fixture', author='Atmosphera fixture',
            description='Native popup close fixture', version='1.0.0', entryPoints=dict(settings='Page.qml'), metadata=dict(
                defaultSettings=dict(label='saved'), settingsSchema=dict(version=1,
                    fields=dict(label=dict(type='String', editorUsage='configuration')))))
        runner.write_json(case / 'config/plugins/close-fixture/manifest.json', manifest)
        shutil.copy2(args.source / 'Scripts/dev/fixtures/plugin-settings-session-page.qml', case / 'config/plugins/close-fixture/Page.qml')
        runner.write_json(case / 'config/settings.json', dict(settingsVersion=62))
        runner.write_json(case / 'config/plugins.json', dict(version=6, sources=[], states={}))
        shared = case / 'config/settings/plugins/close-fixture.json'
        runner.write_json(shared, dict(label='saved', opaque=dict(keep=True)))
        names = ['Modules/MainScreen/PopupMenuWindow.qml', 'Widgets/NPluginSettingsPopup.qml',
                 'Services/UI/BarService.qml', 'Services/UI/DesktopWidgetRegistry.qml', 'Services/UI/PanelService.qml',
                 'Modules/Panels/Settings/Bar/BarWidgetSettingsDialog.qml',
                 'Modules/Panels/Settings/ControlCenter/ControlCenterWidgetSettingsDialog.qml',
                 'Modules/Panels/Settings/DesktopWidgets/DesktopWidgetSettingsDialog.qml',
                 'Scripts/dev/fixtures/plugin-settings-session.qml', 'Scripts/dev/fixtures/popup-close-contract.qml']
        fixture = args.source / 'Scripts/dev/fixtures/popup-close-contract.qml'
        bad = ('TypeError:', 'ReferenceError:', 'SyntaxError:', '_ASSERT:', 'Binding loop detected')
        for mode in ('warm', 'cold'):
            output = out / mode
            output.mkdir()
            text = runner.run_fixture(profile, install, case, output, fixture, extra_lint=tuple(install / name for name in names),
                                     extra_env=dict(PHA_CLOSE_COLD='1' if mode == 'cold' else '0'), timeout=110)
            marker = 'POPUP_CLOSE_CONTRACT: ' + ('COLD_PASS' if mode == 'cold' else 'PASS 9 routes, 3 live dialogs and adoption races')
            if marker not in text or any(token in text for token in bad):
                raise RuntimeError('actual popup close consumer/runtime diagnostic; see ' + str(output / 'runtime.log'))
            if json.loads(shared.read_text()) != dict(label='held-8', opaque=dict(keep=True)):
                raise RuntimeError('independent final popup close native-file mismatch')
        runner.write_json(out / 'source-hashes.json', {name: hashlib.sha256((args.source / name).read_bytes()).hexdigest() for name in names})
        runner.write_json(out / 'result.json', dict(status='PASS', nativeGenericEditor=True,
            realHeldReceipts=True, refusedRoutes=9, separateLiveDialogs=3, controlledLiveSubmissionReceipts=True,
            adoptionRaces=True, independentPersistedReadback=True, separateColdConsumer=True))
        runner.remove_completed_installs(case, out)
        print('POPUP_CLOSE_CONTRACT: PASS (native generic editor; live-dialog controlled receipts)', flush=True)


if __name__ == '__main__':
    main()
