#!/usr/bin/env python3
"""Actual live dialog: native typing across debounce and held owner receipts."""
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
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    for name in ('source', 'output', 'work_root', 'guest_profile'):
        setattr(args, name, getattr(args, name).resolve())
    sys.path.insert(0, str(args.source / 'Scripts/dev'))
    from guest_profile import activate_profile, protect_owned_process
    from probe_files import ProbeFiles
    profile = activate_profile(args.guest_profile)
    assert profile.uuid == '12f17a02-25e9-474c-9dae-fea092c2d2be'
    assert not profile.console.records
    args.output.mkdir(parents=True)
    args.work_root.mkdir(parents=True)
    config = args.work_root / 'c'
    (config / 'settings/plugins').mkdir(parents=True)
    (config / 'settings.json').write_text('{"settingsVersion":62}')
    (config / 'plugins.json').write_text('{"version":5,"sources":[],"states":{}}')
    runtime = profile.child_environment('live-')
    socket = args.work_root / 'u.sock'
    env = dict(os.environ, **runtime, QT_QPA_PLATFORM='wayland', QML_DISABLE_DISK_CACHE='1',
               TMPDIR=str(args.work_root / 'tmp'), YDOTOOL_SOCKET=str(socket),
               LIVE_INPUT_HAS_BOOTSTRAP='1' if (args.source / 'Commons/SettingsBootstrap.qml').is_file() else '0',
               ATMOSPHERA_CONFIG_DIR=str(config), ATMOSPHERA_SETTINGS_FILE=str(config / 'settings.json'),
               ATMOSPHERA_CACHE_DIR=str(args.work_root / 'cache'),
               ATMOSPHERA_STATE_DIR=str(args.work_root / 'state'))
    Path(env['TMPDIR']).mkdir()
    files_owner = None
    process = None
    owned = None
    daemon = False
    unit = 'atcq-live-input-' + args.work_root.name
    observations = {}
    errors = []

    def call(argv, check=True):
        return subprocess.run(['timeout', '10', *map(str, argv)], env=env, capture_output=True,
                              text=True, timeout=15, check=check)

    def ipc(method):
        return call(['qs', '-p', probe, 'ipc', 'call', 'liveInput', method]).stdout

    def snapshot():
        return json.loads(ipc('snapshot'))

    def wait(predicate):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            value = predicate()
            if value:
                return value
            assert process is None or process.poll() is None, 'fixture exited early'
            time.sleep(0.05)
        raise AssertionError('live input deadline')

    try:
        files_owner = ProbeFiles(args.source, args.source / 'Scripts/dev/fixtures/settings-live-input.qml')
        probe = files_owner.probe
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
            ipc('focus')
            wait(lambda: snapshot()['focused'])
            call(['ydotool', 'type', '--key-delay', '10', 'alpha'])
            wait(lambda: snapshot()['held'] == 1)
            observations['debounced'] = snapshot()
            assert observations['debounced']['focused'], 'automatic persistence moved focus out of the native text field'
            generation = observations['debounced']['generation']
            call(['ydotool', 'type', '--key-delay', '10', 'beta'])
            observations['whileBusy'] = snapshot()
            assert observations['whileBusy']['text'] == 'alphabeta', 'continued native typing was lost'
            assert observations['whileBusy']['generation'] > generation, 'live input guard stopped observing while persistence was busy'
            ipc('release')
            wait(lambda: snapshot()['held'] == 1)
            observations['second'] = snapshot()
            assert observations['second']['dirty'] and observations['second']['focused']
            ipc('release')
            wait(lambda: not snapshot()['busy'] and not snapshot()['dirty'])
            observations['settled'] = snapshot()
            assert observations['settled']['stored'][0]['leftClickExec'] == 'alphabeta'
            # A focused clear must reach both page intent and the native-input guard once.
            generation = observations['settled']['generation']
            ipc('clear')
            observations['cleared'] = snapshot()
            assert observations['cleared']['text'] == ''
            assert observations['cleared']['generation'] == generation + 1, 'clear did not produce exactly one native input intent'
            wait(lambda: snapshot()['held'] == 1)
            ipc('release')
            wait(lambda: not snapshot()['busy'] and not snapshot()['dirty'])
            call(['ydotool', 'type', '--key-delay', '10', 'final'])
            wait(lambda: snapshot()['held'] == 1)
            ipc('close')
            observations['closing'] = snapshot()
            ipc('release')
            wait(lambda: not snapshot()['visible'])
            observations['closed'] = snapshot()
            assert observations['closed']['stored'][0]['leftClickExec'] == 'final'
            assert observations['closed']['blurs'] > 0 and not observations['closed']['focused'], 'explicit save-and-close must still settle blur'
            # A real detached owner refuses the next edit. Explicit discard must
            # retire that input lifetime, including the guard's dirty generation.
            ipc('reopenDetached')
            ipc('focus')
            wait(lambda: snapshot()['focused'])
            call(['ydotool', 'type', '--key-delay', '10', 'discarded'])
            wait(lambda: snapshot()['held'] == 1)
            ipc('release')
            wait(lambda: not snapshot()['busy'])
            observations['refused'] = snapshot()
            assert observations['refused']['dirty'] and observations['refused']['guardDirty']
            assert observations['refused']['receipts'][-1]['status'] == 'failed'
            ipc('discard')
            wait(lambda: not snapshot()['visible'])
            observations['discarded'] = snapshot()
            assert not observations['discarded']['dirty'] and not observations['discarded']['guardDirty'], 'confirmed discard retained the old input generation'
            assert observations['discarded']['stored'][0]['leftClickExec'] == 'final'
            ipc('quit')
            assert process.wait(timeout=15) == 0
        assert not any(token in (args.output / 'save.log').read_text() for token in ('TypeError:', 'ReferenceError:', 'SyntaxError:', '_ASSERT:'))
        result = subprocess.run(['timeout', '20', 'dbus-run-session', '--', 'qs', '-p', str(probe), '--no-color'],
                                env=dict(env, LIVE_INPUT_COLD='1'), capture_output=True, text=True, timeout=25)
        text = result.stdout + result.stderr
        (args.output / 'cold.log').write_text(text)
        assert result.returncode == 0 and 'LIVE_INPUT_COLD:' in text and '"leftClickExec":"final"' in text, text
        row = json.loads((config / 'settings/bar.json').read_text())['widgets']['left'][0]
        assert row['leftClickExec'] == 'final' and row['opaque'] == {'keep': True}
        observations['disk'] = row
        vfs = list((Path(runtime['XDG_RUNTIME_DIR']) / 'quickshell/vfs').iterdir())
        assert len(vfs) == 1
        files = ['Widgets/NSettingsInputGuard.qml', 'Widgets/NLiveSettingsEditSession.qml', 'Widgets/NTextInput.qml',
                 'Modules/Panels/Settings/Bar/BarWidgetSettingsDialog.qml',
                 'Modules/Panels/Settings/ControlCenter/ControlCenterWidgetSettingsDialog.qml',
                 'Modules/Panels/Settings/DesktopWidgets/DesktopWidgetSettingsDialog.qml',
                 'Scripts/dev/fixtures/settings-live-input.qml']
        result = subprocess.run(['bash', args.source / 'Scripts/dev/qmllint.sh', *[args.source / name for name in files]],
                                cwd=args.source, env=dict(env, QS_VFS=str(vfs[0])), capture_output=True, text=True, timeout=45)
        (args.output / 'lint.log').write_text(result.stdout + result.stderr)
        assert result.returncode == 0, 'changed QML lint failed'
        (args.output / 'source-hashes.json').write_text(json.dumps({name: hashlib.sha256((args.source / name).read_bytes()).hexdigest() for name in files}, indent=2))
        profile.verify()
    except BaseException as error:
        errors.append(repr(error))
    finally:
        for operation in (
                lambda: owned.terminate() if owned else None,
                lambda: process.wait(timeout=15) if process else None,
                lambda: call(['sudo', '-n', 'systemctl', 'stop', unit]) if daemon else None,
                lambda: files_owner.close() if files_owner else None,
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
    print('SETTINGS_LIVE_INPUT: PASS (native continued typing, held real receipts, clear, close, disk and cold consumer)')


if __name__ == '__main__':
    main()
