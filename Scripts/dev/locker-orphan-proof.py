#!/usr/bin/env python3
"""Original rejected-locker lifetime regression, using real independent PAM.

The selected source tree's actual LockSession is loaded in its own source-root
context. This is the source-level red/green proof, not packaged-closure proof.
No Portals link, synthetic unlock or modified production root is introduced.
"""
import argparse
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import time

from locker_test_support import cgroup_pids, manage, require_guest, run, wait_for


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    source, work = require_guest(args.work, args.source)
    driver = Path(__file__).resolve().parents[2]
    sid = manage(driver, {'operation': 'discover'})['session']
    assert run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'no'
    # The independent authenticating holder comes from the already-proven
    # emergency config, not from the baseline tree under regression.
    stage = work / 'holder-stage'
    run(['bash', '-eu', '-c', 'source "$1/packaging/aur/package.sh"; package', 'stage', str(driver)],
        env=dict(os.environ, srcdir=str(driver.parent), _gitname=driver.name, pkgdir=str(stage), pkgver='0.9.3'), timeout=60)
    holder = stage / 'etc/xdg/quickshell/atmosphera-emergency-lock/shell.qml'
    entry = source / '.locker-orphan-proof.qml'
    config = work / 'config'
    config.mkdir()
    (config / 'settings.json').write_text(json.dumps({'settingsVersion': 62, 'general': {'lockScreenPlugin': 'default', 'lockOnSuspend': False}}))
    environment = {key: value for key, value in os.environ.items() if not key.startswith('ATMOSPHERA_LOCK_')}
    environment.update(ATMOSPHERA_CONFIG_DIR=str(config), ATMOSPHERA_CACHE_DIR=str(work / 'cache'),
                       ATMOSPHERA_STATE_DIR=str(work / 'state'), WAYLAND_DEBUG='client')
    units = {}
    credential = work / 'credential'
    original_shadow = work / 'original-shadow-hash'
    password = secrets.token_hex(16)
    original_hash = run(['sudo', '-n', 'getent', 'shadow', 'tester']).stdout.split(':')[1]
    credential.touch(mode=0o600)
    credential.write_text(password)
    original_shadow.touch(mode=0o600)
    original_shadow.write_text(original_hash)
    run(['sudo', '-n', 'chpasswd'], input='tester:' + password + '\n')
    observer = None
    created = False
    candidate_rejected = False
    authenticated = False

    def launch(role, path):
        name = 'locker-orphan-proof-' + role + '.service'
        command = ['systemd-run', '--user', '--unit=' + name, '--collect', '--property=ExitType=cgroup',
                   '--property=KillMode=control-group', '--property=TimeoutStopSec=2s', '--property=SendSIGKILL=yes']
        keys = ('WAYLAND_DISPLAY', 'NIRI_SOCKET', 'HYPRLAND_INSTANCE_SIGNATURE', 'XDG_CURRENT_DESKTOP', 'XDG_SESSION_TYPE',
                'XDG_RUNTIME_DIR', 'DBUS_SESSION_BUS_ADDRESS', 'TMPDIR', 'HOME', 'USER', 'PATH', 'WAYLAND_DEBUG',
                'ATMOSPHERA_CONFIG_DIR', 'ATMOSPHERA_CACHE_DIR', 'ATMOSPHERA_STATE_DIR')
        command += ['--setenv=' + key + '=' + environment[key] for key in keys if key in environment]
        run(command + ['--', 'qs', '-p', str(path), '--no-color'])
        record = dict(line.split('=', 1) for line in run(['systemctl', '--user', 'show', name,
            '-p', 'InvocationID', '-p', 'ControlGroup', '-p', 'MainPID']).stdout.splitlines())
        assert record['InvocationID'] and record['ControlGroup'] and int(record['MainPID']) > 0
        record['name'] = name
        record['start'] = (Path('/proc') / record['MainPID'] / 'stat').read_text().split(') ', 1)[1].split()[19]
        units[role] = record
        return record

    def journal(role):
        text = run(['journalctl', '--user', '-b', '--no-pager', '-o', 'cat',
                    '_SYSTEMD_INVOCATION_ID=' + units[role]['InvocationID']]).stdout
        return '\n'.join(line for line in text.splitlines() if 'wl_keyboard' not in line)

    def gone(role):
        record = units[role]
        current = dict(line.split('=', 1) for line in run(['systemctl', '--user', 'show', record['name'],
            '-p', 'InvocationID', '-p', 'ActiveState']).stdout.splitlines())
        assert current['InvocationID'] in ('', record['InvocationID']), 'test unit replaced by another invocation'
        group = Path('/sys/fs/cgroup' + record['ControlGroup'])
        members = [int(pid) for pid in cgroup_pids(group)]
        process = Path('/proc') / record['MainPID']
        same = process.exists() and (process / 'stat').read_text().split(') ', 1)[1].split()[19] == record['start']
        return not members and not same and current['ActiveState'] in ('inactive', 'failed', '')

    try:
        with entry.open('x') as output:
            created = True
            output.write('''//@ pragma Env ATMOSPHERA_LOCKSCREEN=1
import QtQuick
import Quickshell
import qs.Commons
import "Quickshell/atmosphera-lockscreen" as LockerUi
ShellRoot {
  SettingsBootstrap { id: bootstrap }
  Loader { active: bootstrap.ready; sourceComponent: Component { LockerUi.LockSession {} } }
}
''')
        observer = subprocess.Popen(['python3', '-B', str(driver / 'Scripts/dev/locker-compositor-observer.py'), '--work', str(work / 'observer')],
            env=environment, stdin=subprocess.PIPE, stdout=(work / 'observer-stdout.txt').open('w'), stderr=(work / 'observer-stderr.txt').open('w'))
        wait_for(lambda: (work / 'observer/ready.json').exists())
        launch('holder', holder)
        wait_for(lambda: re.search(r'ext_session_lock_v1#\d+\.locked\(\)', journal('holder')), 15)
        launch('candidate', entry)
        wait_for(lambda: re.search(r'ext_session_lock_v1#\d+\.finished\(\)', journal('candidate')), 30)
        candidate_rejected = True
        assert 'unlock_and_destroy' not in journal('candidate')
        assert not gone('holder')
        assert run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'yes'
        run(['wtype', 'wrong-password'], env=environment)
        run(['wtype', '-k', 'Return'], env=environment)
        time.sleep(3)
        assert not gone('holder') and 'unlock_and_destroy' not in journal('holder'), 'wrong password unlocked holder'
        assert run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'yes'
        run(['wtype', '-M', 'ctrl', '-k', 'a', '-m', 'ctrl', '-k', 'BackSpace'], env=environment)
        auth_at = time.monotonic()
        with credential.open() as secret:
            run(['wtype', '-'], stdin=secret, env=environment)
        run(['wtype', '-k', 'Return'], env=environment)
        wait_for(lambda: gone('holder'), 15)
        assert run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'no'
        authenticated = True
        time.sleep(10)
        outcome = {role: {'gone': gone(role), 'identity': record} for role, record in units.items()}
        (work / 'outcome.json').write_text(json.dumps(outcome, indent=2))
        observer.stdin.close()
        assert observer.wait(timeout=10) == 0
        events = [json.loads(line) for line in (work / 'observer/events.jsonl').read_text().splitlines()]
        assert not any(event['kind'] == 'observer-error' for event in events)
        native = [event for event in events if event['kind'] == 'journal' and 'unlock_and_destroy' in event['message']]
        assert len(native) == 1 and native[0]['invocation'] == units['holder']['InvocationID']
        assert native[0]['sourceMonotonic'] >= auth_at
        assert journal('holder').count('unlock_and_destroy') == 1
        assert 'unlock_and_destroy' not in journal('candidate')
        hints = [event for event in events if event['kind'] == 'locked-hint' and not event['locked']]
        assert len(hints) == 1 and hints[0]['observed'] >= auth_at
        compositor = [event for event in events if event['kind'] == 'compositor-log' and 'unlocking session' in event['message']]
        assert len(compositor) == 1 and compositor[0]['sourceMonotonic'] >= auth_at
        assert outcome['candidate']['gone'], 'rejected locker survived 10 seconds after authenticated unlock'
        assert outcome['holder']['gone']
        (work / 'result.txt').write_text('PASS orphan-acceptance\n')
        print('PASS orphan-acceptance', work)
    finally:
        if observer is not None and observer.poll() is None:
            if not observer.stdin.closed:
                observer.stdin.close()
            assert observer.wait(timeout=15) == 0
        for role in units:
            (work / (role + '-protocol.txt')).write_text(journal(role))
        # Only the proven rejected root is safe to stop on a failed red run.
        # An authenticating/possibly-secure holder is preserved for real PAM.
        if candidate_rejected and not gone('candidate'):
            assert run(['systemctl', '--user', 'show', units['candidate']['name'], '-p', 'InvocationID', '--value']).stdout.strip() == units['candidate']['InvocationID']
            run(['systemctl', '--user', 'stop', units['candidate']['name']])
            assert gone('candidate')
        if created:
            entry.unlink()
        if authenticated and all(gone(role) for role in units):
            run(['sudo', '-n', 'chpasswd', '-e'], input='tester:' + original_hash + '\n')
            credential.unlink()
            original_shadow.unlink()
        else:
            print('Real-PAM recovery required; protected recovery files in', work, file=__import__('sys').stderr)


if __name__ == '__main__':
    main()
