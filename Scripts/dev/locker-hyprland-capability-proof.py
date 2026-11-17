#!/usr/bin/env python3
"""Hyprland misc:allow_session_lock_restore capability, at the compositor level.

Guest-only. Holders are the shipped standalone emergency lock in exact test
units, observed through the native hyprland-lock-notify subscription, the
holders' own protocol traces and the named VM's console. Nothing here unlocks
except real PAM input into the current holder. The option is changed only at
runtime in this disposable guest and restored to the saved original (value
and `set` flag) before the proof can pass.

dead-client:  restore=0 keeps a dead holder's lock and denies a new client;
              restore=1 lets a new client take the still-locked session over.
live-replace: restore=1 also lets a new client replace a LIVE secure holder.
"""
import argparse
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import time

from locker_test_support import (compositor_locked, compositor_transitions, hypr_option as option, manage, require_guest,
    restore_hypr_option as restore_option, run, set_hypr_option as set_option, wait_for)

LOCKED = re.compile(r'ext_session_lock_v1#\d+\.locked\(\)')
FINISHED = re.compile(r'ext_session_lock_v1#\d+\.finished\(\)')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--subcase', choices=('dead-client', 'live-replace'), required=True)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    source, work = require_guest(args.work, Path(__file__).resolve().parents[2])
    assert os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'), 'Hyprland session required'
    assert os.environ.get('LOCKER_FRAMEBUFFER_PORT') and os.environ.get('LOCKER_TEST_VM_NAME'), 'named VM console required'
    sid = manage(source, {'operation': 'discover'})['session']
    original = option()
    (work / 'original-option.json').write_text(json.dumps(original))
    assert original['int'] == 0, 'capability proof starts from restore disabled'
    stage = work / 'stage'
    run(['bash', '-eu', '-c', 'source "$1/packaging/aur/package.sh"; package', 'stage', str(source)],
        env=dict(os.environ, srcdir=str(source.parent), _gitname=source.name, pkgdir=str(stage), pkgver='0.9.3'), timeout=60)
    environment = dict(os.environ, XDG_CONFIG_DIRS=str(stage / 'etc/xdg') + ':/etc/xdg', WAYLAND_DEBUG='client',
        ATMOSPHERA_CACHE_DIR=str(work / 'cache'), ATMOSPHERA_STATE_DIR=str(work / 'state'))
    for key in ('ATMOSPHERA_LOCK_SESSION', 'ATMOSPHERA_LOCK_GENERATION', 'ATMOSPHERA_LOCK_ROLE', 'ATMOSPHERA_LOCK_ADAPTER'):
        environment.pop(key, None)
    password = secrets.token_hex(16)
    credential = work / 'credential'
    original_shadow = work / 'original-shadow-hash'
    original_hash = run(['sudo', '-n', 'getent', 'shadow', 'tester']).stdout.split(':')[1]
    for path, value in ((credential, password), (original_shadow, original_hash)):
        path.touch(mode=0o600)
        path.write_text(value)
    run(['sudo', '-n', 'chpasswd'], input='tester:' + password + '\n')
    units = {}
    observer = None
    sentinel = None
    unlocked = False
    timeline = []

    def mark(event, **values):
        timeline.append(dict(event=event, monotonic=time.monotonic(), **values))
        (work / 'timeline.json').write_text(json.dumps(timeline, indent=2))

    def status(name):
        fields = ('InvocationID', 'ControlGroup', 'MainPID', 'ActiveState', 'Result')
        result = subprocess.run(['systemctl', '--user', 'show', name, *[v for f in fields for v in ('-p', f)]],
            text=True, capture_output=True, timeout=10)
        values = dict(row.split('=', 1) for row in result.stdout.splitlines() if '=' in row)
        return {field: values.get(field, '') for field in fields}

    def launch(role, command):
        unit = 'locker-capability-' + role + '.service'
        assert status(unit)['ActiveState'] in ('', 'inactive', 'failed'), 'stale capability unit'
        keys = ('WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE', 'XDG_CURRENT_DESKTOP', 'XDG_SESSION_TYPE',
            'XDG_RUNTIME_DIR', 'DBUS_SESSION_BUS_ADDRESS', 'TMPDIR', 'HOME', 'USER', 'PATH', 'XDG_CONFIG_DIRS',
            'ATMOSPHERA_CACHE_DIR', 'ATMOSPHERA_STATE_DIR', 'WAYLAND_DEBUG')
        run(['systemd-run', '--user', '--collect', '--unit=' + unit, '--property=KillMode=control-group',
            '--property=TimeoutStopSec=2s', '--property=ExitType=cgroup',
            *['--setenv=' + key + '=' + environment[key] for key in keys if key in environment], '--', *command])
        identity = status(unit)
        assert identity['InvocationID'] and int(identity['MainPID']) > 0, identity
        units[role] = dict(identity, name=unit)
        (work / 'units.json').write_text(json.dumps(units, indent=2))
        mark('launch', role=role, invocation=identity['InvocationID'])

    def holder(role):
        launch(role, ['qs', '-c', 'atmosphera-emergency-lock'])

    def live(role):
        now = status(units[role]['name'])
        return now['InvocationID'] == units[role]['InvocationID'] and now['ActiveState'] in ('active', 'deactivating')

    def journal(role):
        text = run(['journalctl', '--user', '-b', '--no-pager', '-o', 'cat',
            '_SYSTEMD_INVOCATION_ID=' + units[role]['InvocationID']]).stdout
        return '\n'.join(line for line in text.splitlines() if 'wl_keyboard' not in line)

    def native_locked(role):
        return LOCKED.search(journal(role)) is not None

    def frame(label):
        from locker_framebuffer import Framebuffer
        console = Framebuffer()
        try:
            console.capture(work / (label + '.ppm'))
            visible = console.sentinel_visible()
        finally:
            console.close()
        mark('frame', label=label, sentinelVisible=visible)
        assert not visible, 'unlocked desktop sentinel visible: ' + label
        return visible

    def authenticate(role):
        run(['wtype', 'wrong-password'], env=environment)
        run(['wtype', '-k', 'Return'], env=environment)
        time.sleep(3)
        assert compositor_locked(work, sid) and live(role), 'wrong password changed the lock'
        run(['wtype', '-M', 'ctrl', '-k', 'a', '-m', 'ctrl', '-k', 'BackSpace'], env=environment)
        at = time.monotonic()
        mark('authenticate', role=role)
        with credential.open() as secret:
            run(['wtype', '-'], stdin=secret, env=environment)
        run(['wtype', '-k', 'Return'], env=environment)
        wait_for(lambda: not compositor_locked(work, sid), 20)
        mark('unlocked')
        return at

    try:
        observer = subprocess.Popen(['python3', '-B', str(source / 'Scripts/dev/locker-compositor-observer.py'),
            '--work', str(work / 'observer')], stdin=subprocess.PIPE, env=environment,
            stdout=(work / 'observer-stdout.txt').open('w'), stderr=(work / 'observer-stderr.txt').open('w'))
        wait_for(lambda: (work / 'observer/ready.json').exists(), 15)
        assert not compositor_locked(work, sid), 'existing compositor lock'
        sentinel_entry = work / 'desktop-sentinel.qml'
        shutil.copyfile(source / 'Scripts/dev/fixtures/locker-sentinel.qml', sentinel_entry)
        launch('sentinel', ['qs', '-p', str(sentinel_entry)])
        sentinel = units['sentinel']
        from locker_framebuffer import Framebuffer
        console = Framebuffer()
        try:
            def corners():
                console.capture(work / 'unlocked-before.ppm')
                return all(console.sentinel_corners())
            wait_for(corners, 15)
        finally:
            console.close()
        result = {'subcase': args.subcase, 'original': original}
        if args.subcase == 'dead-client':
            holder('first')
            wait_for(lambda: native_locked('first'), 20)
            wait_for(lambda: compositor_locked(work, sid), 5)
            mark('secure', role='first')
            frame('first-secure')
            run(['systemctl', '--user', 'kill', '--signal=SIGKILL', '--kill-whom=all', units['first']['name']])
            mark('killed', role='first')
            wait_for(lambda: not live('first'), 10)
            time.sleep(1.5)  # past misc:lockdead_screen_delay (1000 ms in this guest)
            assert compositor_locked(work, sid), 'dead holder unlocked the session'
            frame('dead-holder-restore0')
            holder('denied')
            wait_for(lambda: FINISHED.search(journal('denied')), 20)
            wait_for(lambda: not live('denied'), 10)
            assert not LOCKED.search(journal('denied')), 'restore=0 accepted a new lock over a dead holder'
            mark('denied', role='denied')
            assert compositor_locked(work, sid), 'denied replacement unlocked the session'
            frame('denied-restore0')
            set_option(1)
            mark('option', value=1)
            holder('takeover')
            wait_for(lambda: native_locked('takeover'), 20)
            mark('secure', role='takeover')
            frame('takeover-restore1')
            authenticated_at = authenticate('takeover')
            wait_for(lambda: not live('takeover'), 10)
            expected = {'first': 0, 'denied': 0, 'takeover': 1}
            result.update(denied='restore=0 denied a new lock over the dead holder (finished)',
                takeover='restore=1 accepted a new lock over the dead holder; locked() without an intermediate unlock')
        else:
            set_option(1)
            mark('option', value=1)
            holder('first')
            wait_for(lambda: native_locked('first'), 20)
            wait_for(lambda: compositor_locked(work, sid), 5)
            mark('secure', role='first')
            frame('first-secure-restore1')
            holder('replacement')
            wait_for(lambda: native_locked('replacement'), 20)
            mark('secure', role='replacement')
            time.sleep(1)
            assert live('first'), 'replaced holder exited'
            assert not FINISHED.search(journal('first')), 'replaced holder was told finished'
            frame('replaced-live-holder-restore1')
            authenticated_at = authenticate('replacement')
            wait_for(lambda: not live('replacement'), 10)
            # The superseded client was never told it lost the lock. It still
            # runs, convinced it is secure; stop only this exact test unit,
            # after the session is already unlocked by the user's own PAM.
            assert live('first') and not compositor_locked(work, sid)
            result['supersededStillRunning'] = True
            run(['systemctl', '--user', 'stop', units['first']['name']], timeout=20)
            wait_for(lambda: not live('first'), 10)
            mark('stopped-superseded', role='first')
            expected = {'first': 0, 'replacement': 1}
            result.update(replacement='restore=1 accepted a second client while a live holder was secure; '
                'the first client received no finished() and stayed running')
        restore_option(original)
        mark('option-restored', value=option())
        def sentinel_back():
            console = Framebuffer()
            try:
                console.capture(work / 'unlocked-after.ppm')
                return all(console.sentinel_corners())
            finally:
                console.close()
        wait_for(sentinel_back, 15)
        observer.stdin.close()
        assert observer.wait(timeout=15) == 0
        events = [json.loads(line) for line in (work / 'observer/events.jsonl').read_text().splitlines()]
        assert not any(event['kind'] == 'observer-error' for event in events)
        transitions = compositor_transitions(events)
        unlocks = [event for event in transitions if not event['locked']]
        assert len(unlocks) == 1 and unlocks[0]['observed'] >= authenticated_at, 'unlock outside authentication'
        assert transitions and transitions[0]['locked']
        for role, count in expected.items():
            text = journal(role)
            (work / (role + '-protocol.txt')).write_text(text)
            assert text.count('unlock_and_destroy') == count, (role, 'unexpected protocol unlock count')
        native_unlocks = [event for event in events if event['kind'] == 'journal' and 'unlock_and_destroy' in event['message']]
        assert len(native_unlocks) == 1 and native_unlocks[0]['sourceMonotonic'] >= authenticated_at
        unlocked = True
        result.update(transitions=transitions, restored=option(), timeline=timeline)
        (work / 'capability.json').write_text(json.dumps(result, indent=2))
        print('PASS hyprland-capability-' + args.subcase, work)
        (work / 'result.txt').write_text('PASS hyprland-capability-' + args.subcase + '\n')
    finally:
        try:
            if observer is not None and observer.poll() is None:
                if not observer.stdin.closed:
                    observer.stdin.close()
                observer.wait(timeout=15)
        finally:
            still_locked = True
            try:
                still_locked = compositor_locked(work, sid)
            except Exception:
                pass
            if not still_locked:
                for role, record in units.items():
                    if live(role):
                        run(['systemctl', '--user', 'stop', record['name']], timeout=20)
                restore_option(original)
                run(['sudo', '-n', 'chpasswd', '-e'], input='tester:' + original_hash + '\n')
                credential.unlink()
                original_shadow.unlink()
            else:
                # Never stop a possibly secure holder or drop restore=1 while a
                # dead or live lock needs real-PAM recovery.
                print('Real-PAM recovery required; option', option(), 'protected files in', work,
                      file=__import__('sys').stderr)
            (work / 'final-option.json').write_text(json.dumps(option()))
            if unlocked:
                assert option() == original


if __name__ == '__main__':
    main()
