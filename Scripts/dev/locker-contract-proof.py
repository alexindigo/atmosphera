#!/usr/bin/env python3
"""Actual-main Locker1 selection/error/absence proof with independent real PAM."""
import argparse
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import time

from locker_test_support import manage, recover_known_pam_hang, require_guest, run, wait_for


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--variant', choices=('normal', 'error', 'no-engagement', 'disappearing'), required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--recover-known-pam-hang', action='store_true')
    args = parser.parse_args()
    source, work = require_guest(args.work, Path(__file__).resolve().parents[2])
    sid = manage(source, {'operation': 'discover'})['session']
    assert run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'no'
    import dbus
    bus = dbus.SessionBus()
    assert not bus.name_has_owner('app.atmosphera.Locker'), 'an unrelated contract locker is present'
    stage = work / 'stage'
    run(['bash', '-eu', '-c', 'source "$1/packaging/aur/package.sh"; package', 'stage', str(source)],
        env=dict(os.environ, srcdir=str(source.parent), _gitname=source.name, pkgdir=str(stage), pkgver='0.9.3'), timeout=60)
    entry = stage / 'etc/xdg/quickshell/atmosphera/shell.qml'
    config = work / 'config'
    config.mkdir()
    (config / 'settings.json').write_text(json.dumps({'settingsVersion': 62,
        'general': {'lockScreenEnabled': True, 'lockOnSuspend': False, 'showChangelogOnStartup': False}}))
    environment = dict(os.environ, XDG_CONFIG_DIRS=str(stage / 'etc/xdg') + ':/etc/xdg',
        ATMOSPHERA_CONFIG_DIR=str(config), ATMOSPHERA_CACHE_DIR=str(work / 'cache'),
        ATMOSPHERA_STATE_DIR=str(work / 'state'), WAYLAND_DEBUG='client')
    units = {}
    observer = None
    authenticated = False
    password = secrets.token_hex(16)
    credential = work / 'credential'
    original_shadow = work / 'original-shadow-hash'
    original_hash = run(['sudo', '-n', 'getent', 'shadow', 'tester']).stdout.split(':')[1]
    for path, value in ((credential, password), (original_shadow, original_hash)):
        path.touch(mode=0o600)
        path.write_text(value)
    run(['sudo', '-n', 'chpasswd'], input='tester:' + password + '\n')

    def status(name):
        fields = ('InvocationID', 'ControlGroup', 'MainPID', 'ActiveState', 'Result')
        result = subprocess.run(['systemctl', '--user', 'show', name,
            *[value for field in fields for value in ('-p', field)]], text=True, capture_output=True, timeout=10)
        assert result.returncode == 0 or 'not found' in result.stderr or 'could not be found' in result.stderr, result.stderr
        values = dict(row.split('=', 1) for row in result.stdout.splitlines() if '=' in row)
        return {field: values.get(field, '') for field in fields}

    def launch(role, command):
        unit = 'locker-contract-' + role + '.service'
        keys = ('WAYLAND_DISPLAY', 'NIRI_SOCKET', 'HYPRLAND_INSTANCE_SIGNATURE', 'XDG_CURRENT_DESKTOP', 'XDG_SESSION_TYPE',
            'XDG_RUNTIME_DIR', 'DBUS_SESSION_BUS_ADDRESS', 'TMPDIR', 'HOME', 'USER', 'PATH', 'XDG_CONFIG_DIRS',
            'ATMOSPHERA_CONFIG_DIR', 'ATMOSPHERA_CACHE_DIR', 'ATMOSPHERA_STATE_DIR', 'WAYLAND_DEBUG')
        run(['systemd-run', '--user', '--collect', '--unit=' + unit, '--property=KillMode=control-group',
            '--property=TimeoutStopSec=2s', '--property=ExitType=cgroup',
            *['--setenv=' + key + '=' + environment[key] for key in keys if key in environment], '--', *command])
        identity = status(unit)
        assert identity['InvocationID'] and identity['ControlGroup'] and int(identity['MainPID']) > 0
        start = (Path('/proc') / identity['MainPID'] / 'stat').read_text().split(') ', 1)[1].split()[19]
        units[role] = dict(identity, name=unit, pidStart=start)
        (work / 'independent-units.json').write_text(json.dumps(units, indent=2))

    def journal(role):
        text = run(['journalctl', '--user', '-b', '--no-pager', '-o', 'cat',
            '_SYSTEMD_INVOCATION_ID=' + units[role]['InvocationID']]).stdout
        return '\n'.join(line for line in text.splitlines() if 'wl_keyboard' not in line)

    def inspect():
        return manage(source, {'operation': 'inspect', 'session': sid})

    def ipc(*command):
        return run(['qs', 'ipc', '-p', str(entry), 'call', *command], env=environment).stdout.strip()

    def same_live(role):
        saved = units[role]
        now = status(saved['name'])
        assert now['InvocationID'] in ('', saved['InvocationID']), 'independent fixture unit replaced'
        return now['InvocationID'] == saved['InvocationID'] and now['ActiveState'] == 'active'

    try:
        observer = subprocess.Popen(['python3', '-B', str(source / 'Scripts/dev/locker-compositor-observer.py'),
            '--work', str(work / 'observer')], stdin=subprocess.PIPE, env=environment,
            stdout=(work / 'observer-stdout.txt').open('w'), stderr=(work / 'observer-stderr.txt').open('w'))
        wait_for(lambda: (work / 'observer/ready.json').exists())
        fixture = work / 'fixture'
        fixture.mkdir()
        launch('fixture', ['python3', '-B', str(source / 'Scripts/dev/fixtures/locker-contract-service.py'),
            '--variant', args.variant, '--work', str(fixture)])
        wait_for(lambda: (fixture / 'ready.json').exists())
        assert bus.name_has_owner('app.atmosphera.Locker')
        launch('main', ['qs', '-p', str(entry), '--no-color'])
        wait_for(lambda: 'contract locker appeared' in journal('main'), 20)
        def main_ready():
            result = subprocess.run(['qs', 'ipc', '-p', str(entry), 'call', 'state', 'all'],
                env=environment, text=True, capture_output=True, timeout=5)
            return result.returncode == 0 and '"settings"' in result.stdout
        wait_for(main_ready, 20)
        ipc('lockScreen', 'lock')
        def engaged():
            d = inspect()['descriptor']
            if not d or d['phase'] == 'settled' or d['snapshot']['adapter'] != 'contract':
                return False
            current = json.loads(ipc('lockOwner', 'status'))
            return current['state'] == 'engaged-unconfirmed(external)' if args.variant == 'normal' else current['secure']
        wait_for(engaged, 15)
        first = inspect()
        assert first['descriptor']['contractRequested'] and 'real' not in first['descriptor']['units']
        assert json.loads((fixture / 'calls.json').read_text())['calls'] == 1
        if args.variant == 'normal':
            assert not json.loads(ipc('lockOwner', 'status'))['secure'], 'contract presence/refusal was treated as a secure ack'
            assert re.search(r'ext_session_lock_v1#\d+\.locked\(\)', journal('fixture'))
            assert same_live('fixture')
            assert first['units']['emergency']['gone']
        else:
            assert first['descriptor']['units']['emergency']['client']['secure']
            emergency_at = first['descriptor']['units']['emergency']['startedAt']
            if args.variant in ('error', 'disappearing'):
                assert emergency_at < first['descriptor']['emergencyAt'], 'failed contract did not trigger immediate emergency'
            else:
                assert emergency_at >= first['descriptor']['emergencyAt'], 'contract presence was treated as failed exec'
            if args.variant == 'disappearing':
                assert (fixture / 'voluntary-exit.json').exists() and not bus.name_has_owner('app.atmosphera.Locker')
            else:
                assert same_live('fixture'), 'owner terminated independent contract service'
        (work / 'first-secure.json').write_text(json.dumps(first, indent=2))
        generation = first['descriptor']['generation']
        ipc('lockScreen', 'lock')
        time.sleep(.5)
        assert inspect()['descriptor']['generation'] == generation
        assert json.loads((fixture / 'calls.json').read_text())['calls'] == 1
        run(['wtype', 'wrong-password'], env=environment)
        run(['wtype', '-k', 'Return'], env=environment)
        time.sleep(3)
        assert run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'yes'
        holder_role = 'fixture' if args.variant == 'normal' else None
        if holder_role:
            assert same_live(holder_role) and 'unlock_and_destroy' not in journal(holder_role)
        else:
            assert inspect()['descriptor']['units']['emergency']['client']['secure']
            if args.recover_known_pam_hang:
                recover_known_pam_hang(source, sid, 'emergency', work)
        run(['wtype', '-M', 'ctrl', '-k', 'a', '-m', 'ctrl', '-k', 'BackSpace'], env=environment)
        auth_at = time.monotonic()
        with credential.open() as secret:
            run(['wtype', '-'], stdin=secret, env=environment)
        run(['wtype', '-k', 'Return'], env=environment)
        wait_for(lambda: inspect()['descriptor']['phase'] == 'settled', 15)
        final = inspect()
        assert all(unit['gone'] and not unit['members'] for unit in final['units'].values())
        assert run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'no'
        authenticated = True
        if args.variant != 'disappearing':
            assert same_live('fixture'), 'owner cleanup terminated independently managed service'
        time.sleep(10)
        assert inspect()['descriptor']['phase'] == 'settled'
        assert inspect()['descriptor']['generation'] == generation
        observer.stdin.close()
        assert observer.wait(timeout=10) == 0
        events = [json.loads(line) for line in (work / 'observer/events.jsonl').read_text().splitlines()]
        assert not any(event['kind'] == 'observer-error' for event in events)
        for kind, text in (('journal', 'unlock_and_destroy'), ('compositor-log', 'unlocking session')):
            matching = [event for event in events if event['kind'] == kind and text in event['message']]
            assert len(matching) == 1 and matching[0]['sourceMonotonic'] >= auth_at, (kind, matching)
            if kind == 'journal':
                expected = units['fixture']['InvocationID'] if args.variant == 'normal' else final['descriptor']['units']['emergency']['identity']['InvocationID']
                assert matching[0]['invocation'] == expected, 'non-holder protocol unlock'
        hints = [event for event in events if event['kind'] == 'locked-hint' and not event['locked']]
        assert len(hints) == 1 and hints[0]['observed'] >= auth_at
        (work / 'final.json').write_text(json.dumps(final, indent=2))
        (work / 'result.txt').write_text('PASS contract-' + args.variant + '\n')
        print('PASS contract-' + args.variant, work)
    finally:
        if observer is not None and observer.poll() is None:
            if not observer.stdin.closed:
                observer.stdin.close()
            assert observer.wait(timeout=15) == 0
        for role in ('main', 'fixture'):
            if role not in units:
                continue
            saved = units[role]
            (work / (role + '-protocol.txt')).write_text(journal(role))
            if role == 'fixture' and not authenticated:
                continue  # Preserve a possibly secure independent holder.
            now = status(saved['name'])
            assert now['InvocationID'] in ('', saved['InvocationID'])
            if now['InvocationID']:
                run(['systemctl', '--user', 'stop', saved['name']])
            group = Path('/sys/fs/cgroup' + saved['ControlGroup'])
            if group.exists():
                assert not any(file.read_text().split() for file in group.rglob('cgroup.procs'))
            process = Path('/proc') / saved['MainPID'] / 'stat'
            assert not process.exists() or process.read_text().split(') ', 1)[1].split()[19] != saved['pidStart']
            if role == 'main' and authenticated and args.variant != 'disappearing':
                assert same_live('fixture'), 'main-root cleanup stopped independent contract fixture'
                (work / 'fixture-after-owner-stop.json').write_text(json.dumps(status(units['fixture']['name']), indent=2))
        if authenticated:
            (work / 'independent-cleanup.json').write_text(json.dumps({role: status(saved['name']) for role, saved in units.items()}, indent=2))
            run(['sudo', '-n', 'chpasswd', '-e'], input='tester:' + original_hash + '\n')
            credential.unlink()
            original_shadow.unlink()
        else:
            print('Real-PAM recovery required; protected files in', work, file=__import__('sys').stderr)


if __name__ == '__main__':
    main()
