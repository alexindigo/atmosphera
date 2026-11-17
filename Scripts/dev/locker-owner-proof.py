#!/usr/bin/env python3
"""Actual owner/unit/PAM integration. Not the complete acceptance matrix.

The test root uses the real QML singleton and install assembly. No synthetic
authentication or secure event is injected. Only its own root is restarted.
"""
import argparse
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import shutil
import subprocess
import threading
import time

from locker_test_support import manage, recover_known_pam_hang, require_guest, run, wait_for


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--case', choices=('fast', 'adoption', 'slow', 'external', 'opaque', 'opaque-holder', 'opaque-sleep', 'opaque-crash', 'opaque-race', 'opaque-withdraw', 'hooks', 'intent'), default='fast')
    parser.add_argument('--external-variant', choices=('existing', 'missing', 'slow5', 'slow40', 'nonzero', 'crash', 'pipeline', 'daemonizing', 'term-resistant', 'daemonizing-holder'), default='existing')
    parser.add_argument('--delay', type=float, default=5)
    parser.add_argument('--emergency-auth-before-ready', action='store_true')
    parser.add_argument('--ui', choices=('builtin', 'demo'), default='builtin')
    parser.add_argument('--verify-settings', action='store_true')
    parser.add_argument('--main-shell', action='store_true', help='Use the actual main shell for fast/adoption and public lock IPC')
    parser.add_argument('--recover-known-pam-hang', action='store_true', help='Record and recover only a verified native PAM syslog deadlock; never the secure holder')
    args = parser.parse_args()
    if args.main_shell and args.case not in ('fast', 'adoption', 'slow', 'external'):
        parser.error('--main-shell currently proves fast/adoption/slow/external; other main-shell acceptance remains separate')
    if args.case == 'slow' and args.delay < 5:
        parser.error('slow coverage requires at least 5s; boundary ordering is a separate case')
    if args.emergency_auth_before_ready and args.case != 'slow':
        parser.error('--emergency-auth-before-ready belongs to --case slow')
    source, work = require_guest(args.work, Path(__file__).resolve().parents[2])
    if args.ui == 'demo' or (args.case == 'slow' and args.delay < 30 and not args.emergency_auth_before_ready):
        assert os.environ.get('LOCKER_FRAMEBUFFER_PORT') and os.environ.get('LOCKER_TEST_VM_NAME'), 'render/input proof requires the named VM console forward'
    sid = manage(source, {'operation': 'discover'})['session']
    assert run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'no', 'existing holder'
    stage = work / 'stage'
    run(['bash', '-eu', '-c', 'source "$1/packaging/aur/package.sh"; package', 'stage', str(source)],
        env=dict(os.environ, srcdir=str(source.parent), _gitname=source.name, pkgdir=str(stage), pkgver='0.9.3'), timeout=60)
    root = stage / 'etc/xdg/quickshell/atmosphera'
    entry = root / ('shell.qml' if args.main_shell else 'locker-owner-proof.qml')
    if not args.main_shell:
        entry.write_text((source / 'Scripts/dev/fixtures/locker-owner.qml').read_text())
    settings = work / 'config'
    settings.mkdir()
    configuration = {'settingsVersion': 62,
        'general': {'lockScreenEnabled': True, 'lockScreenPlugin': 'demo-custom-lockscreen' if args.ui == 'demo' else 'default',
                    'lockOnSuspend': False, 'showChangelogOnStartup': False}}
    marker = work / 'hook-events'
    if args.case == 'opaque':
        configuration['general']['externalLockCommand'] = 'sleep 40'
    unconfirmed = args.case in ('opaque-holder', 'opaque-sleep', 'opaque-crash', 'opaque-race', 'opaque-withdraw')
    if unconfirmed:
        # Actual independently authenticating client, deliberately not our
        # generation protocol. Its unit activity/hint must not count as secure.
        configuration['general']['externalLockCommand'] = ('env -u ATMOSPHERA_LOCK_SESSION -u ATMOSPHERA_LOCK_GENERATION '
            '-u ATMOSPHERA_LOCK_ROLE -u ATMOSPHERA_LOCK_ADAPTER qs -c atmosphera-emergency-lock')
    external_members = work / 'external-members'
    external_executed = work / 'external-delayed-exec'
    if args.case == 'external':
        standalone = ('env -u ATMOSPHERA_LOCK_SESSION -u ATMOSPHERA_LOCK_GENERATION '
            '-u ATMOSPHERA_LOCK_ROLE -u ATMOSPHERA_LOCK_ADAPTER qs -c atmosphera-emergency-lock')
        workload = 'python3 ' + shlex.quote(str(source / 'Scripts/dev/fixtures/locker-unit-workload.py'))
        workload += ' --work ' + shlex.quote(str(external_members))
        external_members.mkdir()
        commands = {
            'existing': standalone,
            'missing': 'atmosphera-nonexistent-locker-acceptance',
            'nonzero': 'exit 17',
            'crash': 'kill -KILL $$',
            'pipeline': standalone + ' | cat',
            'daemonizing': workload + ' --daemonize',
            'term-resistant': workload + ' --resist-term',
            'daemonizing-holder': standalone + ' & exit 0',
        }
        for delay in (5, 40):
            commands['slow' + str(delay)] = ('sleep ' + str(delay) + '; printf executed > '
                + shlex.quote(str(external_executed)) + '; exec ' + standalone)
        configuration['general']['externalLockCommand'] = commands[args.external_variant]
        unconfirmed = args.external_variant in ('existing', 'pipeline', 'daemonizing-holder')
    if args.case == 'hooks':
        configuration['hooks'] = {'enabled': True, 'handlers': {
            'lockAction': {'command': 'printf pre >> ' + shlex.quote(str(marker)) + '; sleep 1', 'exclusive': False},
            'screenOffAction': {'command': 'sleep 0.5', 'exclusive': False}}, 'listeners': {
            'screenLock': 'printf lock >> ' + shlex.quote(str(marker)) + '; sleep 40',
            'screenUnlock': 'printf unlock >> ' + shlex.quote(str(marker))}}
    (settings / 'settings.json').write_text(json.dumps(configuration))
    environment = dict(os.environ, XDG_CONFIG_DIRS=str(stage / 'etc/xdg') + ':/etc/xdg',
                       ATMOSPHERA_CONFIG_DIR=str(settings), WAYLAND_DEBUG='client',
                       ATMOSPHERA_CACHE_DIR=str(work / 'cache'), ATMOSPHERA_STATE_DIR=str(work / 'state'))
    if args.case in ('slow', 'opaque-race', 'opaque-withdraw'):
        binary = work / 'bin/qs'
        binary.parent.mkdir()
        shutil.copyfile(source / 'Scripts/dev/fixtures/locker-qs-barrier.py', binary)
        binary.chmod(0o700)
        environment['PATH'] = str(binary.parent) + ':' + os.environ['PATH']
        if args.case == 'slow':
            (work / 'delay-real').write_text(str(args.delay))
            if args.delay < 30 and not args.emergency_auth_before_ready:
                adapter_binary = binary.with_name('python3')
                shutil.copyfile(source / 'Scripts/dev/fixtures/locker-adapter-barrier.py', adapter_binary)
                adapter_binary.chmod(0o700)
    unit = 'locker-owner-proof.service'
    password = secrets.token_hex(16)
    credential = work / 'credential'
    credential.touch(mode=0o600)
    credential.write_text(password)
    original_hash = run(['sudo', '-n', 'getent', 'shadow', 'tester']).stdout.split(':')[1]
    original_shadow = work / 'original-shadow-hash'
    original_shadow.touch(mode=0o600)
    original_shadow.write_text(original_hash)
    run(['sudo', '-n', 'chpasswd'], input='tester:' + password + '\n')
    owner = None
    observer = None
    owner_stopped = False
    unlocked = False
    sentinel_identity = None
    sentinel_unit = 'locker-desktop-sentinel.service'

    def inspect():
        return manage(source, {'operation': 'inspect', 'session': sid})

    def ipc(*command):
        if args.main_shell and command[0] == 'lockerProof':
            if command[1] == 'lock':
                command = ('lockScreen', 'lock')
            elif command[1] == 'exit':
                assert run(['systemctl', '--user', 'show', unit, '-p', 'InvocationID', '--value']).stdout.strip() == owner
                run(['systemctl', '--user', 'stop', unit])
                return ''
            elif command[1] == 'fingerprintPreference':
                # A normal external preference edit exercises the real main
                # owner's watch/admission/publication, not a synthetic signal.
                path = settings / 'settings/general.json'
                data = json.loads(path.read_text()) if path.exists() else {}
                data['allowPasswordWithFprintd'] = command[2] == 'true'
                temporary = path.with_suffix('.proof-new')
                temporary.write_text(json.dumps(data))
                temporary.replace(path)
                return ''
            else:
                raise AssertionError('No main-shell harness mapping for ' + str(command))
        return run(['qs', 'ipc', '-p', str(entry), 'call', *command], env=environment).stdout.strip()

    def authenticate():
        with credential.open() as stream:
            run(['wtype', '-'], stdin=stream, env=environment)
        run(['wtype', '-k', 'Return'], env=environment)

    def start():
        nonlocal owner
        launch = ['systemd-run', '--user', '--unit=' + unit, '--collect', '--property=KillMode=control-group', '--property=TimeoutStopSec=2s']
        keys = ('WAYLAND_DISPLAY', 'NIRI_SOCKET', 'HYPRLAND_INSTANCE_SIGNATURE', 'XDG_CURRENT_DESKTOP',
                'XDG_SESSION_TYPE', 'XDG_RUNTIME_DIR', 'DBUS_SESSION_BUS_ADDRESS', 'TMPDIR', 'HOME', 'USER',
                'XDG_CONFIG_DIRS', 'ATMOSPHERA_CONFIG_DIR', 'ATMOSPHERA_CACHE_DIR', 'ATMOSPHERA_STATE_DIR', 'WAYLAND_DEBUG', 'PATH')
        launch += ['--setenv=' + key + '=' + environment[key] for key in keys if key in environment]
        run(launch + ['--', 'qs', '-p', str(entry), '--no-color'])
        owner = run(['systemctl', '--user', 'show', unit, '-p', 'InvocationID', '--value']).stdout.strip()
        def ready():
            endpoint = ['state', 'all'] if args.main_shell else ['lockerProof', 'ready']
            result = subprocess.run(['qs', 'ipc', '-p', str(entry), 'call', *endpoint],
                                    capture_output=True, text=True, env=environment, timeout=5)
            if not args.main_shell:
                return result.returncode == 0 and result.stdout.strip() == 'true'
            if result.returncode:
                return False
            try:
                snapshot = json.loads(result.stdout)
                return isinstance(snapshot, dict) and isinstance(snapshot.get('settings'), dict) and isinstance(snapshot.get('state'), dict)
            except ValueError:
                return False
        wait_for(ready, 20)

    try:
        observer = subprocess.Popen(['python3', '-B', str(source / 'Scripts/dev/locker-compositor-observer.py'),
                                     '--work', str(work / 'observer')], stdin=subprocess.PIPE,
                                    stdout=(work / 'observer-stdout.txt').open('w'),
                                    stderr=(work / 'observer-stderr.txt').open('w'), env=environment)
        wait_for(lambda: (work / 'observer/ready.json').exists(), 10)
        start()
        if args.case == 'slow' and args.delay < 30 and not args.emergency_auth_before_ready:
            from locker_framebuffer import Framebuffer
            sentinel_entry = work / 'desktop-sentinel.qml'
            shutil.copyfile(source / 'Scripts/dev/fixtures/locker-sentinel.qml', sentinel_entry)
            launch = ['systemd-run', '--user', '--unit=' + sentinel_unit, '--collect', '--property=KillMode=control-group']
            launch += ['--setenv=' + key + '=' + environment[key] for key in ('WAYLAND_DISPLAY', 'XDG_RUNTIME_DIR', 'DBUS_SESSION_BUS_ADDRESS', 'TMPDIR')]
            run(launch + ['--', 'qs', '-p', str(sentinel_entry)])
            sentinel_identity = run(['systemctl', '--user', 'show', sentinel_unit, '-p', 'InvocationID', '--value']).stdout.strip()
            console = Framebuffer()
            try:
                def visible_sentinel():
                    console.capture(work / 'unlocked-before.ppm')
                    return all(console.sentinel_corners())
                wait_for(visible_sentinel)
            finally:
                console.close()
        old_generation = (inspect().get('descriptor') or {}).get('generation')
        intent = args.case in ('intent', 'opaque-holder', 'opaque-sleep')
        ipc('lockerProof', 'lockAndSuspend' if intent else 'lock')
        if intent:
            ipc('lockerProof', 'lockAndSuspend')
            assert json.loads(ipc('lockerProof', 'completions'))['suspend'] == 0, 'suspend before secure'
        if args.case == 'hooks':
            ipc('lockerProof', 'overlapHook')
            ipc('lockerProof', 'lockViaHook')
        expected_role = 'emergency' if args.case in ('opaque', 'slow') or (args.case == 'external' and not unconfirmed) else 'real'
        def owner_status():
            return json.loads(ipc('lockOwner', 'status'))
        def secured():
            view = inspect()
            descriptor = view.get('descriptor') or {}
            if unconfirmed:
                return descriptor.get('generation') != old_generation and owner_status()['state'] == 'engaged-unconfirmed(external)'
            record = descriptor.get('units', {}).get(expected_role, {})
            client = record.get('client') or {}
            observation = view.get('units', {}).get(expected_role, {})
            return (descriptor.get('generation') != old_generation and descriptor.get('phase') != 'settled'
                    and client.get('secure') and not client.get('terminal')
                    and observation.get('sameInvocation') and not observation.get('gone'))
        wait_for(secured, 15)
        first = inspect()
        (work / ('first-unconfirmed.json' if unconfirmed else 'first-secure.json')).write_text(json.dumps(first, indent=2))
        assert first['descriptor']['units']['real']['startedAt'] < first['descriptor']['emergencyAt']
        if args.case == 'fast':
            assert 'emergency' not in first['descriptor']['units'], 'unexpected fallback on fast path'
        if args.case == 'slow':
            assert first['descriptor']['units']['emergency']['startedAt'] >= first['descriptor']['emergencyAt'], 'early emergency deadline'
            assert first['descriptor']['units']['real']['startedAt'] < first['descriptor']['emergencyAt']
            if args.emergency_auth_before_ready:
                # Authenticate immediately, while the selected real workload is
                # still in its actual delay. Its future exec must be revoked.
                assert not (first['descriptor']['units']['real'].get('client') or {}).get('requested')
                authenticated_at = time.monotonic()
                authenticate()
                wait_for(lambda: inspect()['descriptor']['phase'] == 'settled', 15)
                assert all(item['gone'] and not item['members'] for item in inspect()['units'].values())
                wait_for(lambda: time.monotonic() >= first['descriptor']['units']['real']['startedAt'] + args.delay + 1, args.delay + 5)
                time.sleep(10)
                assert inspect()['descriptor']['phase'] == 'settled'
                assert all(item['gone'] and not item['members'] for item in inspect()['units'].values())
                assert run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'no'
                assert not (work / 'real-delay-exec.json').exists(), 'revoked real command executed after emergency authentication'
                final = inspect()
                (work / 'final.json').write_text(json.dumps(final, indent=2))
                observer.stdin.close()
                assert observer.wait(timeout=10) == 0
                events = [json.loads(line) for line in (work / 'observer/events.jsonl').read_text().splitlines()]
                assert not any(event['kind'] == 'observer-error' for event in events)
                unlocks = [event for event in events if event['kind'] == 'locked-hint' and not event['locked']]
                assert len(unlocks) == 1 and unlocks[0]['observed'] >= authenticated_at
                native_unlocks = [event for event in events if event['kind'] == 'journal' and 'unlock_and_destroy' in event['message']]
                assert len(native_unlocks) == 1 and native_unlocks[0]['sourceMonotonic'] >= authenticated_at
                assert native_unlocks[0]['invocation'] == first['descriptor']['units']['emergency']['identity']['InvocationID']
                compositor_unlocks = [event for event in events if event['kind'] == 'compositor-log' and 'unlocking session' in event['message']]
                assert len(compositor_unlocks) == 1 and compositor_unlocks[0]['sourceMonotonic'] >= authenticated_at
                for role, record in final['descriptor']['units'].items():
                    journal = run(['journalctl', '--user', '-b', '--no-pager', '-o', 'cat',
                        '_SYSTEMD_INVOCATION_ID=' + record['identity']['InvocationID']]).stdout
                    journal = '\n'.join(line for line in journal.splitlines() if 'wl_keyboard#' not in line)
                    (work / (role + '-protocol.txt')).write_text(journal)
                    assert journal.count('unlock_and_destroy') == (1 if role == 'emergency' else 0)
                    if role == 'real':
                        assert not re.search(r'ext_session_lock_manager_v1#\d+\.lock\(', journal), 'revoked candidate requested a lock'
                    else:
                        assert re.search(r'ext_session_lock_v1#\d+\.locked\(\)', journal)
                unlocked = True
                print('PASS owner-slow-emergency-auth', work)
                (work / 'result.txt').write_text('PASS owner-slow-emergency-auth\n')
                return
            if args.delay < 30:
                from locker_framebuffer import Framebuffer
                console = Framebuffer()
                sequence_stop = threading.Event()
                sequence_errors = []
                sequence = []
                def capture_sequence():
                    frames = Framebuffer()
                    try:
                        while not sequence_stop.is_set():
                            path = work / ('handover-frame-%04d.ppm' % len(sequence))
                            began = time.monotonic()
                            frames.capture(path)
                            sequence.append({'file': path.name, 'began': began, 'ended': time.monotonic()})
                            assert not frames.sentinel_visible(), 'unlocked desktop sentinel in handover sequence'
                            sequence_stop.wait(.05)
                    except BaseException as error:
                        sequence_errors.append(str(error))
                    finally:
                        frames.close()
                capture_thread = threading.Thread(target=capture_sequence)
                capture_thread.start()
                try:
                    console.capture(work / 'emergency-secure.ppm')
                    assert not console.sentinel_visible(), 'unlocked desktop visible under emergency'
                    wait_for(lambda: (work / 'handover-at-barrier.json').exists(), args.delay + 10)
                    wait_for(lambda: inspect()['units']['emergency']['gone'])
                    blank = inspect()
                    assert blank['descriptor']['handoverCommitted']
                    assert not blank['descriptor']['units']['real']['grant'], 'candidate granted before dead-holder capture'
                    assert run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'yes', 'dead-holder handover unlocked'
                    console.capture(work / 'dead-holder.ppm')
                    assert not console.sentinel_visible(), 'unlocked desktop visible during dead-holder handover'
                    (work / 'dead-holder.json').write_text(json.dumps(blank, indent=2))
                    (work / 'release-handover').touch(mode=0o600)
                    expected_role = 'real'
                    wait_for(secured, 15)
                    first = inspect()
                    console.capture(work / 'real-secure.ppm')
                    assert not console.sentinel_visible(), 'unlocked desktop visible under replacement'
                    (work / 'handover-secure.json').write_text(json.dumps(first, indent=2))
                finally:
                    sequence_stop.set()
                    capture_thread.join(timeout=15)
                    assert not capture_thread.is_alive(), 'framebuffer worker did not finish'
                    (work / 'handover-frames.json').write_text(json.dumps({'frames': sequence, 'errors': sequence_errors}, indent=2))
                    console.close()
                assert sequence and not sequence_errors, sequence_errors
            else:
                wait_for(lambda: time.monotonic() > first['descriptor']['deadline'] + 1, 35)
                expired = inspect()
                assert expired['units']['real']['gone'] and not expired['units']['real']['members']
                assert expired['descriptor']['units']['emergency']['client']['secure']
                assert expired['descriptor']['deadline'] == first['descriptor']['deadline'], 'deadline reset'
                (work / 'deadline-expired.json').write_text(json.dumps(expired, indent=2))
                wait_for(lambda: time.monotonic() > first['descriptor']['units']['real']['startedAt'] + args.delay + 1, args.delay + 5)
                assert not (work / 'real-delay-exec.json').exists(), 'unready command executed after deadline'
                assert inspect()['descriptor']['units']['emergency']['client']['secure']
        if args.verify_settings:
            client_entry = stage / 'etc/xdg/quickshell/atmosphera-lockscreen/shell.qml'
            def preferences():
                return json.loads(run(['qs', 'ipc', '-p', str(client_entry), 'call', 'lockerSettings', 'status'], env=environment).stdout)
            original_preferences = preferences()
            assert original_preferences['readOnly'] and original_preferences['ready']
            assert original_preferences['session'] == sid and original_preferences['generation'] == first['descriptor']['generation']
            before_revision = first['descriptor']['settingsRevision']
            ipc('lockerProof', 'fingerprintPreference', 'true')
            wait_for(lambda: preferences()['allowPasswordWithFingerprint'] is True)
            assert inspect()['descriptor']['settingsRevision'] > before_revision
            assert inspect()['descriptor']['units']['real']['identity'] == first['descriptor']['units']['real']['identity']
            assert inspect()['descriptor']['units']['real']['client']['secure']
            ipc('lockerProof', 'fingerprintPreference', 'false')
            wait_for(lambda: preferences()['allowPasswordWithFingerprint'] is False)
            (work / 'settings-consumer.json').write_text(json.dumps(preferences(), indent=2))
        if args.case == 'opaque':
            wait_for(lambda: inspect()['units']['real']['gone'])
            first = inspect()
            assert not first['descriptor']['handoverCommitted'], 'opaque handover'
            assert first['descriptor']['snapshot']['adapter'] == 'opaque'
        if args.case == 'external':
            assert first['descriptor']['snapshot']['adapter'] == 'opaque'
            assert first['descriptor']['snapshot']['command'] == configuration['general']['externalLockCommand']
            assert not first['descriptor']['handoverCommitted'], 'opaque adapter must not hand over'
            if not unconfirmed:
                wait_for(lambda: inspect()['units']['real']['gone'])
                assert not inspect()['units']['real']['members']
            if args.external_variant in ('daemonizing', 'term-resistant'):
                assert {path.name for path in external_members.iterdir()} == {'parent.json', 'child.json'}
                members = [json.loads(path.read_text()) for path in external_members.iterdir()]
                for member in members:
                    process = Path('/proc') / str(member['pid'])
                    assert not process.exists() or (process / 'stat').read_text().split(') ', 1)[1].split()[19] != member['start'], 'escaped external descendant'
                (work / 'external-identities.json').write_text(json.dumps(members, indent=2))
            if args.external_variant in ('slow5', 'slow40'):
                delay = int(args.external_variant[4:])
                wait_for(lambda: time.monotonic() > first['descriptor']['units']['real']['startedAt'] + delay + 1, delay + 5)
                assert not external_executed.exists(), 'opaque delayed locker executed after emergency cancellation'
                assert inspect()['descriptor']['units']['emergency']['client']['secure']
        if args.case == 'hooks':
            assert marker.read_text() == 'prelock', 'hook not exactly once'
            assert json.loads(ipc('lockerProof', 'completions'))['other'] == 1, 'unrelated callback stolen'
            assert first['units']['prehook']['gone']
        if args.case == 'intent':
            wait_for(lambda: json.loads(ipc('lockerProof', 'completions'))['suspend'] == 1)
        if unconfirmed:
            probe = first['descriptor']['units']['emergency']['identity']['InvocationID']
            wait_for(lambda: inspect()['units']['emergency']['gone'])
            time.sleep(2)
            assert inspect()['descriptor']['units']['emergency']['identity']['InvocationID'] == probe, 'periodic probe'
            if args.case == 'opaque-sleep':
                ipc('lockerProof', 'sleepWindow')
                wait_for(lambda: inspect()['descriptor']['units']['emergency']['identity']['InvocationID'] != probe)
                wait_for(lambda: inspect()['units']['emergency']['gone'])
                probe = inspect()['descriptor']['units']['emergency']['identity']['InvocationID']
                assert inspect()['descriptor']['probeEvents']['sleep:1'] == probe
                ipc('lockerProof', 'sleepWindow')
                time.sleep(2)
                assert inspect()['descriptor']['units']['emergency']['identity']['InvocationID'] == probe, 'duplicate sleep-window probe'
            if args.case == 'opaque-crash':
                crashed_at = time.monotonic()
                # Exact owned invocation only, intentional crash. No protocol
                # unlock: recovery must acquire niri's dead-client locked state.
                real = inspect()['descriptor']['units']['real']
                run(['systemctl', '--user', 'kill', '--signal=SIGKILL', '--kill-whom=all', real['name']])
                wait_for(lambda: (inspect()['descriptor']['units']['emergency'].get('client') or {}).get('secure'))
                recovery = inspect()['descriptor']['units']['emergency']
                assert recovery['startedAt'] - crashed_at < 3
                assert inspect()['descriptor']['probeEvents']['exit:' + real['identity']['InvocationID']] == recovery['identity']['InvocationID']
                (work / 'crash-response.json').write_text(json.dumps({'candidateInvocation': real['identity']['InvocationID'],
                    'probeInvocation': recovery['identity']['InvocationID'], 'secondsToLaunch': recovery['startedAt'] - crashed_at}, indent=2))
                expected_role = 'emergency'
                unconfirmed = False
                first = inspect()
            if args.case != 'opaque-crash':
                assert not owner_status()['secure'], 'opaque refusal was declared secure'
                if args.main_shell:
                    assert not inspect()['descriptor']['suspendPending'], 'external lock unexpectedly requested suspend'
                else:
                    assert json.loads(ipc('lockerProof', 'completions'))['suspend'] == 0, 'opaque refusal discharged suspend'
            assert run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'yes'
        generation = first['descriptor']['generation']
        identity = first['descriptor']['units'][expected_role]['identity']
        ipc('lockerProof', 'lock')
        time.sleep(.5)
        assert inspect()['descriptor']['generation'] == generation, 'duplicate generation'
        # Graceful exit only for our harness root. The locker unit must survive.
        ipc('lockerProof', 'exit')
        wait_for(lambda: run(['systemctl', '--user', 'show', unit, '-p', 'ActiveState', '--value']).stdout.strip() == 'inactive')
        assert inspect()['descriptor']['units'][expected_role]['identity'] == identity
        if not unconfirmed:
            assert inspect()['descriptor']['units'][expected_role]['client']['secure']
        start()
        def adopted():
            status = json.loads(ipc('lockOwner', 'status'))
            return status if (status['state'] == 'engaged-unconfirmed(external)' if unconfirmed else status['secure']) else None
        status = wait_for(adopted, 10)
        assert status['descriptor']['generation'] == generation
        assert status['descriptor']['units'][expected_role]['identity'] == identity
        (work / 'adopted.json').write_text(json.dumps(status, indent=2))
        if intent:
            assert json.loads(ipc('lockerProof', 'completions'))['suspend'] == 0, 'adoption duplicated suspend intent'
        # The demo's TextInput needs an ordinary click after its window maps.
        # Capture the actual VM console first; never focus by mutating UI state.
        if args.ui == 'demo':
            from locker_framebuffer import Framebuffer
            console = Framebuffer()
            try:
                console.capture(work / 'before-demo-input.ppm')
                console.click(console.width // 2, console.height - 73)
            finally:
                console.close()
        # Wrong password must leave the real holder secure.
        run(['wtype', 'wrong-password'], env=environment)
        run(['wtype', '-k', 'Return'], env=environment)
        time.sleep(3)
        if unconfirmed:
            assert inspect()['units']['real']['sameInvocation'] and not owner_status()['secure']
            assert run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'yes'
        else:
            assert inspect()['descriptor']['units'][expected_role]['client']['secure']
        if args.recover_known_pam_hang and not unconfirmed:
            recover_known_pam_hang(source, sid, expected_role, work)
        run(['wtype', '-M', 'ctrl', '-k', 'a', '-m', 'ctrl', '-k', 'BackSpace'], env=environment)
        if args.case in ('opaque-race', 'opaque-withdraw'):
            (work / 'block-probe').touch(mode=0o600)
            ipc('lockerProof', 'sleepWindow')
            wait_for(lambda: (work / 'probe-at-barrier.json').exists())
            current = inspect()
            assert not (current['descriptor']['units']['emergency'].get('client') or {}).get('requested')
            if args.case == 'opaque-race':
                assert run(['systemctl', '--user', 'show', unit, '-p', 'InvocationID', '--value']).stdout.strip() == owner
                run(['systemctl', '--user', 'kill', '--signal=SIGSTOP', '--kill-whom=main', unit])
                owner_stopped = True
        successful_input_at = time.monotonic()
        authenticate()
        authenticated_inputs = [successful_input_at]
        if args.case in ('opaque-race', 'opaque-withdraw'):
            wait_for(lambda: inspect()['units']['real']['gone'])
            assert run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'no'
            if args.case == 'opaque-withdraw':
                wait_for(lambda: inspect()['descriptor'].get('sessionUnlockObserved'))
            (work / 'release-probe').touch(mode=0o600)
            if args.case == 'opaque-race':
                wait_for(lambda: (inspect()['descriptor']['units']['emergency'].get('client') or {}).get('secure'))
                retained_identity = inspect()['descriptor']['units']['emergency']['identity']
                run(['systemctl', '--user', 'kill', '--signal=SIGCONT', '--kill-whom=main', unit])
                owner_stopped = False
                wait_for(lambda: inspect()['descriptor'].get('probeRaceWon'))
                assert inspect()['descriptor']['units']['emergency']['identity'] == retained_identity
                assert not inspect()['units']['emergency']['gone']
                assert run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'yes'
                authenticated_inputs.append(time.monotonic())
                authenticate()
                expected_role = 'emergency'
        wait_for(lambda: inspect()['descriptor']['phase'] == 'settled', 15)
        final = inspect()
        (work / 'final.json').write_text(json.dumps(final, indent=2))
        assert all(item['gone'] and not item['members'] for item in final['units'].values())
        if args.case == 'hooks':
            assert marker.read_text() == 'prelockunlock', 'hook duplicated or lost after adoption'
        assert run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'no'
        if sentinel_identity:
            from locker_framebuffer import Framebuffer
            console = Framebuffer()
            try:
                def authenticated_sentinel():
                    console.capture(work / 'unlocked-after.ppm')
                    return all(console.sentinel_corners())
                wait_for(authenticated_sentinel)
            finally:
                console.close()
        if args.case in ('slow', 'external', 'opaque-holder', 'opaque-sleep', 'opaque-race', 'opaque-withdraw'):
            time.sleep(10)
            assert inspect()['descriptor']['phase'] == 'settled'
            assert all(item['gone'] and not item['members'] for item in inspect()['units'].values())
            assert run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'no', 'delayed relock'
        unlocked = True
        real_journal = run(['journalctl', '--user', '-b', '--no-pager', '-o', 'cat',
                            '_SYSTEMD_INVOCATION_ID=' + identity['InvocationID']]).stdout
        real_journal = '\n'.join(line for line in real_journal.splitlines() if 'wl_keyboard#' not in line)
        (work / 'holder-journal.txt').write_text(real_journal)
        assert re.search(r'ext_session_lock_v1#\d+\.locked\(\)', real_journal), 'native secure event missing'
        assert real_journal.count('unlock_and_destroy') == 1
        # IconRegistry is the required data-only icon map, not the general
        # plugin registry. Keep rejecting every other registry/service startup.
        assert 'Registry' not in real_journal.replace('IconRegistry', '') and 'PluginService' not in real_journal, 'registry initialized'
        observer.stdin.close()
        assert observer.wait(timeout=10) == 0
        events = [json.loads(line) for line in (work / 'observer/events.jsonl').read_text().splitlines()]
        assert not any(event['kind'] == 'observer-error' for event in events), 'continuous observer failed'
        transitions = [event for event in events if event['kind'] == 'locked-hint']
        assert any(event['locked'] for event in transitions), 'missing compositor-originated secure hint'
        unlocks = [event for event in transitions if not event['locked']]
        assert len(unlocks) == len(authenticated_inputs), 'unlock/relock outside approved race'
        assert all(event['observed'] >= at for event, at in zip(unlocks, authenticated_inputs)), 'unlock before successful PAM input'
        native_unlocks = [event for event in events if event['kind'] == 'journal' and 'unlock_and_destroy' in event['message']]
        assert len(native_unlocks) == len(authenticated_inputs), 'unexpected native unlock'
        assert all(event['sourceMonotonic'] >= at for event, at in zip(native_unlocks, authenticated_inputs)), 'native unlock before PAM input'
        if os.environ.get('NIRI_SOCKET'):
            compositor_unlocks = [event for event in events if event['kind'] == 'compositor-log' and 'unlocking session' in event['message']]
            assert len(compositor_unlocks) == len(authenticated_inputs), 'compositor unlock outside approved authentication'
            assert all(event['sourceMonotonic'] >= at for event, at in zip(compositor_unlocks, authenticated_inputs)), 'compositor unlocked before PAM input'
        native_secure = [event for event in events if event['kind'] == 'journal'
                         and event['invocation'] == identity['InvocationID']
                         and re.search(r'ext_session_lock_v1#\d+\.locked\(\)', event['message'])]
        assert native_secure, 'continuous observer missed holder secure event'
        timings = {'ui': args.ui, 'requestedAt': first['descriptor']['requestedAt'],
                   'realStartedAt': first['descriptor']['units']['real']['startedAt'],
                   'holderSecureAt': native_secure[0]['sourceMonotonic']}
        timings['secondsToSecure'] = timings['holderSecureAt'] - timings['requestedAt']
        (work / 'startup-timings.json').write_text(json.dumps(timings, indent=2))
        if args.case == 'fast':
            assert timings['holderSecureAt'] < first['descriptor']['emergencyAt'], 'fast secure acknowledgement missed 3s deadline'
        for role, record in final['descriptor']['units'].items():
            if role not in ('real', 'emergency'):
                continue
            journal = run(['journalctl', '--user', '-b', '--no-pager', '-o', 'cat',
                           '_SYSTEMD_INVOCATION_ID=' + record['identity']['InvocationID']]).stdout
            journal = '\n'.join(line for line in journal.splitlines() if 'wl_keyboard' not in line)
            (work / (role + '-protocol.txt')).write_text(journal)
            expected = 1 if role == expected_role or (args.case == 'opaque-race' and role == 'real') else 0
            assert journal.count('unlock_and_destroy') == expected, 'non-holder protocol unlock'
            if args.case == 'opaque-withdraw' and role == 'emergency':
                assert not re.search(r'ext_session_lock_manager_v1#\d+\.lock\(', journal), 'revoked unrequested probe acquired'
        if args.case == 'opaque-race':
            journal = run(['journalctl', '--user', '-b', '--no-pager', '-o', 'cat', '_SYSTEMD_INVOCATION_ID=' + owner]).stdout
            assert 'emergency probe won race against external unlock' in journal
        recovery = ' (known native PAM hang recovered)' if (work / 'known-pam-hang-recovery.json').exists() else ''
        print('PASS owner-' + args.case + recovery, work)
        (work / 'result.txt').write_text('PASS owner-' + args.case + recovery + '\n')
    finally:
        if owner_stopped:
            run(['systemctl', '--user', 'kill', '--signal=SIGCONT', '--kill-whom=main', unit])
        observer_error = None
        if observer is not None and observer.poll() is None:
            if not observer.stdin.closed:
                observer.stdin.close()
            try:
                observer.wait(timeout=15)
            except subprocess.TimeoutExpired as error:
                observer_error = error
                observer.terminate()
                observer.wait(timeout=15)
        current = inspect()
        (work / 'last-observation.json').write_text(json.dumps(current, indent=2))
        if owner:
            journal = run(['journalctl', '--user', '-b', '--no-pager', '-o', 'cat',
                           '_SYSTEMD_INVOCATION_ID=' + owner]).stdout
            (work / 'owner-journal.txt').write_text(journal)
        # No failure cleanup unlock or broad kill: only stop this root. Preserve
        # a still-secure holder and protected credential for real-PAM recovery.
        run(['systemctl', '--user', 'stop', unit])
        if sentinel_identity:
            assert run(['systemctl', '--user', 'show', sentinel_unit, '-p', 'InvocationID', '--value']).stdout.strip() == sentinel_identity
            run(['systemctl', '--user', 'stop', sentinel_unit])
            assert run(['systemctl', '--user', 'show', sentinel_unit, '-p', 'MainPID', '--value']).stdout.strip() == '0'
        hint = run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip()
        if hint == 'no' and (unlocked or not current.get('descriptor') or current['descriptor']['phase'] == 'settled'):
            run(['sudo', '-n', 'chpasswd', '-e'], input='tester:' + original_hash + '\n')
            credential.unlink()
            original_shadow.unlink()
        else:
            print('Real-PAM recovery required; protected recovery files in', work, file=__import__('sys').stderr)
        if observer_error is not None:
            raise observer_error


if __name__ == '__main__':
    main()
