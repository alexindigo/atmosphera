#!/usr/bin/env python3
"""Refused desktop opening cleans real unassigned shortcuts, VM only."""
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
    parser.add_argument('--captured', action='store_true')
    args = parser.parse_args()
    for name in ('source', 'output', 'work_root', 'guest_profile'):
        setattr(args, name, getattr(args, name).resolve())
    sys.path.insert(0, str(args.source / 'Scripts/dev'))
    from guest_profile import activate_profile
    from probe_files import ProbeFiles
    profile = activate_profile(args.guest_profile)
    assert profile.uuid == '12f17a02-25e9-474c-9dae-fea092c2d2be' and not profile.console.records
    args.output.mkdir(parents=True)
    args.work_root.mkdir(parents=True)
    config = args.work_root / 'config'
    (config / 'settings/plugins').mkdir(parents=True)
    (config / 'settings.json').write_text('{"settingsVersion":62}')
    (config / 'plugins.json').write_text('{"version":5,"sources":[],"states":{}}')
    runtime = profile.child_environment('sr-')
    env = dict(os.environ, **runtime, QT_QPA_PLATFORM='wayland', QML_DISABLE_DISK_CACHE='1',
               TMPDIR=str(args.work_root / 'tmp'), ATMOSPHERA_CONFIG_DIR=str(config),
               ATMOSPHERA_CACHE_DIR=str(args.work_root / 'cache'), ATMOSPHERA_STATE_DIR=str(args.work_root / 'state'),
               SHORTCUT_CAPTURED='1' if args.captured else '0')
    Path(env['TMPDIR']).mkdir()
    files_owner = None
    errors = []
    try:
        files_owner = ProbeFiles(args.source, args.source / 'Scripts/dev/fixtures/desktop-settings-refusal.qml')
        probe = files_owner.probe
        for leg, marker in [('save', 'SAVED_PASS'), ('cold', 'COLD_PASS')]:
            result = subprocess.run(['timeout', '22', 'dbus-run-session', '--', 'qs', '-p', str(probe), '--no-color'],
                                    env=dict(env, SHORTCUT_COLD='1' if leg == 'cold' else '0'), cwd=args.source,
                                    capture_output=True, text=True, timeout=27)
            text = result.stdout + result.stderr
            (args.output / (leg + '.log')).write_text(text)
            assert result.returncode == 0 and 'SHORTCUT_REFUSAL: ' + marker in text, text
            assert not any(token in text for token in ('TypeError:', 'ReferenceError:', 'SyntaxError:', '_ASSERT:')), text
        value = json.loads((config / 'settings/desktopWidgets.json').read_text())
        rows = value['monitorWidgets'][0]['widgets']
        assert len(rows) == 1 and rows[0]['id'] == 'Clock' and rows[0]['opaque'] == {'keep': True}, value
        (args.output / 'disk.json').write_text(json.dumps(value, indent=2))
        vfs = list((Path(runtime['XDG_RUNTIME_DIR']) / 'quickshell/vfs').iterdir())
        assert len(vfs) == 1
        files = ['Services/UI/DesktopWidgetRegistry.qml', 'Scripts/dev/fixtures/desktop-settings-refusal.qml']
        lint = subprocess.run(['bash', args.source / 'Scripts/dev/qmllint.sh', *[args.source / name for name in files]],
                              cwd=args.source, env=dict(env, QS_VFS=str(vfs[0])), capture_output=True, text=True, timeout=45)
        (args.output / 'lint.log').write_text(lint.stdout + lint.stderr)
        assert lint.returncode == 0
        (args.output / 'source-hashes.json').write_text(json.dumps({name: hashlib.sha256((args.source / name).read_bytes()).hexdigest() for name in files}))
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
    print('DESKTOP_SETTINGS_REFUSAL: PASS (actual unassigned removal, disk and cold consumer)')


if __name__ == '__main__':
    main()
