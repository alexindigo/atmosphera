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
import struct
import subprocess
import threading
import time

from locker_test_support import compositor_locked, compositor_transitions, hypr_option, manage, recover_known_pam_hang, require_guest, run, wait_for
from locker_proof_oracles import authenticated_unlocks, process_report_commit


def deadline_outcome(descriptor, events):
    """Classify actual protocol winners, never owner receipt time or LockedHint."""
    secure = {}
    for role in ('real', 'emergency'):
        record = descriptor['units'].get(role)
        if record:
            secure[role] = [event['sourceMonotonic'] for event in events
                if event['kind'] == 'journal' and event['invocation'] == record['identity']['InvocationID']
                and re.search(r'ext_session_lock_v1#\d+\.locked\(\)', event['message'])]
    assert secure.get('real'), 'real native secure event missing'
    real = min(secure['real'])
    emergency = min(secure['emergency']) if secure.get('emergency') else None
    if real < descriptor['emergencyAt']:
        assert 'emergency' not in descriptor['units'], 'unexpected emergency on under-deadline fast path'
        return 'fast-without-emergency'
    assert 'emergency' in descriptor['units'], 'late real lock had no deadline emergency attempt'
    if emergency is None:
        rejected = descriptor['units']['emergency']['client']
        assert rejected['terminal'] and rejected['settlement'] == 'finished', 'losing emergency did not settle refusal'
        assert not descriptor['handoverCommitted'], 'real-first race unexpectedly retired its secure holder'
        return 'late-real-first'
    assert emergency < real and descriptor['handoverCommitted'], 'emergency-first acquisition did not hand over fail-closed'
    assert descriptor['units']['emergency']['client']['settlement'] == 'retired'
    return 'emergency-first-handover'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--case', choices=('fast', 'adoption', 'slow', 'boundary', 'external', 'opaque', 'opaque-holder', 'opaque-sleep', 'opaque-crash', 'opaque-race', 'opaque-withdraw', 'opaque-expiry', 'report-refusal', 'report-unknown', 'hooks', 'intent'), default='fast')
    parser.add_argument('--external-variant', choices=('existing', 'missing', 'slow5', 'slow40', 'nonzero', 'crash', 'pipeline', 'daemonizing', 'term-resistant', 'daemonizing-holder'), default='existing')
    parser.add_argument('--delay', type=float, default=5)
    parser.add_argument('--emergency-auth-before-ready', action='store_true')
    parser.add_argument('--restart-state', choices=('starting', 'fallback', 'handing-over'))
    parser.add_argument('--ui', choices=('builtin', 'demo'), default='builtin')
    parser.add_argument('--verify-settings', action='store_true')
    parser.add_argument('--main-shell', action='store_true', help='Use the actual main shell for fast/adoption and public lock IPC')
    parser.add_argument('--ingress', choices=('ipc', 'cli', 'keybind', 'hot-corner', 'idle', 'custom', 'exclusive', 'hooks', 'legacy'), default='ipc')
    parser.add_argument('--late-real-first', action='store_true', help='Test-only granted-client response barrier and held emergency exec')
    parser.add_argument('--real-suspend', action='store_true')
    parser.add_argument('--sleep-signals', action='store_true', help='Real logind/inhibitor path with a no-kernel-sleep service barrier')
    parser.add_argument('--sleep-route', choices=('lock-and-suspend', 'prepare-for-sleep'), default='lock-and-suspend')
    parser.add_argument('--suspend-after-inspect-race', action='store_true', help='Authenticate before delivering the captured final inspect; lockOnSuspend stays false')
    parser.add_argument('--suspend-race-lock-on-suspend', action='store_true', help='Prove the same intervening-PAM ordering with lockOnSuspend enabled')
    parser.add_argument('--recover-known-pam-hang', action='store_true', help='Record and recover only a verified native PAM syslog deadlock; never the secure holder')
    args = parser.parse_args()
    if args.suspend_after_inspect_race and (not args.main_shell or args.case != 'fast' or args.sleep_signals):
        parser.error('--suspend-after-inspect-race requires actual-main fast without the optional sleep helper')
    if args.suspend_race_lock_on_suspend and not args.suspend_after_inspect_race:
        parser.error('--suspend-race-lock-on-suspend requires --suspend-after-inspect-race')
    if args.main_shell and args.case not in ('fast', 'adoption', 'slow', 'boundary', 'external', 'opaque-expiry'):
        parser.error('--main-shell currently proves fast/adoption/slow/boundary/external; other main-shell acceptance remains separate')
    if args.ingress != 'ipc' and not args.main_shell:
        parser.error('--ingress requires the actual main shell')
    if args.late_real_first and args.case != 'fast':
        parser.error('--late-real-first belongs to the fast/startup outcome proof')
    if args.real_suspend:
        parser.error('real S3 is not testable in this VM; use --sleep-signals')
    if args.sleep_signals and (not args.main_shell or args.case not in ('fast', 'slow', 'opaque-expiry') or args.late_real_first):
        parser.error('--sleep-signals requires the actual main fast or slow path')
    if args.case == 'opaque-expiry' and (not args.sleep_signals or args.sleep_route != 'prepare-for-sleep'):
        parser.error('opaque-expiry requires actual-main --sleep-signals --sleep-route prepare-for-sleep')
    if args.ingress in ('custom', 'exclusive', 'legacy') and (args.case != 'external' or args.external_variant != 'existing'):
        parser.error('selected adapter ingress needs the existing external client proof')
    if args.case == 'slow' and args.delay < 5:
        parser.error('slow coverage requires at least 5s; boundary ordering is a separate case')
    if args.emergency_auth_before_ready and args.case != 'slow':
        parser.error('--emergency-auth-before-ready belongs to --case slow')
    if args.restart_state and (args.case != 'slow' or args.delay >= 30 or args.emergency_auth_before_ready):
        parser.error('--restart-state needs the cooperative slow handover case')
    source, work = require_guest(args.work, Path(__file__).resolve().parents[2])
    # Hyprland keeps a dead holder's lock and denies every new lock unless
    # misc:allow_session_lock_restore is on; the capability case sets it in
    # this disposable guest and restores it. See locker-hyprland-capability-proof.py.
    hypr_crash = args.case == 'opaque-crash' and bool(os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'))
    if hypr_crash:
        restore = json.loads(run(['hyprctl', '-j', 'getoption', 'misc:allow_session_lock_restore']).stdout)
        assert restore['int'] == 1, 'Hyprland opaque-crash runs only inside the restore=1 capability case'
    telemetry = []
    load_file = Path(os.environ['LOCKER_TEST_ARK_LOAD_FILE'])

    def sample_load(phase):
        fields = [int(value) for value in Path('/proc/stat').read_text().splitlines()[0].split()[1:]]
        # guest and guest_nice are already included in user/nice, not extra time.
        total, steal = sum(fields[:8]), fields[7]
        previous = telemetry[-1] if telemetry else None
        sample = {'phase': phase, 'monotonic': time.monotonic(), 'cpuTotalTicks': total,
            'cpuStealTicks': steal, 'arkUptime': load_file.read_text().splitlines()[-1]}
        if previous and total > previous['cpuTotalTicks']:
            sample['stealPercentSincePrevious'] = 100 * (steal - previous['cpuStealTicks']) / (total - previous['cpuTotalTicks'])
        telemetry.append(sample)
        (work / 'load-samples.json').write_text(json.dumps(telemetry, indent=2))

    sample_load('start')
    if hypr_crash or args.sleep_signals or args.ui == 'demo' or args.ingress in ('keybind', 'hot-corner') or args.case == 'boundary' or (args.case == 'slow' and args.delay < 30 and not args.emergency_auth_before_ready):
        assert os.environ.get('LOCKER_FRAMEBUFFER_PORT') and os.environ.get('LOCKER_TEST_VM_NAME'), 'render/input proof requires the named VM console forward'
    discovery = manage(source, {'operation': 'discover'})
    sid, takeover = discovery['session'], discovery['takeover']
    assert run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'no', 'existing holder'
    stage = work / 'stage'
    run(['bash', '-eu', '-c', 'source "$1/packaging/aur/package.sh"; package', 'stage', str(source)],
        env=dict(os.environ, srcdir=str(source.parent), _gitname=source.name, pkgdir=str(stage), pkgver='0.9.3'), timeout=60)
    root = stage / 'etc/xdg/quickshell/atmosphera'
    # Read-only proof observations of the actual shared LockAuth completion.
    # No credential, auth result injection or alternative unlock path.
    for relative, target in (('atmosphera-lockscreen/LockSession.qml', 'lockContext'),
            ('atmosphera-emergency-lock/EmergencyLock.qml', 'lockAuth')):
        path = stage / 'etc/xdg/quickshell' / relative
        text = path.read_text()
        anchor = '  id: root\n'
        assert text.count(anchor) == 1
        observation = ('  Connections { target: ' + target + '; function onDiagnostic(message) { '
            'if (message === "Authentication successful") console.log("LOCKER_PAM_SUCCESS " '
            '+ JSON.stringify({pid: Quickshell.processId})); } }\n')
        path.write_text(text.replace(anchor, anchor + observation))
    entry = root / ('shell.qml' if args.main_shell else 'locker-owner-proof.qml')
    if args.suspend_after_inspect_race:
        # Observe the independent notification/inspect ordering. Delay only the
        # real signal forwarding in this disposable install; never fabricate an
        # unlock or alter the managed client's private authentication fence.
        path = root / 'Services/Locker/LockerService.qml'
        text = path.read_text()
        assert text.count('      sessionUnlocked();') == 1
        assert text.count('  id: root\n') == 1
        text = text.replace('      sessionUnlocked();', '      delayedUnlockObservation.restart();')
        text = text.replace('  id: root\n', '  id: root\n  Timer { id: delayedUnlockObservation; interval: 10000; onTriggered: root.sessionUnlocked(); }\n')
        path.write_text(text)
        (work / 'sleep-observe-session').write_text(sid)
    if not args.main_shell:
        entry.write_text((source / 'Scripts/dev/fixtures/locker-owner.qml').read_text())
    settings = work / 'config'
    settings.mkdir()
    configuration = {'settingsVersion': 62,
        'general': {'lockScreenEnabled': True, 'lockScreenPlugin': 'demo-custom-lockscreen' if args.ui == 'demo' else 'default',
                     'lockOnSuspend': args.sleep_signals or args.suspend_race_lock_on_suspend, 'showChangelogOnStartup': False}}
    marker = work / 'hook-events'
    if args.case in ('opaque', 'report-unknown'):
        configuration['general']['externalLockCommand'] = 'sleep 40'
    unconfirmed = args.case in ('opaque-holder', 'opaque-sleep', 'opaque-crash', 'opaque-race', 'opaque-withdraw', 'report-refusal')
    if unconfirmed:
        # Actual independently authenticating client, deliberately not our
        # generation protocol. Its unit activity/hint must not count as secure.
        configuration['general']['externalLockCommand'] = ('env -u ATMOSPHERA_LOCK_SESSION -u ATMOSPHERA_LOCK_GENERATION '
            '-u ATMOSPHERA_LOCK_ROLE -u ATMOSPHERA_LOCK_ADAPTER qs -c atmosphera-emergency-lock')
    if args.case == 'opaque-expiry':
        unconfirmed = True
        protocol = '/usr/share/wayland-protocols/staging/ext-session-lock/ext-session-lock-v1.xml'
        header, code = work / 'session-lock-client.h', work / 'session-lock-protocol.c'
        run(['wayland-scanner', 'client-header', protocol, str(header)])
        run(['wayland-scanner', 'private-code', protocol, str(code)])
        flags = shlex.split(run(['pkg-config', '--cflags', '--libs', 'wayland-client', 'xkbcommon', 'pam']).stdout)
        fixture = work / 'opaque-delayed-locker'
        compiled = run(['cc', '-Wall', '-Wextra', '-Werror', '-I' + str(work),
            str(source / 'Scripts/dev/fixtures/locker-opaque-delayed.c'), str(code), '-o', str(fixture), *flags])
        (work / 'fixture-build.txt').write_text(compiled.stdout + compiled.stderr)
        configuration['general']['externalLockCommand'] = shlex.join([str(fixture), str(work / 'release-surfaces')])
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
        if args.ingress == 'custom':
            configuration['sessionMenu'] = {'powerOptions': [{'action': 'lock', 'enabled': True, 'keybind': '1',
                'command': commands[args.external_variant]}]}
            configuration['general']['externalLockCommand'] = 'exit 99'
        elif args.ingress == 'exclusive':
            configuration['hooks'] = {'enabled': True, 'handlers': {'lockAction': {
                'command': commands[args.external_variant], 'exclusive': True}}}
            configuration['general']['externalLockCommand'] = 'exit 99'
        elif args.ingress == 'legacy':
            configuration['general']['lockScreenPlugin'] = 'external'
        unconfirmed = args.external_variant in ('existing', 'pipeline', 'daemonizing-holder')
    if args.case == 'hooks' or args.ingress == 'hooks':
        prehook_delay = '1' if args.case == 'hooks' else '0.1'
        configuration['hooks'] = {'enabled': True, 'handlers': {
            'lockAction': {'command': 'printf pre >> ' + shlex.quote(str(marker)) + '; sleep ' + prehook_delay, 'exclusive': False},
            'screenOffAction': {'command': 'sleep 0.5', 'exclusive': False}}, 'listeners': {
            'screenLock': 'printf lock >> ' + shlex.quote(str(marker)) + '; sleep 40',
             'screenUnlock': 'printf unlock >> ' + shlex.quote(str(marker))}}
    if args.ingress == 'idle':
        configuration['idle'] = {'enabled': False, 'lockTimeout': 2, 'screenOffTimeout': 0,
            'suspendTimeout': 0, 'fadeDuration': 0}
    if args.ingress == 'hot-corner':
        configuration['general']['hotCorners'] = {'bottomRight': 'atmosphera ipc lockScreen lock', 'delayMs': 200}
    (settings / 'settings.json').write_text(json.dumps(configuration))
    environment = dict(os.environ, XDG_CONFIG_DIRS=str(stage / 'etc/xdg') + ':/etc/xdg',
                       ATMOSPHERA_CONFIG_DIR=str(settings), WAYLAND_DEBUG='client',
                       ATMOSPHERA_CACHE_DIR=str(work / 'cache'), ATMOSPHERA_STATE_DIR=str(work / 'state'))
    if args.ingress == 'hot-corner':
        environment['PATH'] = str(root / 'Scripts/bash') + ':' + environment['PATH']
    if args.case in ('slow', 'opaque-race', 'opaque-withdraw', 'report-refusal', 'report-unknown') or args.late_real_first:
        binary = work / 'bin/qs'
        binary.parent.mkdir()
        fixture_name = 'locker-report-qs.py' if args.case.startswith('report-') else 'locker-qs-barrier.py'
        shutil.copyfile(source / 'Scripts/dev/fixtures' / fixture_name, binary)
        binary.chmod(0o700)
        environment['PATH'] = str(binary.parent) + ':' + os.environ['PATH']
        if args.case.startswith('report-'):
            (work / ('trace-report-probe' if args.case == 'report-refusal' else 'hold-first-report-probe')).touch(mode=0o600)
        if args.case == 'slow':
            (work / 'delay-real').write_text(str(args.delay))
            if args.delay < 30 and not args.emergency_auth_before_ready and takeover:
                adapter_binary = binary.with_name('python3')
                shutil.copyfile(source / 'Scripts/dev/fixtures/locker-adapter-barrier.py', adapter_binary)
                adapter_binary.chmod(0o700)
        if args.late_real_first:
            (work / 'block-probe').touch(mode=0o600)
            adapter_binary = binary.with_name('python3')
            shutil.copyfile(source / 'Scripts/dev/fixtures/locker-grant-barrier.py', adapter_binary)
            adapter_binary.chmod(0o700)
    if args.case == 'boundary':
        binary = work / 'bin/python3'
        binary.parent.mkdir()
        shutil.copyfile(source / 'Scripts/dev/fixtures/locker-adapter-barrier.py', binary)
        binary.chmod(0o700)
        (work / 'ready-at-delay').write_text(str(args.delay))
        environment['PATH'] = str(binary.parent) + ':' + os.environ['PATH']
    if args.sleep_signals or args.suspend_after_inspect_race:
        binary = work / 'bin/python3'
        binary.parent.mkdir(exist_ok=True)
        shutil.copyfile(source / 'Scripts/dev/fixtures/locker-adapter-barrier.py', binary)
        binary.chmod(0o700)
        environment['PATH'] = str(binary.parent) + ':' + os.environ['PATH']
        if args.suspend_after_inspect_race:
            (work / 'hold-after-consume-inspect').touch(mode=0o600)
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
    original_niri_config = None
    restore_niri_config = None
    suspend_command = None
    kernel_cursor = None
    sleep_harness = None

    def output_capture(label):
        # Bounded diagnostic: shared compositor rendering, not physical scanout
        # proof. Both sides must calibrate against the same desktop sentinel.
        path = work / (label + '.png')
        capture = run(['grim', str(path)], env=environment)
        (work / (label + '-capture.txt')).write_text(capture.stdout + capture.stderr)
        width, height = map(int, run(['magick', 'identify', '-format', '%w %h', str(path)]).stdout.split())
        pixels = subprocess.run(['magick', str(path), '-depth', '8', 'rgb:-'],
            check=True, capture_output=True, timeout=15).stdout
        assert len(pixels) == width * height * 3
        return {'width': width, 'height': height, 'sentinelVisible': b'\xff\x00\xff' * 8 in pixels,
            'allBlack': not any(pixels), 'monotonic': time.monotonic()}

    def hypr_lock_timers():
        # Hyprland v0.56.2 sources: misc:lockdead_screen_delay is configuration
        # (Renderer.cpp:1109-1113, SessionLockManager.cpp:244-250); the 5 s
        # locked fallback is a constant (SessionLockManager.cpp:113-130).
        version = json.loads(run(['hyprctl', '-j', 'version']).stdout)
        assert version['tag'] == 'v0.56.2', 'Hyprland lock timers verified only against v0.56.2 sources'
        option = json.loads(run(['hyprctl', '-j', 'getoption', 'misc:lockdead_screen_delay']).stdout)
        assert option['option'] == 'misc:lockdead_screen_delay'
        return {'version': version['tag'], 'commit': version['commit'], 'lockdeadOption': option,
                'lockdeadScreenDelay': option['int'] / 1000, 'lockedFallback': 5.0, 'restore': hypr_option()}

    def hypr_resumed_locked(resume):
        """Hyprland form of "still locked after resume" for a holder that never drew.

        Hyprland reports such a lock (lock-notify) only after it sends the
        client locked, which is at the latest its 5 s fallback timer. Wait
        through that timer, then require: no unlock at all, no authentication,
        and every emergency probe refused by the existing lock (restore=0).
        """
        timers = hypr_lock_timers()
        assert timers['restore']['int'] == 0, 'refusal proof needs misc:allow_session_lock_restore=0'
        descriptor = inspect()['descriptor']
        holder = descriptor['units']['real']['identity']['InvocationID']

        def observed():
            raw = (work / 'observer/events.jsonl').read_text()
            return [json.loads(line) for line in raw.rpartition('\n')[0].splitlines()]

        def protocol(invocation, pattern):
            return [event['sourceMonotonic'] for event in observed() if event['kind'] == 'journal'
                and event.get('invocation') == invocation and re.search(pattern, event['message'])]

        holder_requests = protocol(holder, r'-> ext_session_lock_manager_v1#\d+\.lock\(')
        assert len(holder_requests) == 1, 'holder lock request not observed exactly once'
        bound = holder_requests[0] + max(timers['lockedFallback'], timers['lockdeadScreenDelay']) + 2

        def native():
            return [event for event in observed() if event['kind'] in ('compositor-initial', 'compositor-lock')]
        at_resume_events = [row for row in native() if row.get('sourceMonotonic', row['observed']) <= resume['observed']]
        at_resume = at_resume_events[-1]['locked'] if at_resume_events else False
        wait_for(lambda: native()[-1]['locked'], max(bound - time.monotonic(), 0) + .5)
        transitions = native()
        assert [event['locked'] for event in transitions] == [False, True], 'native unlock or relock around resume'
        assert holder_requests[0] <= transitions[-1]['sourceMonotonic'] <= bound, 'native locked outside the Hyprland timer'
        assert not any(event['kind'] == 'journal' and 'unlock_and_destroy' in event['message'] for event in observed())
        holder_journal = run(['journalctl', '--user', '-b', '--no-pager', '-o', 'cat',
            '_SYSTEMD_INVOCATION_ID=' + holder]).stdout
        assert not any(name in holder_journal for name in ('"pam-success"', '"authenticated-unlock"')), 'holder authenticated before resume check'
        status = owner_status()
        assert status['state'] == 'engaged-unconfirmed(external)' and not status['secure']
        view = inspect()
        assert view['units']['real']['sameInvocation'] and not view['units']['real']['gone']
        records = [view['descriptor']['units']['emergency'], *view['descriptor'].get('retiredInvocations', [])]
        records = {record['identity']['InvocationID']: record for record in records if record['name'].startswith('atmosphera-emergency-lock')}
        probes = view['descriptor']['probeEvents']
        assert {'sleep:1', 'deadline'} <= set(probes), 'expected sleep-window and deadline probes'
        refusals = {}
        for event, invocation in probes.items():
            record = records[invocation]
            assert record['protocolOutcome'] == 'finished' and not record['everSecure'], 'probe was not refused'
            assert record['protocolReport']['event'] == 'finished' and not record['protocolReport']['everSecure']
            requests = protocol(invocation, r'-> ext_session_lock_manager_v1#\d+\.lock\(')
            finished = protocol(invocation, r'ext_session_lock_v1#\d+\.finished\(\)')
            assert len(requests) == 1 and requests[0] > holder_requests[0], 'probe request did not follow the holder lock'
            assert finished and not protocol(invocation, r'ext_session_lock_v1#\d+\.locked\(\)'), 'probe secured'
            refusals[event] = {'invocation': invocation, 'requested': requests[0], 'finished': finished[0]}
        (work / 'hypr-resume-lock.json').write_text(json.dumps({'timers': timers, 'holderRequestedAt': holder_requests[0],
            'resumeObserved': resume['observed'], 'nativeLockedAtResume': at_resume,
            'nativeLockedAt': transitions[-1]['sourceMonotonic'], 'boundAt': bound,
            'nativeLockedAfterRequest': transitions[-1]['sourceMonotonic'] - holder_requests[0],
            'transitions': transitions, 'refusedProbes': refusals, 'owner': status['state'],
            'note': 'restore=0: Hyprland denies a new lock only while the session is protocol-locked'}, indent=2))

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

    def idle_enabled(enabled):
        path = settings / 'settings/idle.json'
        values = dict(configuration['idle'], enabled=enabled)
        temporary = path.with_suffix('.proof-new')
        temporary.write_text(json.dumps(values))
        temporary.replace(path)

    def ingress():
        nonlocal original_niri_config, restore_niri_config, suspend_command, kernel_cursor
        if args.suspend_after_inspect_race:
            if args.suspend_race_lock_on_suspend:
                sleep_harness.held()
            ipc('sessionMenu', 'lockAndSuspend')
            return
        if args.sleep_signals:
            sleep_harness.held()
            cursor = run(['sudo', '-n', 'journalctl', '-b', '-k', '-n', '1', '--show-cursor', '--no-pager']).stdout
            kernel_cursor = re.search(r'-- cursor: (\S+)', cursor)[1]
            if args.sleep_route == 'prepare-for-sleep':
                suspend_command = subprocess.Popen(['sudo', '-n', 'systemctl', 'suspend'],
                    stdout=(work / 'suspend-command.txt').open('x'), stderr=subprocess.STDOUT)
            else:
                ipc('sessionMenu', 'lockAndSuspend')
            return
        if args.ingress == 'idle':
            # Real ext-idle-notify, not a call to the service's internal action.
            run(['wtype', '-M', 'shift', '-m', 'shift'], env=environment)
            idle_enabled(True)
            return
        cli = root / 'Scripts/bash/atmosphera'
        if args.ingress == 'cli':
            run([str(cli), 'lock'], env=environment)
            return
        if args.ingress == 'hot-corner':
            assert environment['XDG_CURRENT_DESKTOP'] == 'niri', 'hot-corner integration uses the niri guest'
            from locker_framebuffer import Framebuffer
            console = Framebuffer()
            try:
                # Ordinary native pointer motion over the real corner surface;
                # no direct service/owner call or synthetic dwell completion.
                console.socket.sendall(struct.pack('>BBHH', 5, 0, console.width // 2, console.height // 2))
                time.sleep(.3)
                console.socket.sendall(struct.pack('>BBHH', 5, 0, console.width - 3, console.height - 3))
            finally:
                console.close()
            return
        if args.ingress == 'keybind':
            assert environment['XDG_CURRENT_DESKTOP'] == 'niri', 'keybind fixture here uses niri'
            def startup_handoff():
                text = run(['journalctl', '--user', '-b', '--no-pager', '-o', 'cat',
                    '_SYSTEMD_INVOCATION_ID=' + owner]).stdout
                paths = re.findall(r'niri accepted configuration handoff:\s+(\S+)', text)
                return Path(paths[-1]) if paths else None
            restore_niri_config = wait_for(startup_handoff, 20)
            assert restore_niri_config.is_file()
            compositor = json.loads((work / 'observer/ready.json').read_text())['compositor']
            assert compositor, 'exact compositor identity required'
            process = Path('/proc') / str(compositor['pid'])
            assert process.joinpath('stat').read_text().split(') ', 1)[1].split()[19] == compositor['start']
            argv = process.joinpath('cmdline').read_bytes().decode().strip('\0').split('\0')
            env = dict(item.split('=', 1) for item in process.joinpath('environ').read_bytes().decode().split('\0') if '=' in item)
            original_niri_config = Path(env.get('XDG_CONFIG_HOME', env['HOME'] + '/.config')) / 'niri/config.kdl'
            for index, value in enumerate(argv):
                if value in ('-c', '--config'):
                    original_niri_config = Path(argv[index + 1])
                elif value.startswith('--config='):
                    original_niri_config = Path(value.split('=', 1)[1])
            text = original_niri_config.read_text()
            # Relative includes keep resolving against their original folder.
            text = re.sub(r'(?m)^(\s*include\s+)"([^"\n]+)"', lambda match:
                match[1] + json.dumps(str((original_niri_config.parent / match[2]).resolve())), text)
            key_config = work / 'keybind-config.kdl'
            command = 'printf key > ' + shlex.quote(str(work / 'keybind-fired')) + '; exec ' + shlex.join([str(cli), 'lock'])
            binding = '\n  Mod+Shift+F12 { spawn "sh" "-c" ' + json.dumps(command) + '; }\n'
            openings = list(re.finditer(r'(?m)^binds\s*\{', text))
            assert len(openings) == 1, 'fixture needs the guest config single binds section'
            at = openings[0].end()
            text = text[:at] + binding + text[at:]
            key_config.write_text(text)
            validation = subprocess.run(['niri', 'validate', '-c', str(key_config)], env=environment,
                text=True, capture_output=True, timeout=15)
            (work / 'keybind-validation.txt').write_text(validation.stdout + validation.stderr)
            assert validation.returncode == 0, validation.stderr
            run(['niri', 'msg', 'action', 'load-config-file', '--path', str(key_config)], env=environment)
            from locker_framebuffer import Framebuffer
            console = Framebuffer()
            try:
                console.chord(0xffeb, 0xffe1, 0xffc9)  # Super_L + Shift_L + F12
            finally:
                console.close()
            wait_for(lambda: (work / 'keybind-fired').exists())
            return
        # Custom session and hook selection is owned behind the same public
        # session-menu/lock IPC, never a direct test call to an internal owner.
        if args.ingress == 'custom':
            ipc('sessionMenu', 'lock')
        else:
            ipc('lockerProof', 'lock')

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
        if args.sleep_signals:
            def inhibitor_ready():
                journal = run(['journalctl', '--user', '-b', '--no-pager', '-o', 'cat',
                    '_SYSTEMD_INVOCATION_ID=' + owner]).stdout
                return 'Delay inhibitor acquired' in journal
            wait_for(inhibitor_ready, 15)

    def restart_at(state):
        before = inspect()
        d = before['descriptor']
        real = d['units']['real']
        if state == 'starting':
            assert 'emergency' not in d['units'] and not real['grant']
            assert not (real.get('client') or {}).get('requested')
        elif state == 'fallback':
            assert d['units']['emergency']['client']['secure'] and not d['handoverCommitted']
            assert not (real.get('client') or {}).get('ready')
        elif state == 'handing-over':
            assert d['handoverCommitted'] and before['units']['emergency']['gone']
            assert not real['grant']
        else:
            raise AssertionError(state)
        previous_owner = owner
        ipc('lockerProof', 'exit')
        wait_for(lambda: run(['systemctl', '--user', 'show', unit, '-p', 'ActiveState', '--value']).stdout.strip() == 'inactive')
        stopped = inspect()
        assert stopped['descriptor']['generation'] == d['generation']
        for role, record in d['units'].items():
            assert stopped['descriptor']['units'][role]['identity'] == record['identity'], 'shell exit replaced a locker invocation'
        start()
        def readopted():
            current = json.loads(ipc('lockOwner', 'status'))
            return (current.get('descriptor') or {}).get('generation') == d['generation']
        wait_for(readopted, 10)
        after = inspect()
        assert owner != previous_owner, 'main root did not restart'
        assert after['descriptor']['generation'] == d['generation']
        for key in ('requestedAt', 'emergencyAt', 'deadline'):
            assert after['descriptor'][key] == d[key], 'shell restart reset an original deadline'
        for role, record in d['units'].items():
            assert after['descriptor']['units'][role]['identity'] == record['identity'], 'adoption launched a duplicate invocation'
        (work / ('restart-' + state + '.json')).write_text(json.dumps({'previousOwner': previous_owner,
            'newOwner': owner, 'before': before, 'stopped': stopped, 'after': after}, indent=2))

    try:
        if args.sleep_signals or args.suspend_after_inspect_race:
            from locker_sleep_support import SleepHarness
            sleep_harness = SleepHarness(source, work)
            sleep_harness.install()
        observer = subprocess.Popen(['python3', '-B', str(source / 'Scripts/dev/locker-compositor-observer.py'),
                                     '--work', str(work / 'observer')], stdin=subprocess.PIPE,
                                    stdout=(work / 'observer-stdout.txt').open('w'),
                                    stderr=(work / 'observer-stderr.txt').open('w'), env=environment)
        wait_for(lambda: (work / 'observer/ready.json').exists(), 10)
        assert not compositor_locked(work, sid), 'existing compositor lock'
        start()
        if hypr_crash or args.sleep_signals or args.case == 'boundary' or (args.case == 'slow' and args.delay < 30 and not args.emergency_auth_before_ready):
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
                    if args.case == 'opaque-expiry':
                        capture = output_capture('unlocked-before')
                        return capture['sentinelVisible']
                    console.capture(work / 'unlocked-before.ppm')
                    return all(console.sentinel_corners())
                wait_for(visible_sentinel)
            finally:
                console.close()
        old_generation = (inspect().get('descriptor') or {}).get('generation')
        sample_load('request')
        intent = args.case in ('intent', 'opaque-holder', 'opaque-sleep')
        if intent:
            ipc('lockerProof', 'lockAndSuspend')
        else:
            ingress()
        if args.case == 'report-unknown':
            wait_for(lambda: (work / 'probe-held.json').exists(), 15)
            held = inspect()
            probe = held['descriptor']['units']['emergency']
            assert held['units']['emergency']['sameInvocation'] and probe.get('protocolOutcome') == 'unknown'
            assert json.loads(Path(probe['reportInfo']['path']).read_text()) == {}
            run(['systemctl', '--user', 'kill', '--signal=SIGSTOP', '--kill-whom=main', unit])
            owner_stopped = True
            run(['systemctl', '--user', 'kill', '--signal=SIGKILL', '--kill-whom=all', probe['name']])
            wait_for(lambda: inspect()['units']['emergency']['gone'])
            unknown = inspect()
            assert unknown['descriptor']['units']['emergency']['protocolOutcome'] == 'unknown'
            assert not unknown['descriptor']['units']['emergency'].get('everSecure')
            assert not unknown['descriptor']['units']['emergency']['client']
            (work / 'unknown-probe-exit.json').write_text(json.dumps(unknown, indent=2))
            run(['systemctl', '--user', 'kill', '--signal=SIGCONT', '--kill-whom=main', unit])
            owner_stopped = False
            wait_for(lambda: inspect()['descriptor']['units']['emergency']['identity']['InvocationID'] != probe['identity']['InvocationID'])
        if args.case == 'opaque-expiry':
            from locker_framebuffer import Framebuffer
            def requested_without_surfaces():
                view = inspect()
                record = (view.get('descriptor') or {}).get('units', {}).get('real')
                if not record:
                    return False
                text = run(['journalctl', '--user', '-b', '--no-pager', '-o', 'cat',
                    '_SYSTEMD_INVOCATION_ID=' + record['identity']['InvocationID']]).stdout
                return text if 'requested-without-surfaces' in text else False
            before = wait_for(requested_without_surfaces, 15)
            initial_started = time.monotonic()
            initial_pixels = output_capture('opaque-initial-request')
            initial_output = {'beforeCaptureJournal': before, 'pixels': initial_pixels, 'captureStarted': initial_started}
            if os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'):
                # Finding, not a pass: Hyprland draws the desktop until the
                # client is sent locked/finished or lockdead_screen_delay passes.
                # Bound that window with one capture after the guest's delay.
                hypr_timers = hypr_lock_timers()
                requested_at = next(json.loads(line)['monotonic'] for line in before.splitlines()
                    if '"requested-without-surfaces"' in line)
                wait_for(lambda: time.monotonic() >= requested_at + hypr_timers['lockdeadScreenDelay'] + .25, 5)
                dead_started = time.monotonic()
                dead_pixels = output_capture('opaque-after-lockdead-delay')
                assert not dead_pixels['sentinelVisible'], 'desktop sentinel after misc:lockdead_screen_delay'
                initial_output['hyprland'] = {'timers': hypr_timers, 'requestedAt': requested_at,
                    'initialCaptureAfterRequest': initial_started - requested_at,
                    'initialSentinelVisible': initial_pixels['sentinelVisible'],
                    'deadDelayCaptureAfterRequest': dead_started - requested_at, 'deadDelayPixels': dead_pixels}
            (work / 'opaque-initial-output.json').write_text(json.dumps(initial_output, indent=2))
        if intent:
            ipc('lockerProof', 'lockAndSuspend')
            assert json.loads(ipc('lockerProof', 'completions'))['suspend'] == 0, 'suspend before secure'
        if args.case == 'hooks':
            ipc('lockerProof', 'overlapHook')
            ipc('lockerProof', 'lockViaHook')
        if args.restart_state == 'starting':
            wait_for(lambda: inspect().get('descriptor', {}).get('generation') != old_generation
                and 'real' in inspect()['descriptor']['units'])
            restart_at('starting')
        expected_role = 'emergency' if args.case in ('opaque', 'slow', 'report-unknown') or (args.case == 'external' and not unconfirmed) else 'real'
        crashed = None
        if hypr_crash:
            # With restore=1 a later lock replaces even a live holder, so the
            # deadline probe is never refused and the unconfirmed state cannot
            # arise. Crash the sole secure opaque holder before the 3 s deadline
            # instead: its exit is the probe event, the dead lock is the target.
            def holder_secure():
                descriptor = inspect().get('descriptor') or {}
                record = (descriptor.get('units') or {}).get('real')
                if descriptor.get('generation') == old_generation or not record:
                    return None
                text = run(['journalctl', '--user', '-b', '--no-pager', '-o', 'cat',
                    '_SYSTEMD_INVOCATION_ID=' + record['identity']['InvocationID']]).stdout
                return record if re.search(r'ext_session_lock_v1#\d+\.locked\(\)', text) else None
            crashed = wait_for(holder_secure, 3)
            before_crash = inspect()['descriptor']
            assert 'emergency' not in before_crash['units'] and time.monotonic() < before_crash['emergencyAt'] - .3, 'opaque holder secured too late for a sole-holder crash'
            crashed_at = time.monotonic()
            run(['systemctl', '--user', 'kill', '--signal=SIGKILL', '--kill-whom=all', crashed['name']])
            from locker_framebuffer import Framebuffer
            console = Framebuffer()
            try:
                console.capture(work / 'dead-holder.ppm')
                assert not console.sentinel_visible(), 'unlocked desktop after the opaque holder crashed'
            finally:
                console.close()
            unconfirmed = False
            expected_role = 'emergency'
        def owner_status():
            return json.loads(ipc('lockOwner', 'status'))
        def secured():
            nonlocal expected_role
            view = inspect()
            descriptor = view.get('descriptor') or {}
            if unconfirmed:
                return descriptor.get('generation') != old_generation and owner_status()['state'] == 'engaged-unconfirmed(external)'
            if args.case == 'boundary':
                holders = [role for role in ('real', 'emergency')
                    if (descriptor.get('units', {}).get(role, {}).get('client') or {}).get('secure')
                    and not descriptor['units'][role]['client'].get('terminal')
                    and view.get('units', {}).get(role, {}).get('sameInvocation')
                    and not view['units'][role]['gone']]
                assert len(holders) <= 1, 'two live secure holders'
                if holders:
                    expected_role = holders[0]
                    return descriptor.get('generation') != old_generation
                return False
            record = descriptor.get('units', {}).get(expected_role, {})
            client = record.get('client') or {}
            observation = view.get('units', {}).get(expected_role, {})
            return (descriptor.get('generation') != old_generation and descriptor.get('phase') != 'settled'
                    and client.get('secure') and not client.get('terminal')
                    and observation.get('sameInvocation') and not observation.get('gone'))
        wait_for(secured, 15)
        first = inspect()
        if args.suspend_after_inspect_race:
            wait_for((work / 'after-consume-inspect.json').exists, 15)
            captured = json.loads((work / 'after-consume-inspect.json').read_text())['value']
            assert captured['descriptor']['generation'] == first['descriptor']['generation']
            assert captured['descriptor']['units']['real']['client']['secure']
            assert configuration['general']['lockOnSuspend'] is args.suspend_race_lock_on_suspend
            auth_at = time.monotonic()
            authenticate()
            try:
                wait_for(lambda: not compositor_locked(work, sid), 5)
            except AssertionError:
                if not args.recover_known_pam_hang:
                    raise
                recover_known_pam_hang(source, sid, 'real', work)
                authenticate()
                wait_for(lambda: not compositor_locked(work, sid), 10)
            before_release = inspect()
            assert before_release['descriptor']['phase'] == 'unlocking'
            (work / 'release-after-consume-inspect').touch(mode=0o600)
            wait_for((work / 'sleep-service-entered.json').exists, 20)
            entered = json.loads((work / 'sleep-service-entered.json').read_text())
            at_sleep = inspect()
            locked_at_sleep = compositor_locked(work, sid)
            events = [json.loads(line) for line in (work / 'observer/events.jsonl').read_text().splitlines()]
            ordering = authenticated_unlocks(events, 1)
            (work / 'suspend-race-result.json').write_text(json.dumps({
                'lockOnSuspend': args.suspend_race_lock_on_suspend, 'authInputAt': auth_at, 'captured': captured,
                'beforeRelease': before_release, 'sleepServiceEntered': entered,
                'atSleep': at_sleep, 'lockedAtSleep': locked_at_sleep, 'pamOrdering': ordering}, indent=2))
            if args.suspend_race_lock_on_suspend:
                assert locked_at_sleep and entered['lockedHintAtEntry'] == 'yes', 'lockOnSuspend did not relock before actual sleep entry'
                holder = at_sleep['descriptor']['units']['real']
                assert at_sleep['descriptor']['generation'] != captured['descriptor']['generation']
                def relock_events():
                    observed = [json.loads(line) for line in (work / 'observer/events.jsonl').read_text().splitlines()]
                    return [row['sourceMonotonic'] for row in observed if row['kind'] == 'journal'
                        and row['invocation'] == holder['identity']['InvocationID']
                        and re.search(r'ext_session_lock_v1#\d+\.locked\(\)', row['message'])]
                secure_events = wait_for(relock_events, 10)
                sleep_harness.entered(min(secure_events))
                wait_for(lambda: any(row['kind'] == 'prepare-for-sleep' and not row['sleeping']
                    for row in [json.loads(line) for line in (work / 'observer/events.jsonl').read_text().splitlines()]), 15)
                assert compositor_locked(work, sid), 'lock not intact through PrepareForSleep(false)'
                authenticate()
                wait_for(lambda: not compositor_locked(work, sid), 10)
                wait_for(lambda: inspect()['descriptor']['phase'] == 'settled', 15)
                wait_for(lambda: sum(row['kind'] == 'journal' and 'unlock_and_destroy' in row.get('message', '')
                    for row in [json.loads(line) for line in (work / 'observer/events.jsonl').read_text().splitlines()]) == 2, 10)
                events = [json.loads(line) for line in (work / 'observer/events.jsonl').read_text().splitlines()]
                (work / 'pam-unlock-ordering.json').write_text(json.dumps(authenticated_unlocks(events, 2), indent=2))
            else:
                assert not locked_at_sleep and entered['lockedHintAtEntry'] == 'no', 'intervening successful PAM ordering not exercised'
                (work / 'release-sleep-service').touch(mode=0o600)
            wait_for(lambda: inspect()['descriptor']['phase'] == 'settled', 15)
            unlocked = True
            (work / 'result.txt').write_text('PASS suspend with intervening PAM, lockOnSuspend=' + str(args.suspend_race_lock_on_suspend) + '\n')
            print('PASS suspend with intervening PAM, lockOnSuspend=' + str(args.suspend_race_lock_on_suspend), work)
            return
        if args.ingress == 'hot-corner':
            # End this gesture while locked; a pointer left in the corner can
            # start a fresh dwell when the shell returns after authentication.
            from locker_framebuffer import Framebuffer
            console = Framebuffer()
            try:
                console.socket.sendall(struct.pack('>BBHH', 5, 0, console.width // 2, console.height // 2))
                (work / 'hot-corner-pointer-rest.json').write_text(json.dumps({
                    'monotonic': time.monotonic(), 'x': console.width // 2, 'y': console.height // 2}))
            finally:
                console.close()
        sample_load('first-secure')
        if crashed:
            recovery = first['descriptor']['units']['emergency']
            assert recovery['startedAt'] - crashed_at < 3, 'crash did not start the emergency lock at once'
            assert recovery['startedAt'] < first['descriptor']['emergencyAt'], 'probe came from the deadline, not the crash'
            assert first['descriptor']['probeEvents']['exit:' + crashed['identity']['InvocationID']] == recovery['identity']['InvocationID']
            assert first['units']['real']['gone'] and not first['units']['real']['members']
            from locker_framebuffer import Framebuffer
            console = Framebuffer()
            try:
                console.capture(work / 'probe-secure.ppm')
                assert not console.sentinel_visible(), 'unlocked desktop under the recovery probe'
            finally:
                console.close()
            (work / 'crash-response.json').write_text(json.dumps({'candidateInvocation': crashed['identity']['InvocationID'],
                'probeInvocation': recovery['identity']['InvocationID'], 'secondsToLaunch': recovery['startedAt'] - crashed_at,
                'restore': 1, 'note': 'dead-client takeover by the owner probe; product takeover policy unchanged'}, indent=2))
        if args.sleep_signals:
            # The real manager must wait on its real delay fd before entering
            # our no-kernel-sleep service. Observe native secure, fd release,
            # service entry, then let the normal manager publish resume.
            def native_secure_time():
                events = [json.loads(line) for line in (work / 'observer/events.jsonl').read_text().splitlines()]
                secure = [event['sourceMonotonic'] for event in events if event['kind'] == 'journal'
                    and re.search(r'ext_session_lock_v1#\d+\.locked\(\)', event['message'])]
                return min(secure) if secure else None
            if args.case == 'opaque-expiry':
                from locker_framebuffer import Framebuffer
                wait_for((work / 'sleep-service-entered.json').exists, 20)
                expired = wait_for(lambda: next((row for row in sleep_harness.events()
                    if row['value']['event'] == 'unconfirmed'), None), 5)
                released = wait_for(lambda: next((row for row in sleep_harness.events()
                    if row['value']['event'] == 'released'), None), 5)
                prepared = next(row for row in sleep_harness.events()
                    if row['value']['event'] == 'prepare' and row['value']['sleeping'])
                entered = json.loads((work / 'sleep-service-entered.json').read_text())
                assert expired['value']['message'] == 'suspend without confirmed secure lock (opaque locker)'
                assert expired['value']['monotonic'] - prepared['value']['monotonic'] >= expired['value']['maxDelay']
                assert not released['value']['secure'] and not sleep_harness.inhibitors(sleep_harness.pid)
                status = owner_status()
                assert status['state'] == 'engaged-unconfirmed(external)' and not status['secure']
                assert inspect()['units']['real']['sameInvocation'] and not inspect()['units']['real']['gone']
                assert not (work / 'release-surfaces').exists()
                pixels = output_capture('opaque-at-inhibitor-expiry')
                assert not pixels['sentinelVisible'], 'desktop sentinel exposed at inhibitor expiry'
                (work / 'opaque-expiry-finding.json').write_text(json.dumps({'prepared': prepared,
                    'expired': expired, 'released': released, 'sleepServiceEntered': entered,
                    'status': status, 'pixels': pixels, 'nativeSecureAt': native_secure_time(),
                    'ownerConfirmedSecure': False, 'kernelSleepInvoked': False}, indent=2))
                (work / 'release-sleep-service').touch(mode=0o600)
            else:
                sleep_harness.entered(wait_for(native_secure_time, 10))
            def resumed():
                events = [json.loads(line) for line in (work / 'observer/events.jsonl').read_text().splitlines()]
                sleep = [event for event in events if event['kind'] == 'prepare-for-sleep']
                return sleep if len(sleep) >= 2 and not sleep[-1]['sleeping'] else None
            sleep = wait_for(resumed, 45)
            assert [event['sleeping'] for event in sleep] == [True, False], 'missing or duplicated real sleep window'
            kernel_text = run(['sudo', '-n', 'journalctl', '-b', '-k', '--no-pager', '-o', 'json', '--after-cursor=' + kernel_cursor]).stdout
            kernel = [json.loads(line) for line in kernel_text.splitlines()]
            (work / 'sleep-kernel.json').write_text(json.dumps(kernel, indent=2))
            assert not any('PM: suspend entry' in record.get('MESSAGE', '') for record in kernel), 'fixture unexpectedly suspended the kernel'
            if args.case == 'opaque-expiry' and os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'):
                hypr_resumed_locked(sleep[-1])
            else:
                assert compositor_locked(work, sid), 'resumed unlocked'
            wait_for(lambda: sleep_harness.inhibitors(sleep_harness.pid), 10)
            if suspend_command is not None:
                assert suspend_command.wait(timeout=10) == 0
            from locker_framebuffer import Framebuffer
            if args.case == 'opaque-expiry':
                assert not output_capture('opaque-after-resume')['sentinelVisible'], 'unlocked desktop after resume'
            else:
                console = Framebuffer()
                try:
                    console.capture(work / 'after-resume.ppm')
                    assert not console.sentinel_visible(), 'unlocked desktop after resume'
                finally:
                    console.close()
            (work / 'sleep-result.json').write_text(json.dumps({'route': args.sleep_route, 'events': sleep,
                'realLogindSignals': True, 'kernelSleepInvoked': False, 'lockIntactOnResume': True,
                'hardwareLimit': "real S3 not testable in this VM; to be checked on the user's machine"}, indent=2))
            if args.case == 'opaque-expiry':
                (work / 'release-surfaces').touch(mode=0o600)
                def fixture_mapped():
                    journal = run(['journalctl', '--user', '-b', '--no-pager', '-o', 'cat',
                        '_SYSTEMD_INVOCATION_ID=' + first['descriptor']['units']['real']['identity']['InvocationID']]).stdout
                    return 'surface-committed' in journal and 'keyboard-focus' in journal
                wait_for(fixture_mapped, 10)
                # The deadline probe can supersede the initial sleep-window
                # probe while the no-surface fixture remains unconfirmed.
                first = inspect()
        if args.late_real_first:
            assert (work / 'grant-held.json').exists(), 'real acquisition did not pass the actual grant barrier'
            assert (work / 'probe-at-barrier.json').exists(), 'deadline emergency was not exercised'
            (work / 'release-probe').touch(mode=0o600)
            wait_for(lambda: inspect()['units']['emergency']['gone'])
            first = inspect()
        if args.ingress == 'hooks':
            assert first['units']['prehook']['gone'], 'real lock bypassed unfinished pre-hook'
            assert first['descriptor']['units']['prehook']['startedAt'] < first['descriptor']['units']['real']['startedAt']
        if args.ingress == 'idle':
            idle_enabled(False)
            journal = run(['journalctl', '--user', '-b', '--no-pager', '-o', 'cat', '_SYSTEMD_INVOCATION_ID=' + owner]).stdout
            assert 'Executing action: lock' in journal and 'Idle fired: lock' in journal, 'idle ingress did not fire natively'
        if args.ingress == 'hot-corner':
            text = run(['journalctl', '--user', '-b', '--no-pager', '-o', 'cat', '_SYSTEMD_INVOCATION_ID=' + owner]).stdout
            events = [line for line in text.splitlines() if 'HotCorners' in line and 'run bottomRight' in line]
            assert len(events) == 1 and 'Virtual-1' in events[0], 'exact hot-corner action not observed'
        (work / 'ingress.json').write_text(json.dumps({'route': args.ingress, 'snapshot': first['descriptor']['snapshot']}, indent=2))
        (work / ('first-unconfirmed.json' if unconfirmed else 'first-secure.json')).write_text(json.dumps(first, indent=2))
        assert first['descriptor']['units']['real']['startedAt'] < first['descriptor']['emergencyAt']
        if args.case == 'boundary':
            from locker_framebuffer import Framebuffer
            wait_for(lambda: (work / 'ready-at-barrier.json').exists())
            ready = json.loads((work / 'ready-at-barrier.json').read_text())
            assert ready['requestedAt'] == first['descriptor']['requestedAt']
            assert ready['arrived'] < ready['target']
            # Capture the actual readiness/deadline window, not 30 seconds of
            # identical waiting frames. The continuous protocol observer spans
            # the complete generation, including all the preceding time.
            wait_for(lambda: time.monotonic() >= ready['target'] - 1, args.delay + 5)
            console = Framebuffer()
            frames = []
            until = max(first['descriptor']['requestedAt'] + args.delay + 3, time.monotonic() + 1)
            try:
                while time.monotonic() < until:
                    view = inspect()
                    holders = [role for role, record in view['descriptor']['units'].items()
                        if record.get('client') and record['client']['secure'] and not record['client']['terminal']
                        and view['units'][role]['sameInvocation'] and not view['units'][role]['gone']]
                    assert len(holders) <= 1, 'two secure holders at boundary'
                    frame = work / ('boundary-frame-%04d.ppm' % len(frames))
                    at = time.monotonic()
                    console.capture(frame)
                    assert not console.sentinel_visible(), 'unlocked desktop during boundary race'
                    frames.append({'file': frame.name, 'at': at, 'holders': holders, 'view': view})
                    time.sleep(.05)
            finally:
                console.close()
                (work / 'boundary-frames.json').write_text(json.dumps(frames, indent=2))
            assert frames
            wait_for(secured, 10)
            first = inspect()
            if args.delay >= 30:
                assert first['units']['real']['gone'] and not first['descriptor']['units']['real']['grant'], 'late-ready client retained acquisition authority'
                assert expected_role == 'emergency' and not first['descriptor']['handoverCommitted']
            else:
                released = json.loads((work / 'ready-released.json').read_text())
                assert released['released'] >= ready['target']
            if first['descriptor']['units']['real']['grant']:
                candidate = first['descriptor']['units']['real']['client']
                assert candidate['secure'] or (first['units']['real']['gone'] and candidate['terminal']
                    and candidate['settlement'] == 'finished'), 'granted boundary client neither secured nor settled its refusal'
            (work / 'boundary-outcome.json').write_text(json.dumps({'delay': args.delay, 'ready': ready,
                'holder': expected_role, 'view': first}, indent=2))
        if args.case == 'slow':
            assert first['descriptor']['units']['emergency']['startedAt'] >= first['descriptor']['emergencyAt'], 'early emergency deadline'
            assert first['descriptor']['units']['real']['startedAt'] < first['descriptor']['emergencyAt']
            if args.restart_state == 'fallback':
                restart_at('fallback')
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
                assert not compositor_locked(work, sid)
                assert not (work / 'real-delay-exec.json').exists(), 'revoked real command executed after emergency authentication'
                final = inspect()
                (work / 'final.json').write_text(json.dumps(final, indent=2))
                observer.stdin.close()
                assert observer.wait(timeout=10) == 0
                events = [json.loads(line) for line in (work / 'observer/events.jsonl').read_text().splitlines()]
                assert not any(event['kind'] == 'observer-error' for event in events)
                unlocks = [event for event in compositor_transitions(events) if not event['locked']]
                assert len(unlocks) == 1 and unlocks[0]['observed'] >= authenticated_at
                native_unlocks = [event for event in events if event['kind'] == 'journal' and 'unlock_and_destroy' in event['message']]
                assert len(native_unlocks) == 1 and native_unlocks[0]['sourceMonotonic'] >= authenticated_at
                (work / 'pam-unlock-ordering.json').write_text(json.dumps(authenticated_unlocks(events, 1), indent=2))
                assert native_unlocks[0]['invocation'] == first['descriptor']['units']['emergency']['identity']['InvocationID']
                if os.environ.get('NIRI_SOCKET'):
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
            if args.delay < 30 and not takeover:
                # A compositor without proven dead-client restore must retain
                # the live emergency, not manufacture a dead-holder handover.
                wait_for(lambda: inspect()['units']['real']['gone'])
                retained = inspect()
                assert not retained['descriptor']['handoverCommitted']
                assert retained['descriptor']['units']['emergency']['client']['secure']
                assert not (retained['descriptor']['units']['real'].get('client') or {}).get('requested')
                if args.restart_state == 'handing-over':
                    restart_at('fallback')
                    (work / 'restart-policy.json').write_text(json.dumps({'requested': 'handing-over',
                        'observed': 'retained-fallback', 'takeover': False,
                        'reason': 'handover is unreachable without proven dead-client restore'}))
                from locker_framebuffer import Framebuffer
                console = Framebuffer()
                try:
                    console.capture(work / 'emergency-retained.ppm')
                    assert not console.sentinel_visible()
                finally:
                    console.close()
                wait_for(lambda: time.monotonic() > first['descriptor']['units']['real']['startedAt'] + args.delay + 1, args.delay + 5)
                assert not (work / 'real-delay-exec.json').exists(), 'cancelled real candidate executed'
                (work / 'no-takeover.json').write_text(json.dumps(retained, indent=2))
            elif args.delay < 30:
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
                    if args.restart_state == 'handing-over':
                        restart_at('handing-over')
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
            selected = configuration['general']['externalLockCommand']
            if args.ingress == 'custom':
                selected = configuration['sessionMenu']['powerOptions'][0]['command']
            elif args.ingress == 'exclusive':
                selected = 'sh -lc ' + shlex.quote(configuration['hooks']['handlers']['lockAction']['command'])
            assert first['descriptor']['snapshot']['command'] == selected
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
            assert compositor_locked(work, sid)
        if args.case == 'report-refusal':
            probe = inspect()['descriptor']['units']['emergency']
            assert inspect()['units']['emergency']['gone']
            report = probe['protocolReport']
            assert report['event'] == 'finished' and not report['everSecure']
            assert probe['protocolOutcome'] == 'finished' and not owner_status()['secure']
            text = run(['journalctl', '--user', '-b', '--no-pager', '-o', 'cat',
                '_SYSTEMD_INVOCATION_ID=' + probe['identity']['InvocationID']]).stdout
            if os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'):
                assert 'invalid object' in text, 'native refused-probe crash was hidden'
            trace = []
            for path in work.glob('probe-syscalls.*'):
                if path.name != 'probe-syscalls.' + str(probe['clientIdentity']['pid']):
                    continue  # Prove the synchronous client handler, not a helper's fsync.
                for line in path.read_text().splitlines():
                    try:
                        trace.append((float(line.split()[0]), '[trace=' + path.name + '] ' + line))
                    except (ValueError, IndexError):
                        pass
            received = min(at for at, line in trace if re.search(r'ext_session_lock_v1#\d+\.finished\(', line))
            destroyed = min(at for at, line in trace if re.search(r'ext_session_lock_surface_v1#\d+\.destroy\(', line))
            committed = process_report_commit(trace, probe['reportInfo']['path'], received, destroyed)
            (work / 'durable-refusal.json').write_text(json.dumps({'report': report, 'probe': probe,
                'finishedAt': received, 'atomicCommit': committed, 'surfaceDestroyAt': destroyed,
                'persistenceScope': 'same-boot process survival, not power-loss/reboot',
                'nativeErrorVisible': 'invalid object' in text}, indent=2))
            # This focused proof observes the refused report. Hyprland opaque
            # unit-exit observation belongs to the next addendum integration.
            ipc('lockerProof', 'exit')
            auth_at = time.monotonic()
            authenticate()
            wait_for(lambda: inspect()['units']['real']['gone'], 20)
            wait_for(lambda: not compositor_locked(work, sid))
            manage(source, {'operation': 'settle', 'session': sid, 'generation': first['descriptor']['generation']})
            final = inspect()
            assert all(row['gone'] and not row['members'] for row in final['units'].values())
            observer.stdin.close()
            assert observer.wait(timeout=10) == 0
            events = [json.loads(line) for line in (work / 'observer/events.jsonl').read_text().splitlines()]
            releases = [row for row in compositor_transitions(events) if not row['locked']]
            native_unlocks = [row for row in events if row['kind'] == 'journal' and 'unlock_and_destroy' in row['message']]
            assert len(releases) == len(native_unlocks) == 1
            (work / 'pam-unlock-ordering.json').write_text(json.dumps(authenticated_unlocks(events, 1), indent=2))
            assert releases[0]['observed'] >= auth_at and native_unlocks[0]['sourceMonotonic'] >= auth_at
            assert native_unlocks[0]['invocation'] == first['descriptor']['units']['real']['identity']['InvocationID']
            (work / 'final.json').write_text(json.dumps(final, indent=2))
            unlocked = True
            (work / 'result.txt').write_text('PASS durable refused-probe report before native teardown\n')
            print('PASS durable refused-probe report before native teardown', work)
            return
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
            assert compositor_locked(work, sid)
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
            assert not compositor_locked(work, sid)
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
                assert compositor_locked(work, sid)
                authenticated_inputs.append(time.monotonic())
                authenticate()
                expected_role = 'emergency'
        wait_for(lambda: inspect()['descriptor']['phase'] == 'settled', 15)
        final = inspect()
        (work / 'final.json').write_text(json.dumps(final, indent=2))
        assert all(item['gone'] and not item['members'] for item in final['units'].values())
        if args.case == 'hooks' or args.ingress == 'hooks':
            assert marker.read_text() == 'prelockunlock', 'hook duplicated or lost after adoption'
        assert not compositor_locked(work, sid)
        if sentinel_identity:
            from locker_framebuffer import Framebuffer
            console = Framebuffer()
            try:
                def authenticated_sentinel():
                    if args.case == 'opaque-expiry':
                        return output_capture('unlocked-after')['sentinelVisible']
                    console.capture(work / 'unlocked-after.ppm')
                    return all(console.sentinel_corners())
                wait_for(authenticated_sentinel)
            finally:
                console.close()
        if args.case in ('slow', 'boundary', 'external', 'opaque-holder', 'opaque-sleep', 'opaque-race', 'opaque-withdraw', 'opaque-expiry') or args.ingress == 'hot-corner':
            time.sleep(10)
            assert inspect()['descriptor']['phase'] == 'settled'
            assert inspect()['descriptor']['generation'] == final['descriptor']['generation'], 'unexpected follow-on generation'
            assert all(item['gone'] and not item['members'] for item in inspect()['units'].values())
            assert not compositor_locked(work, sid), 'delayed relock'
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
        transitions = compositor_transitions(events)
        assert any(event['locked'] for event in transitions), 'missing compositor-originated lock observation'
        unlocks = [event for event in transitions if not event['locked']]
        assert len(unlocks) == len(authenticated_inputs), 'unlock/relock outside approved race'
        assert all(event['observed'] >= at for event, at in zip(unlocks, authenticated_inputs)), 'unlock before successful PAM input'
        native_unlocks = [event for event in events if event['kind'] == 'journal' and 'unlock_and_destroy' in event['message']]
        assert len(native_unlocks) == len(authenticated_inputs), 'unexpected native unlock'
        (work / 'pam-unlock-ordering.json').write_text(json.dumps(authenticated_unlocks(events, len(authenticated_inputs)), indent=2))
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
        if args.case == 'slow' and args.delay < 30 and not takeover:
            assert expected_role == 'emergency' and not final['descriptor']['handoverCommitted']
            assert not re.search(r'ext_session_lock_v1#\d+\.locked\(\)', run(['journalctl', '--user', '-b',
                '--no-pager', '-o', 'cat', '_SYSTEMD_INVOCATION_ID=' + final['descriptor']['units']['real']['identity']['InvocationID']]).stdout)
            timings['outcome'] = 'emergency-retained-no-takeover'
        elif args.case == 'fast' or (args.case == 'slow' and args.delay < 30):
            timings['outcome'] = deadline_outcome(final['descriptor'], events)
            if args.late_real_first:
                assert timings['outcome'] == 'late-real-first'
            if args.case == 'slow':
                assert timings['outcome'] == 'emergency-first-handover'
        (work / 'startup-timings.json').write_text(json.dumps(timings, indent=2))
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
        current = None
        observer_error = None
        try:
            if owner_stopped:
                run(['systemctl', '--user', 'kill', '--signal=SIGCONT', '--kill-whom=main', unit])
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
            sample_load('end')
            event_path = work / 'observer/events.jsonl'
            if current.get('descriptor') and event_path.exists():
                descriptor = current['descriptor']
                events = [json.loads(line) for line in event_path.read_text().splitlines()]
                native = []
                for role, record in descriptor['units'].items():
                    for event in events:
                        if (event['kind'] == 'journal' and event['invocation'] == record['identity']['InvocationID']
                                and re.search(r'ext_session_lock_v1#\d+\.(locked|finished)\(\)', event['message'])):
                            native.append({'role': role, 'invocation': event['invocation'],
                                'secondsFromRequest': event['sourceMonotonic'] - descriptor['requestedAt'],
                                'message': event['message']})
                (work / 'native-startup-timings.json').write_text(json.dumps({'native': native,
                    'requestedAt': descriptor['requestedAt'], 'emergencyAt': descriptor['emergencyAt'],
                    'handoverCommitted': descriptor['handoverCommitted']}, indent=2))
            (work / 'last-observation.json').write_text(json.dumps(current, indent=2))
            if owner:
                journal = run(['journalctl', '--user', '-b', '--no-pager', '-o', 'cat',
                               '_SYSTEMD_INVOCATION_ID=' + owner]).stdout
                (work / 'owner-journal.txt').write_text(journal)
        finally:
            # Evidence failures still fail the proof, but may not skip its
            # independent teardown/restoration obligations. Never unlock here.
            try:
                try:
                    if owner:
                        actual = run(['systemctl', '--user', 'show', unit, '-p', 'InvocationID', '--value']).stdout.strip()
                        assert actual in ('', owner), 'harness root invocation replaced'
                        if actual:
                            run(['systemctl', '--user', 'stop', unit])
                    if sentinel_identity:
                        actual = run(['systemctl', '--user', 'show', sentinel_unit, '-p', 'InvocationID', '--value']).stdout.strip()
                        assert actual in ('', sentinel_identity), 'sentinel invocation replaced'
                        if actual:
                            run(['systemctl', '--user', 'stop', sentinel_unit])
                            assert run(['systemctl', '--user', 'show', sentinel_unit, '-p', 'MainPID', '--value']).stdout.strip() == '0'
                finally:
                    # A sentinel evidence/identity failure must not skip safe
                    # restoration after already-authenticated settlement.
                    hint = run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip()
                    settled = current is not None and (not current.get('descriptor') or current['descriptor']['phase'] == 'settled')
                    if hint == 'no' and (unlocked or settled):
                        run(['sudo', '-n', 'chpasswd', '-e'], input='tester:' + original_hash + '\n')
                        credential.unlink()
                        original_shadow.unlink()
                    else:
                        print('Real-PAM recovery required; protected recovery files in', work, file=__import__('sys').stderr)
            finally:
                if restore_niri_config is not None:
                    run(['niri', 'msg', 'action', 'load-config-file', '--path', str(restore_niri_config)], env=environment)
                if sleep_harness is not None:
                    sleep_harness.close()
        if observer_error is not None:
            raise observer_error


if __name__ == '__main__':
    main()
