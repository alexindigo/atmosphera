#!/usr/bin/env python3
"""Actual host/popup close, replacement and held-completion controls, VM only."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'output', 'work-root', 'guest-profile'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    for name in ('source', 'output', 'work_root', 'guest_profile'):
        setattr(args, name, getattr(args, name).resolve())
    sys.path.insert(0, str(args.source / 'Scripts/dev'))
    from guest_profile import activate_profile
    from probe_files import ProbeFiles
    profile = activate_profile(args.guest_profile)
    assert profile.uuid == '12f17a02-25e9-474c-9dae-fea092c2d2be'
    assert not profile.console.records
    args.output.mkdir(parents=True)
    args.work_root.mkdir(parents=True)
    config = args.work_root / 'config'
    config.mkdir()
    (config / 'settings.json').write_text('{"settingsVersion":62}')
    (config / 'plugins.json').write_text('{"version":5,"sources":[],"states":{}}')
    runtime = profile.child_environment('pc-')
    env = dict(os.environ, **runtime, QT_QPA_PLATFORM='wayland', QML_DISABLE_DISK_CACHE='1',
               TMPDIR=str(args.work_root / 'tmp'), ATMOSPHERA_CONFIG_DIR=str(config),
               ATMOSPHERA_CACHE_DIR=str(args.work_root / 'cache'), ATMOSPHERA_STATE_DIR=str(args.work_root / 'state'))
    Path(env['TMPDIR']).mkdir()
    files_owner = None
    errors = []
    try:
        files_owner = ProbeFiles(args.source, args.source / 'Scripts/dev/fixtures/popup-close-contract.qml')
        probe = files_owner.probe
        result = subprocess.run(['timeout', '25', 'dbus-run-session', '--', 'qs', '-p', str(probe), '--no-color'],
                                env=env, cwd=args.source, capture_output=True, text=True, timeout=30)
        text = result.stdout + result.stderr
        (args.output / 'close.log').write_text(text)
        assert result.returncode == 0 and 'POPUP_CLOSE_CONTRACT: PASS' in text, text
        assert not any(token in text for token in ('TypeError:', 'ReferenceError:', 'SyntaxError:', '_ASSERT:')), text
        vfs = list((Path(runtime['XDG_RUNTIME_DIR']) / 'quickshell/vfs').iterdir())
        assert len(vfs) == 1
        files = ['Modules/MainScreen/PopupMenuWindow.qml', 'Widgets/NPluginSettingsPopup.qml',
                 'Services/UI/BarService.qml', 'Services/UI/DesktopWidgetRegistry.qml', 'Services/UI/PanelService.qml',
                 'Modules/Panels/Settings/Bar/BarWidgetSettingsDialog.qml',
                 'Modules/Panels/Settings/ControlCenter/ControlCenterWidgetSettingsDialog.qml',
                 'Modules/Panels/Settings/DesktopWidgets/DesktopWidgetSettingsDialog.qml',
                 'Scripts/dev/fixtures/plugin-settings-session.qml', 'Scripts/dev/fixtures/popup-close-contract.qml']
        result = subprocess.run(['bash', args.source / 'Scripts/dev/qmllint.sh', *[args.source / name for name in files]],
                                cwd=args.source, env=dict(env, QS_VFS=str(vfs[0])), capture_output=True, text=True, timeout=45)
        (args.output / 'lint.log').write_text(result.stdout + result.stderr)
        assert result.returncode == 0, 'changed QML lint failed'
        (args.output / 'source-hashes.json').write_text(json.dumps({name: hashlib.sha256((args.source / name).read_bytes()).hexdigest() for name in files}, indent=2))
        profile.verify()
    except BaseException as error:
        errors.append(repr(error))
    finally:
        for operation in (lambda: files_owner.close() if files_owner else None,
                          lambda: shutil.rmtree(Path(runtime['XDG_RUNTIME_DIR']))):
            try:
                operation()
            except BaseException as error:
                errors.append('cleanup: ' + repr(error))
        (args.output / 'result.json').write_text(json.dumps(dict(status='FAIL' if errors else 'PASS', errors=errors), indent=2))
        (args.output / 'SHA256SUMS').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.name + '\n'
                                                        for p in sorted(args.output.iterdir()) if p.is_file()))
    if errors:
        raise AssertionError(errors)
    print('POPUP_CLOSE_CONTRACT: PASS (dirty/busy host routes and retained completion dependencies)')


if __name__ == '__main__':
    main()
