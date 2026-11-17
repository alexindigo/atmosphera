#!/usr/bin/env python3
"""Actual-main Locker1 v1/v2 selection, observation and failure proof with real PAM.

`capable` is an independent version 2 service backed by a native lock client;
`shipped` is the standalone emergency lock serving version 2 itself. Version 1
variants keep the original contract. Nothing here forges a secure or unlock
fact into the owner: forged/stale signals are sent only to prove rejection.
"""
import argparse
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import subprocess
import time

from locker_test_support import cgroup_pids, compositor_locked, compositor_transitions, manage, recover_known_pam_hang, require_guest, run, wait_for


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--variant', choices=('normal', 'error', 'no-engagement', 'disappearing', 'capable', 'shipped'), required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--recover-known-pam-hang', action='store_true')
    args = parser.parse_args()
    source, work = require_guest(args.work, Path(__file__).resolve().parents[2])
    sid = manage(source, {'operation': 'discover'})['session']
    assert run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'no'
    import dbus
    import dbus.lowlevel
    bus = dbus.SessionBus()
    assert not bus.name_has_owner('app.atmosphera.Locker'), 'an unrelated contract locker is present'
    hyprland = bool(os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'))
    native_client = None
    if args.variant == 'capable':
        protocol = '/usr/share/wayland-protocols/staging/ext-session-lock/ext-session-lock-v1.xml'
        header, code = work / 'session-lock-client.h', work / 'session-lock-protocol.c'
        run(['wayland-scanner', 'client-header', protocol, str(header)])
        run(['wayland-scanner', 'private-code', protocol, str(code)])
        flags = shlex.split(run(['pkg-config', '--cflags', '--libs', 'wayland-client', 'xkbcommon', 'pam']).stdout)
        native_client = work / 'native-locker'
        compiled = run(['cc', '-Wall', '-Wextra', '-Werror', '-I' + str(work),
            str(source / 'Scripts/dev/fixtures/locker-opaque-delayed.c'), str(code), '-o', str(native_client), *flags], timeout=60)
        (work / 'native-build.txt').write_text(compiled.stdout + compiled.stderr)

    def name_owner():
        try:
            return str(bus.get_name_owner('app.atmosphera.Locker'))
        except dbus.exceptions.DBusException:
            return ''

    def owner_pid(owner):
        return int(bus.call_blocking('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus',
            'GetConnectionUnixProcessID', 's', (owner,)))

    def locker_proxy():
        return bus.get_object('app.atmosphera.Locker', '/app/atmosphera/Locker')
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
        assert identity['InvocationID'] and identity['ControlGroup'] and int(identity['MainPID']) > 0, identity
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

    def owner_status():
        return json.loads(ipc('lockOwner', 'status'))

    def start_main(role):
        launch(role, ['qs', '-p', str(entry), '--no-color'])
        wait_for(lambda: 'contract locker appeared' in journal(role), 20)
        def main_ready():
            result = subprocess.run(['qs', 'ipc', '-p', str(entry), 'call', 'state', 'all'],
                env=environment, text=True, capture_output=True, timeout=5)
            return result.returncode == 0 and '"settings"' in result.stdout
        wait_for(main_ready, 20)

    def stop_main(role):
        run(['systemctl', '--user', 'stop', units[role]['name']], timeout=20)
        wait_for(lambda: not same_live(role), 10)

    def type_password(text_or_file):
        run(['wtype', '-M', 'ctrl', '-k', 'a', '-m', 'ctrl', '-k', 'BackSpace'], env=environment)
        if isinstance(text_or_file, Path):
            with text_or_file.open() as secret:
                run(['wtype', '-'], stdin=secret, env=environment)
        else:
            run(['wtype', text_or_file], env=environment)
        run(['wtype', '-k', 'Return'], env=environment)

    def forge(member, request_id):
        # Sent from this proof's own connection, not the accepting owner.
        message = dbus.lowlevel.SignalMessage('/app/atmosphera/Locker', 'app.atmosphera.Locker1', member)
        message.append(request_id, signature='s')
        bus.send_message(message)
        bus.flush()

    contract_v2 = args.variant in ('capable', 'shipped')
    holder_role = 'fixture' if args.variant in ('normal', 'capable') else 'standalone' if args.variant == 'shipped' else None
    fixture_owner = ''
    try:
        observer = subprocess.Popen(['python3', '-B', str(source / 'Scripts/dev/locker-compositor-observer.py'),
            '--work', str(work / 'observer')], stdin=subprocess.PIPE, env=environment,
            stdout=(work / 'observer-stdout.txt').open('w'), stderr=(work / 'observer-stderr.txt').open('w'))
        wait_for(lambda: (work / 'observer/ready.json').exists())
        assert not compositor_locked(work, sid), 'existing compositor lock'
        fixture = work / 'fixture'
        fixture.mkdir()
        if args.variant == 'shipped':
            # The user's own standalone shipped locker, started outside the owner.
            launch('standalone', ['env', '-u', 'ATMOSPHERA_LOCK_SESSION', '-u', 'ATMOSPHERA_LOCK_GENERATION',
                '-u', 'ATMOSPHERA_LOCK_ROLE', '-u', 'ATMOSPHERA_LOCK_ADAPTER', 'qs', '-c', 'atmosphera-emergency-lock'])
            wait_for(lambda: re.search(r'ext_session_lock_v1#\d+\.locked\(\)', journal('standalone')), 20)
            wait_for(name_owner, 10)
            fixture_owner = name_owner()
            standalone_pid = int(units['standalone']['MainPID'])
            assert owner_pid(fixture_owner) == standalone_pid, 'shipped locker does not own its contract name'
            version = locker_proxy().Get('app.atmosphera.Locker1', 'Version', dbus_interface=dbus.PROPERTIES_IFACE)
            assert int(version) == 2, version
            (fixture / 'ready.json').write_text(json.dumps({'owner': fixture_owner, 'pid': standalone_pid, 'version': int(version)}))
        else:
            command = ['python3', '-B', str(source / 'Scripts/dev/fixtures/locker-contract-service.py'),
                '--variant', args.variant, '--work', str(fixture)]
            if native_client:
                command += ['--native-client', str(native_client)]
            launch('fixture', command)
            wait_for(lambda: (fixture / 'ready.json').exists())
            fixture_owner = json.loads((fixture / 'ready.json').read_text())['owner']
            assert name_owner() == fixture_owner
        start_main('main')
        main_role = 'main'
        ipc('lockScreen', 'lock')
        def engaged():
            d = inspect()['descriptor']
            if not d or d['phase'] == 'settled' or d['snapshot']['adapter'] != 'contract':
                return False
            current = owner_status()
            if args.variant == 'normal':
                return current['state'] == 'engaged-unconfirmed(external)'
            if contract_v2:
                return current['secure'] and current['holder'] == 'external' and current['state'] == 'engaged'
            return current['secure']
        wait_for(engaged, 15)
        first = inspect()
        d = first['descriptor']
        assert d['contractRequested'] and 'real' not in d['units']
        if args.variant != 'shipped':
            assert json.loads((fixture / 'calls.json').read_text())['calls'] == 1
        if args.variant == 'normal':
            assert not owner_status()['secure'], 'contract presence/refusal was treated as a secure ack'
            assert re.search(r'ext_session_lock_v1#\d+\.locked\(\)', journal('fixture'))
            assert same_live('fixture')
            assert first['units']['emergency']['gone']
            assert d['units']['emergency'].get('protocolOutcome') == 'finished', 'refusal needs the durable native report'
            assert d.get('contractVersion') == 1 and not d.get('contractSecured')
        elif contract_v2:
            assert d['contractVersion'] == 2 and d['contractSecured'] and d['contractOwner'] == fixture_owner
            assert re.fullmatch(r'[0-9a-f]{32}', d['contractRequestId']) and d['contractRequestId'] != d['generation']
            assert 'emergency' not in d['units'], 'a confirmed v2 lock still needed an emergency probe'
            state = locker_proxy().RequestState(d['contractRequestId'], dbus_interface='app.atmosphera.Locker1')
            assert str(state) == 'secure', state
        else:
            assert d['units']['emergency']['client']['secure']
            emergency_at = d['units']['emergency']['startedAt']
            if args.variant in ('error', 'disappearing'):
                assert emergency_at < d['emergencyAt'], 'failed contract did not trigger immediate emergency'
            else:
                assert emergency_at >= d['emergencyAt'], 'contract presence was treated as failed exec'
            if args.variant == 'disappearing':
                assert (fixture / 'voluntary-exit.json').exists() and not bus.name_has_owner('app.atmosphera.Locker')
                # The owner's managed emergency lock must not claim the free name.
                assert name_owner() == '', 'managed emergency lock claimed app.atmosphera.Locker'
            else:
                assert same_live('fixture'), 'owner terminated independent contract service'
        if args.variant != 'disappearing':
            assert name_owner() == fixture_owner, 'a probe or child took the independent contract name'
        (work / 'first-secure.json').write_text(json.dumps(first, indent=2))
        generation = d['generation']
        ipc('lockScreen', 'lock')
        time.sleep(.5)
        assert inspect()['descriptor']['generation'] == generation
        if args.variant != 'shipped':
            assert json.loads((fixture / 'calls.json').read_text())['calls'] == 1
        if contract_v2:
            request_id = d['contractRequestId']
            stale = secrets.token_hex(16)
            forge('Unlocked', request_id)
            forge('Secured', stale)
            if args.variant == 'capable':
                locker_proxy().Emit('Unlocked', stale, dbus_interface='app.atmosphera.Fixture')
            time.sleep(1.5)
            after = inspect()['descriptor']
            assert after['phase'] not in ('unlocking', 'settled') and not after.get('contractUnlocked')
            assert not after.get('sessionUnlockObserved') and 'emergency' not in after['units']
            assert owner_status()['secure'], 'forged or stale Locker1 evidence changed the owner'
            (work / 'stale-evidence.json').write_text(json.dumps({'forgedRealId': True, 'staleId': stale, 'descriptor': after}, indent=2))
        type_password('wrong-password')
        time.sleep(3)
        assert compositor_locked(work, sid)
        if holder_role:
            assert same_live(holder_role) and 'unlock_and_destroy' not in journal(holder_role)
        else:
            assert inspect()['descriptor']['units']['emergency']['client']['secure']
            if args.recover_known_pam_hang:
                recover_known_pam_hang(source, sid, 'emergency', work)
        if args.variant == 'capable':
            # Restart reconciliation: the new shell queries the accepted owner.
            stop_main('main')
            start_main('main2')
            main_role = 'main2'
            wait_for(lambda: owner_status()['secure'] and owner_status()['holder'] == 'external', 15)
            assert any(json.loads(line)['event'] == 'request-state' for line in (fixture / 'events.jsonl').read_text().splitlines())
            # Miss the Unlocked signal entirely: no shell runs during auth.
            stop_main('main2')
            main_role = None
        auth_at = time.monotonic()
        type_password(credential)
        if args.variant == 'capable':
            wait_for(lambda: '"Unlocked"' in (fixture / 'events.jsonl').read_text(), 15)
            wait_for(lambda: not compositor_locked(work, sid), 10)
            assert inspect()['descriptor']['phase'] not in ('unlocking', 'settled')
            start_main('main3')
            main_role = 'main3'
        if args.variant == 'normal' and hyprland:
            # Documented version 1 limitation: Hyprland has no LockedHint and
            # Quickshell no lock-notify client, so the owner cannot observe the
            # independent service's own unlock. It must stay unconfirmed and
            # never touch the service or probe on its own.
            wait_for(lambda: not compositor_locked(work, sid), 15)
            time.sleep(5)
            limited = inspect()
            assert owner_status()['state'] == 'engaged-unconfirmed(external)' and not owner_status()['secure']
            assert limited['descriptor']['units']['emergency']['identity'] == d['units']['emergency']['identity'], 'unexpected probe'
            assert same_live('fixture')
            (work / 'v1-hyprland-limitation.json').write_text(json.dumps(limited, indent=2))
            # Test cleanup only: supply the observation the product cannot make.
            manage(source, {'operation': 'note', 'session': sid, 'generation': generation, 'sessionUnlockObserved': True})
            (work / 'harness-supplied-unlock-observation.txt').write_text(
                'Harness note after native Hyprland unlock, for cleanup only; not product behavior.\n')
        wait_for(lambda: inspect()['descriptor']['phase'] == 'settled', 15)
        final = inspect()
        assert all(unit['gone'] and not unit['members'] for unit in final['units'].values())
        assert not compositor_locked(work, sid)
        authenticated = True
        if contract_v2:
            assert final['descriptor']['contractUnlocked'] and 'emergency' not in final['descriptor']['units'], 'v2 unlock was followed by a probe'
        if args.variant == 'shipped':
            wait_for(lambda: not same_live('standalone'), 10)
            assert name_owner() == '', 'shipped locker kept its contract name after unlock'
        elif args.variant != 'disappearing':
            assert same_live('fixture'), 'owner cleanup terminated independently managed service'
        time.sleep(10)
        assert inspect()['descriptor']['phase'] == 'settled'
        assert inspect()['descriptor']['generation'] == generation
        observer.stdin.close()
        assert observer.wait(timeout=10) == 0
        events = [json.loads(line) for line in (work / 'observer/events.jsonl').read_text().splitlines()]
        assert not any(event['kind'] == 'observer-error' for event in events)
        for kind, text in (('journal', 'unlock_and_destroy'), ('compositor-log', 'unlocking session')):
            if kind == 'compositor-log' and hyprland:
                continue  # Hyprland's independent native notification is checked below.
            matching = [event for event in events if event['kind'] == kind and text in event['message']]
            if kind == 'journal' and args.variant == 'capable':
                # The native C client does not use libwayland debug; check its own exit.
                assert [json.loads(line) for line in (fixture / 'events.jsonl').read_text().splitlines()
                        if json.loads(line)['event'] == 'native-exit'][-1]['value'] == 0
                continue
            assert len(matching) == 1 and matching[0]['sourceMonotonic'] >= auth_at, (kind, matching)
            if kind == 'journal':
                expected = (units[holder_role]['InvocationID'] if holder_role
                    else final['descriptor']['units']['emergency']['identity']['InvocationID'])
                assert matching[0]['invocation'] == expected, 'non-holder protocol unlock'
        hints = [event for event in compositor_transitions(events) if not event['locked']]
        assert len(hints) == 1 and hints[0]['observed'] >= auth_at
        (work / 'final.json').write_text(json.dumps(final, indent=2))
        (work / 'result.txt').write_text('PASS contract-' + args.variant + '\n')
        print('PASS contract-' + args.variant, work)
    finally:
        if observer is not None and observer.poll() is None:
            if not observer.stdin.closed:
                observer.stdin.close()
            assert observer.wait(timeout=15) == 0
        for role in ('main', 'main2', 'main3', 'fixture', 'standalone'):
            if role not in units:
                continue
            saved = units[role]
            (work / (role + '-protocol.txt')).write_text(journal(role))
            if role in ('fixture', 'standalone') and not authenticated:
                continue  # Preserve a possibly secure independent holder.
            now = status(saved['name'])
            assert now['InvocationID'] in ('', saved['InvocationID'])
            if now['InvocationID']:
                run(['systemctl', '--user', 'stop', saved['name']])
            group = Path('/sys/fs/cgroup' + saved['ControlGroup'])
            if group.exists():
                assert not cgroup_pids(group)
            process = Path('/proc') / saved['MainPID'] / 'stat'
            assert not process.exists() or process.read_text().split(') ', 1)[1].split()[19] != saved['pidStart']
            if role.startswith('main') and authenticated and args.variant not in ('disappearing', 'shipped'):
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
