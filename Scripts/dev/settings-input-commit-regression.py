#!/usr/bin/env python3
"""Native deferred wrapper publication and held slider gesture across live saves."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'output', 'work-root', 'guest-profile'):
        parser.add_argument('--' + name, type=lambda value: Path(value).resolve(), required=True)
    parser.add_argument('--case', choices=('deferred', 'slider', 'unsupported'), required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.source / 'Scripts/dev'))
    from guest_profile import activate_profile, protect_owned_process
    profile = activate_profile(args.guest_profile)
    assert profile.uuid == '12f17a02-25e9-474c-9dae-fea092c2d2be' and not profile.console.records
    args.output.mkdir(parents=True)
    args.work_root.mkdir(parents=True)
    config = args.work_root / 'c'
    (config / 'settings/plugins').mkdir(parents=True)
    (config / 'settings.json').write_text('{"settingsVersion":62}')
    (config / 'plugins.json').write_text('{"version":5,"sources":[],"states":{}}')
    runtime = profile.child_environment('ic-')
    socket = args.work_root / 'u.sock'
    env = dict(os.environ, **runtime, QT_QPA_PLATFORM='wayland', QML_DISABLE_DISK_CACHE='1',
               TMPDIR=str(args.work_root / 'tmp'), YDOTOOL_SOCKET=str(socket), INPUT_COMMIT_CASE=args.case,
               LIVE_INPUT_HAS_BOOTSTRAP='1' if (args.source / 'Commons/SettingsBootstrap.qml').is_file() else '0',
               ATMOSPHERA_CONFIG_DIR=str(config), ATMOSPHERA_CACHE_DIR=str(args.work_root / 'cache'),
               ATMOSPHERA_STATE_DIR=str(args.work_root / 'state'))
    Path(env['TMPDIR']).mkdir()
    probe = args.source / 'input-commit-proof.qml'
    probe.write_bytes((args.source / 'Scripts/dev/fixtures/settings-input-commit.qml').read_bytes())
    qmlls = args.source / '.qmlls.ini'
    created_qmlls = not qmlls.exists()
    if created_qmlls:
        qmlls.write_text('')
    process = owned = None
    daemon = False
    unit = 'atcq-input-commit-' + args.work_root.name
    observations, errors = {}, []

    def call(argv, check=True):
        return subprocess.run(['timeout', '10', *map(str, argv)], env=env, capture_output=True,
                              text=True, timeout=15, check=check)

    def ipc(method):
        return call(['qs', '-p', probe, 'ipc', 'call', 'inputCommit', method]).stdout

    def snapshot():
        return json.loads(ipc('snapshot'))

    def wait(predicate):
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            value = predicate()
            if value:
                return value
            assert process is None or process.poll() is None, 'fixture exited early'
            time.sleep(0.05)
        raise AssertionError('input commit deadline')

    def settle():
        for unused in range(10):
            value = snapshot()
            if value['held']:
                ipc('release')
            elif not value['busy']:
                return value
            time.sleep(0.1)
        raise AssertionError('receipt settlement deadline')

    try:
        call(['niri', 'msg', 'action', 'close-overview'])
        call(['sudo', '-n', 'systemd-run', '--unit=' + unit, '--property=RuntimeMaxSec=120',
              '--property=TimeoutStopSec=5', '--setenv=TMPDIR=' + env['TMPDIR'], '/usr/bin/ydotoold',
              '--socket-path=' + str(socket), '--socket-own=' + str(profile.uid) + ':' + str(os.getgid())])
        daemon = True
        wait(socket.exists)
        with (args.output / 'save.log').open('x') as log:
            process = subprocess.Popen(['timeout', '80', 'dbus-run-session', '--', 'qs', '-p', str(probe), '--no-color'],
                                       env=env, cwd=args.source, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            owned = protect_owned_process(process)
            wait(lambda: call(['qs', '-p', probe, 'ipc', 'show'], False).returncode == 0)
            wait(lambda: snapshot()['ready'])
            if args.case != 'slider':
                ipc('mixed')
                wait(lambda: snapshot()['focused'])
                call(['ydotool', 'type', '--key-delay', '10', '480'])
                ipc('queue')
                wait(lambda: snapshot()['held'] == 1)
                observations['automatic'] = snapshot()
                assert observations['automatic']['focused'], 'automatic wrapper commit blurred input'
                ipc('release')
                wait(lambda: not snapshot()['busy'])
                observations['acknowledged'] = snapshot()
                assert observations['acknowledged']['stored']['height'] == 96
                if args.case == 'unsupported':
                    assert observations['acknowledged']['stored']['width'] == 320
                    assert observations['acknowledged']['guardDirty'], 'receipt acknowledged unsupported focused text'
                else:
                    assert observations['acknowledged']['stored']['width'] == 480, 'receipt acknowledged unpublished focused wrapper text'
                    assert not observations['acknowledged']['guardDirty']
                call(['ydotool', 'type', '--key-delay', '10', '9'])
                observations['continued'] = snapshot()
                assert observations['continued']['text'] == '4809' and observations['continued']['dirty']
                ipc('close')
                wait(lambda: snapshot()['held'] == 1)
                ipc('release')
                wait(lambda: not snapshot()['visible'])
                observations['closed'] = snapshot()
                assert observations['closed']['stored']['width'] == 4809 and observations['closed']['blurs'] > 0
            else:
                geometry = snapshot()
                x = round(geometry['x'] - geometry['width'] / 5)
                y = round(geometry['y'])
                call(['ydotool', 'mousemove', '--absolute', '-x', x, '-y', y])
                call(['ydotool', 'click', '0x40'])
                wait(lambda: snapshot()['pressed'])
                call(['ydotool', 'mousemove', '--absolute', '-x', round(geometry['x']), '-y', y])
                wait(lambda: snapshot()['held'] == 1)
                observations['held'] = snapshot()
                assert observations['held']['pressed'] and observations['held']['releases'] == 0, 'automatic commit ended held native slider drag'
                ipc('release')
                first = snapshot()['value']
                call(['ydotool', 'mousemove', '--absolute', '-x', round(geometry['x'] + geometry['width'] / 5), '-y', y])
                wait(lambda: snapshot()['value'] != first)
                call(['ydotool', 'click', '0x80'])
                wait(lambda: not snapshot()['pressed'])
                wait(lambda: snapshot()['held'] == 1)
                observations['released'] = settle()
                assert observations['released']['releases'] == 1
                assert observations['released']['stored']['iconScale'] == observations['released']['value']
                ipc('close')
                wait(lambda: not snapshot()['visible'])
            observations['final'] = snapshot()
            ipc('quit')
            assert process.wait(timeout=15) == 0
        assert not any(token in (args.output / 'save.log').read_text() for token in ('TypeError:', 'ReferenceError:', 'SyntaxError:', '_ASSERT:'))
        result = subprocess.run(['timeout', '20', 'dbus-run-session', '--', 'qs', '-p', str(probe), '--no-color'],
                                env=dict(env, LIVE_INPUT_COLD='1'), capture_output=True, text=True, timeout=25)
        text = result.stdout + result.stderr
        (args.output / 'cold.log').write_text(text)
        marker = 'INPUT_COMMIT_COLD: '
        assert result.returncode == 0 and marker in text, text
        row = json.loads(next(line.split(marker, 1)[1] for line in text.splitlines() if marker in line))
        assert row == observations['final']['stored'] and row['opaque'] == {'keep': True}
        shard = json.loads((config / ('settings/bar.json' if args.case == 'slider' else 'settings/desktopWidgets.json')).read_text())
        disk_row = shard['widgets']['left'][0] if args.case == 'slider' else shard['monitorWidgets'][0]['widgets'][0]
        assert disk_row == row
        observations['disk'] = row
        vfs = list((Path(runtime['XDG_RUNTIME_DIR']) / 'quickshell/vfs').iterdir())
        assert len(vfs) == 1
        files = ['Widgets/NSettingsInputGuard.qml', 'Widgets/NTextInput.qml', 'Widgets/NSlider.qml',
                 'Widgets/NSpinBox.qml', 'Scripts/dev/fixtures/settings-input-commit.qml']
        result = subprocess.run(['bash', args.source / 'Scripts/dev/qmllint.sh', *[args.source / name for name in files]],
                                cwd=args.source, env=dict(env, QS_VFS=str(vfs[0])), capture_output=True, text=True, timeout=60)
        (args.output / 'lint.log').write_text(result.stdout + result.stderr)
        assert result.returncode == 0, 'changed QML lint failed'
        (args.output / 'source-hashes.json').write_text(json.dumps({name: hashlib.sha256((args.source / name).read_bytes()).hexdigest() for name in files}, indent=2))
        profile.verify()
    except BaseException as error:
        errors.append(repr(error))
    finally:
        for operation in (
                lambda: call(['ydotool', 'click', '0x80'], False) if daemon else None,
                lambda: owned.terminate() if owned else None,
                lambda: process.wait(timeout=15) if process else None,
                lambda: call(['sudo', '-n', 'systemctl', 'stop', unit]) if daemon else None,
                lambda: probe.unlink(),
                lambda: qmlls.unlink() if created_qmlls else None,
                lambda: shutil.rmtree(Path(runtime['XDG_RUNTIME_DIR']))):
            try:
                operation()
            except BaseException as error:
                errors.append('cleanup: ' + repr(error))
        (args.output / 'result.json').write_text(json.dumps(dict(status='FAIL' if errors else 'PASS', observations=observations, errors=errors), indent=2))
        (args.output / 'SHA256SUMS').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.name + '\n'
                                                       for p in sorted(args.output.iterdir()) if p.is_file()))
    if errors:
        raise AssertionError(errors)
    print('SETTINGS_INPUT_COMMIT: PASS (' + args.case + ', actual native input, persistence and cold consumer)')


if __name__ == '__main__':
    main()
