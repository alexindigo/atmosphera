#!/usr/bin/env python3
"""Guest-only rejected-client and bounded terminal-resource acceptance.

Unmodified packaged clients must self-exit. The optional diagnostic loads the
actual packaged LockSession with a test-only terminal-publication response
barrier, never a disabled exit, fake endpoint or synthetic authentication.
"""
import argparse
import json
import os
from pathlib import Path
import re
import secrets
import signal
import subprocess
import time

from locker_test_support import manage, require_guest, run, wait_for


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--resources', action='store_true')
    parser.add_argument('--sample-seconds', type=float, default=10)
    parser.add_argument('--post-unlock-seconds', type=float, default=10)
    parser.add_argument('--recover-known-pam-hang', action='store_true')
    args = parser.parse_args()
    assert args.sample_seconds >= 10 and args.post_unlock_seconds >= 10, 'preserve full resource observation windows'
    source, work = require_guest(args.work, Path(__file__).resolve().parents[2])
    sid = manage(source, {'operation': 'discover'})['session']
    assert run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'no'
    stage = work / 'stage'
    run(['bash', '-eu', '-c', 'source "$1/packaging/aur/package.sh"; package', 'stage', str(source)],
        env=dict(os.environ, srcdir=str(source.parent), _gitname=source.name, pkgdir=str(stage), pkgver='0.9.3'), timeout=60)
    configs = stage / 'etc/xdg/quickshell'
    config = work / 'config'
    config.mkdir()
    (config / 'settings.json').write_text(json.dumps({'settingsVersion': 62, 'general': {
        'lockScreenPlugin': 'default', 'lockOnSuspend': False,
        'enableLockScreenMediaControls': True, 'compactLockScreen': False},
        'audio': {'visualizerType': 'linear'}}))
    environment = {key: value for key, value in os.environ.items() if not key.startswith('ATMOSPHERA_LOCK_')}
    environment.update(ATMOSPHERA_CONFIG_DIR=str(config), ATMOSPHERA_CACHE_DIR=str(work / 'cache'),
        ATMOSPHERA_STATE_DIR=str(work / 'state'), ATMOSPHERA_DEBUG='1', WAYLAND_DEBUG='client')
    units = {}
    observer = None
    authenticated = False
    credential, original_shadow = work / 'credential', work / 'original-shadow-hash'
    password = secrets.token_hex(16)
    original_hash = run(['sudo', '-n', 'getent', 'shadow', 'tester']).stdout.split(':')[1]
    for path, value in ((credential, password), (original_shadow, original_hash)):
        path.touch(mode=0o600)
        path.write_text(value)
    run(['sudo', '-n', 'chpasswd'], input='tester:' + password + '\n')

    def identity(pid):
        fields = (Path('/proc') / str(pid) / 'stat').read_text().split(') ', 1)[1].split()
        return {'pid': int(pid), 'parent': int(fields[1]), 'start': fields[19],
            'ticks': int(fields[11]) + int(fields[12]), 'state': fields[0]}

    def status(role):
        saved = units[role]
        fields = ('InvocationID', 'ControlGroup', 'MainPID', 'ActiveState', 'Result')
        response = subprocess.run(['systemctl', '--user', 'show', saved['name'],
            *[item for field in fields for item in ('-p', field)]], text=True, capture_output=True, timeout=10)
        assert response.returncode == 0 or 'not found' in response.stderr or 'could not be found' in response.stderr, response.stderr
        now = dict(line.split('=', 1) for line in response.stdout.splitlines() if '=' in line)
        assert now.get('InvocationID', '') in ('', saved['InvocationID']), 'test unit replaced'
        group = Path('/sys/fs/cgroup' + saved['ControlGroup'])
        members = []
        if group.exists():
            for file in group.rglob('cgroup.procs'):
                for pid in file.read_text().split():
                    try:
                        members.append(identity(pid))
                    except FileNotFoundError:
                        pass
        try:
            same = identity(saved['pid'])['start'] == saved['start']
        except FileNotFoundError:
            same = False
        return {'systemd': now, 'members': members, 'sameProcess': same,
            'gone': not same and not members and now.get('ActiveState', '') in ('', 'inactive', 'failed')}

    def journal(role):
        text = run(['journalctl', '--user', '-b', '--no-pager', '-o', 'cat',
            '_SYSTEMD_INVOCATION_ID=' + units[role]['InvocationID']]).stdout
        return '\n'.join(line for line in text.splitlines() if 'wl_keyboard' not in line)

    def launch(role, entry, extra=None):
        env = dict(environment, **(extra or {}))
        name = 'locker-orphan-proof-' + role + '.service'
        keys = ('WAYLAND_DISPLAY', 'NIRI_SOCKET', 'HYPRLAND_INSTANCE_SIGNATURE', 'XDG_CURRENT_DESKTOP', 'XDG_SESSION_TYPE',
            'XDG_RUNTIME_DIR', 'DBUS_SESSION_BUS_ADDRESS', 'TMPDIR', 'HOME', 'USER', 'PATH', 'WAYLAND_DEBUG',
            'ATMOSPHERA_CONFIG_DIR', 'ATMOSPHERA_CACHE_DIR', 'ATMOSPHERA_STATE_DIR', 'ATMOSPHERA_DEBUG',
            'ATMOSPHERA_LOCK_SESSION', 'ATMOSPHERA_LOCK_GENERATION', 'ATMOSPHERA_LOCK_ADAPTER', 'LOCKER_TERMINAL_BARRIER')
        run(['systemd-run', '--user', '--collect', '--unit=' + name, '--property=ExitType=cgroup',
            '--property=KillMode=control-group', '--property=TimeoutStopSec=2s', '--property=SendSIGKILL=yes',
            *['--setenv=' + key + '=' + env[key] for key in keys if key in env], '--', 'qs', '-p', str(entry), '--no-color'])
        record = dict(line.split('=', 1) for line in run(['systemctl', '--user', 'show', name,
            '-p', 'InvocationID', '-p', 'ControlGroup', '-p', 'MainPID']).stdout.splitlines())
        assert record['InvocationID'] and record['ControlGroup'] and int(record['MainPID']) > 0
        units[role] = dict(record, name=name, **identity(record['MainPID']))
        (work / 'unit-identities.json').write_text(json.dumps(units, indent=2))

    def locked():
        return run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'yes'

    def recover_pam():
        # Same narrowly identified child-only recovery as the managed tests;
        # this holder is intentionally independent of the generation adapter.
        parent = units['holder']
        assert status('holder')['sameProcess'] and locked()
        assert 'unlock_and_destroy' not in journal('holder')
        for child in status('holder')['members']:
            if child['parent'] != parent['pid']:
                continue
            if (Path('/proc') / str(child['pid']) / 'exe').resolve() != (Path('/proc') / str(parent['pid']) / 'exe').resolve():
                continue
            trace = run(['sudo', '-n', 'gdb', '-q', '-batch', '-p', str(child['pid']), '-ex', 'thread apply all bt'], timeout=20)
            stack = trace.stdout + trace.stderr
            (work / ('pam-child-' + str(child['pid']) + '-stack.txt')).write_text(stack)
            if not all(frame in stack for frame in ('__lll_lock_wait_private', '__syslog_chk', 'pam_syslog', 'pam_sm_authenticate', 'pam_unix.so')):
                continue
            assert identity(parent['pid'])['start'] == parent['start']
            now = identity(child['pid'])
            assert now['start'] == child['start'] and now['parent'] == parent['pid']
            assert status('holder')['systemd']['InvocationID'] == parent['InvocationID']
            assert any(item['pid'] == child['pid'] and item['start'] == child['start'] for item in status('holder')['members'])
            os.kill(child['pid'], signal.SIGKILL)
            wait_for(lambda: not (Path('/proc') / str(child['pid'])).exists())
            assert status('holder')['sameProcess'] and locked() and 'unlock_and_destroy' not in journal('holder')
            (work / 'known-pam-hang-recovery.json').write_text(json.dumps({'holder': parent, 'child': child}, indent=2))

    barrier = work / 'terminal-barrier'
    try:
        observer = subprocess.Popen(['python3', '-B', str(source / 'Scripts/dev/locker-compositor-observer.py'),
            '--work', str(work / 'observer')], env=environment, stdin=subprocess.PIPE,
            stdout=(work / 'observer-stdout.txt').open('w'), stderr=(work / 'observer-stderr.txt').open('w'))
        wait_for(lambda: (work / 'observer/ready.json').exists())
        launch('holder', configs / 'atmosphera-emergency-lock/shell.qml')
        wait_for(lambda: re.search(r'ext_session_lock_v1#\d+\.locked\(\)', journal('holder')), 15)
        for role, folder in (('bundled-loser', 'atmosphera-lockscreen'), ('emergency-loser', 'atmosphera-emergency-lock')):
            launch(role, configs / folder / 'shell.qml')
            wait_for(lambda: re.search(r'ext_session_lock_v1#\d+\.finished\(\)', journal(role)), 30)
            wait_for(lambda: status(role)['gone'], 10)
            assert 'unlock_and_destroy' not in journal(role) and locked() and status('holder')['sameProcess']
            assert 'unlock_and_destroy' not in journal('holder')
        if args.resources:
            barrier.mkdir()
            diagnostic = configs / 'atmosphera-lockscreen/locker-resources.qml'
            diagnostic.write_text((source / 'Scripts/dev/fixtures/locker-resources.qml').read_text())
            launch('diagnostic', diagnostic, {'ATMOSPHERA_LOCK_SESSION': '', 'ATMOSPHERA_LOCK_GENERATION': '',
                'ATMOSPHERA_LOCK_ADAPTER': str(source / 'Scripts/dev/fixtures/locker-terminal-adapter.py'),
                'LOCKER_TERMINAL_BARRIER': str(barrier)})
            wait_for(lambda: (barrier / 'terminal.json').exists(), 30)
            def resources():
                return json.loads(run(['qs', 'ipc', '-p', str(diagnostic), 'call', 'lockerResources', 'status'], env=environment).stdout)
            def stopped():
                view = resources()
                return view if not any(view[key] for key in ('keysRegistered', 'keyPolling', 'spectrumRegistered', 'spectrumEnabled')) else None
            initial_resources = wait_for(stopped)
            log = journal('diagnostic')
            assert re.search(r'ext_session_lock_v1#\d+\.finished\(\)', log) and 'unlock_and_destroy' not in log
            plain = re.sub(r'\x1b\[[0-9;]*m', '', log)
            assert re.search(r'LockKeys\s+Component registered: lockscreen - total: 1', plain)
            assert re.search(r'Spectrum\s+Component registered: lockscreen - total: 1', plain)
            # A refused request creates no UI surfaces. The terminal diagnostic
            # must not initialize compositor event subscriptions at all.
            assert not re.search(r'(NiriService|NiriIpcBackend|Detected compositor|HyprlandService)', log)
            for role in ('holder', 'diagnostic'):
                trace = run(['sudo', '-n', 'gdb', '-q', '-batch', '-p', str(units[role]['pid']),
                    '-ex', 'thread apply all bt'], timeout=20)
                (work / (role + '-native-stacks-before.txt')).write_text(trace.stdout + trace.stderr)
            begin = time.monotonic()
            first = {role: status(role) for role in units}
            samples = []
            while time.monotonic() - begin < args.sample_seconds:
                current = resources()
                assert current == initial_resources, 'post-terminal registrations or event activity'
                assert status('diagnostic')['sameProcess'] and locked() and status('holder')['sameProcess']
                samples.append({'at': time.monotonic(), 'resources': current, 'units': {role: status(role) for role in units}})
                time.sleep(.5)
            last = {role: status(role) for role in units}
            duration = time.monotonic() - begin
            hz = os.sysconf('SC_CLK_TCK')
            cpu = {}
            for role in ('holder', 'diagnostic'):
                before = next(item for item in first[role]['members'] if item['pid'] == units[role]['pid'])
                after = next(item for item in last[role]['members'] if item['pid'] == units[role]['pid'])
                assert before['start'] == after['start'] == units[role]['start']
                cpu[role] = {'ticks': after['ticks'] - before['ticks'], 'CLK_TCK': hz, 'seconds': duration,
                    'cores': (after['ticks'] - before['ticks']) / hz / duration}
                trace = run(['sudo', '-n', 'gdb', '-q', '-batch', '-p', str(units[role]['pid']),
                    '-ex', 'thread apply all bt'], timeout=20)
                (work / (role + '-native-stacks-after.txt')).write_text(trace.stdout + trace.stderr)
            (work / 'resource-sample.json').write_text(json.dumps({'first': first, 'last': last, 'samples': samples, 'cpu': cpu}, indent=2))
            assert cpu['diagnostic']['cores'] < .1, 'retained terminal diagnostic exceeded 0.1 core'
            def activity(text):
                # The cache's unrelated 1x1 renderer can emit frame traffic;
                # the required terminal contract covers lock registrations,
                # LED/spectrum work and compositor event subscriptions.
                return [line for line in text.splitlines() if re.search(
                    r'LockKeys|Spectrum|NiriService|NiriIpcBackend|HyprlandService|/sys/class/leds', line)]
            assert activity(journal('diagnostic')) == activity(log), 'terminal diagnostic continued polling/subscriptions'
            (barrier / 'release').touch(mode=0o600)
            wait_for(lambda: status('diagnostic')['gone'], 10)
        run(['wtype', 'wrong-password'], env=environment)
        run(['wtype', '-k', 'Return'], env=environment)
        time.sleep(3)
        assert locked() and status('holder')['sameProcess'] and 'unlock_and_destroy' not in journal('holder')
        if args.recover_known_pam_hang:
            recover_pam()
        run(['wtype', '-M', 'ctrl', '-k', 'a', '-m', 'ctrl', '-k', 'BackSpace'], env=environment)
        auth_at = time.monotonic()
        with credential.open() as secret:
            run(['wtype', '-'], stdin=secret, env=environment)
        run(['wtype', '-k', 'Return'], env=environment)
        wait_for(lambda: status('holder')['gone'], 15)
        assert not locked()
        authenticated = True
        time.sleep(args.post_unlock_seconds)
        final = {role: status(role) for role in units}
        assert all(view['gone'] and not view['members'] for view in final.values()) and not locked()
        observer.stdin.close()
        assert observer.wait(timeout=10) == 0
        events = [json.loads(line) for line in (work / 'observer/events.jsonl').read_text().splitlines()]
        assert not any(event['kind'] == 'observer-error' for event in events)
        native = [event for event in events if event['kind'] == 'journal' and 'unlock_and_destroy' in event['message']]
        assert len(native) == 1 and native[0]['invocation'] == units['holder']['InvocationID'] and native[0]['sourceMonotonic'] >= auth_at
        hints = [event for event in events if event['kind'] == 'locked-hint' and not event['locked']]
        assert len(hints) == 1 and hints[0]['observed'] >= auth_at
        if os.environ.get('NIRI_SOCKET'):
            compositor = [event for event in events if event['kind'] == 'compositor-log' and 'unlocking session' in event['message']]
            assert len(compositor) == 1 and compositor[0]['sourceMonotonic'] >= auth_at
        (work / 'final.json').write_text(json.dumps(final, indent=2))
        case = 'resources' if args.resources else 'rejected'
        suffix = ' (known native PAM hang recovered)' if (work / 'known-pam-hang-recovery.json').exists() else ''
        (work / 'result.txt').write_text('PASS ' + case + suffix + '\n')
        print('PASS ' + case + suffix, work)
    finally:
        if barrier.exists():
            (barrier / 'release').touch(mode=0o600)
        if observer is not None and observer.poll() is None:
            if not observer.stdin.closed:
                observer.stdin.close()
            assert observer.wait(timeout=15) == 0
        for role in units:
            (work / (role + '-protocol.txt')).write_text(journal(role))
            if role != 'holder' and re.search(r'ext_session_lock_v1#\d+\.finished\(\)', journal(role)):
                wait_for(lambda: status(role)['gone'], 10)
        if authenticated and all(status(role)['gone'] for role in units):
            run(['sudo', '-n', 'chpasswd', '-e'], input='tester:' + original_hash + '\n')
            credential.unlink()
            original_shadow.unlink()
        else:
            print('Real-PAM recovery required; protected files in', work, file=__import__('sys').stderr)


if __name__ == '__main__':
    main()
