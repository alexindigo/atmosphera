#!/usr/bin/env python3
"""Guest-only standalone bundled lock/PAM with unusable settings state.

No main shell, generation owner, synthetic authentication or unlock is used.
The installed LockContext gains only a read-only successful-PAM diagnostic.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import time

from locker_proof_oracles import authenticated_unlocks
from locker_test_support import cgroup_pids, compositor_locked, compositor_transitions, manage, require_guest, run, wait_for


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--mode', choices=('file', 'unwritable'), required=True)
    args = parser.parse_args()
    source, work = require_guest(args.work, Path(__file__).resolve().parents[2])
    sid = manage(source, {'operation': 'discover'})['session']
    stage = work / 'stage'
    run(['bash', '-eu', '-c', 'source "$1/packaging/aur/package.sh"; package', 'stage', str(source)],
        env=dict(os.environ, srcdir=str(source.parent), _gitname=source.name, pkgdir=str(stage), pkgver='0.9.3'), timeout=60)
    ui = stage / 'etc/xdg/quickshell/atmosphera-lockscreen/LockSession.qml'
    text = ui.read_text()
    anchor = '  id: root\n'
    assert text.count(anchor) == 1
    ui.write_text(text.replace(anchor, anchor + '  Connections { target: lockContext; function onDiagnostic(message) { '
        'if (message === "Authentication successful") console.log("LOCKER_PAM_SUCCESS " '
        '+ JSON.stringify({pid: Quickshell.processId})); } '
        'function onFailed() { console.log("LOCKER_PAM_REJECTED"); } }\n'))
    config = work / 'config'
    config.mkdir()
    (config / 'settings.json').write_text(json.dumps({'settingsVersion': 62,
        'general': {'lockScreenEnabled': True, 'lockScreenPlugin': 'default'}}))
    state = work / 'settings-state'
    if args.mode == 'file':
        state.write_text('unavailable directory: retain this file\n')
    else:
        state.mkdir(mode=0o500)
    # Prove the actual tester cannot create state, not just a mode-bit assumption.
    try:
        (state / 'write-refusal-control').write_text('must not succeed')
    except (PermissionError, NotADirectoryError):
        pass
    else:
        raise AssertionError('state is writable')
    def inputs():
        return {str(p.relative_to(config)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in config.rglob('*') if p.is_file()
            and (p.name == 'settings.json' or p.is_relative_to(config / 'settings'))}
    before = inputs()
    state_before = state.read_bytes() if state.is_file() else None
    environment = dict(os.environ, XDG_CONFIG_DIRS=str(stage / 'etc/xdg') + ':/etc/xdg',
        ATMOSPHERA_CONFIG_DIR=str(config), ATMOSPHERA_CACHE_DIR=str(work / 'cache'),
        ATMOSPHERA_STATE_DIR=str(state), WAYLAND_DEBUG='client')
    for name in ('ATMOSPHERA_LOCK_SESSION', 'ATMOSPHERA_LOCK_GENERATION', 'ATMOSPHERA_LOCK_ROLE', 'ATMOSPHERA_LOCK_ADAPTER'):
        environment.pop(name, None)
    password = secrets.token_hex(16)
    original_hash = run(['sudo', '-n', 'getent', 'shadow', 'tester']).stdout.split(':')[1]
    for name, value in (('credential', password), ('original-shadow-hash', original_hash)):
        path = work / name
        path.touch(mode=0o600)
        path.write_text(value)
    unit = 'locker-contract-state-storage-proof.service'
    saved = None
    observer = None
    authenticated = False
    def journal():
        return run(['journalctl', '--user', '-b', '--no-pager', '-o', 'cat',
            '_SYSTEMD_INVOCATION_ID=' + saved['InvocationID']]).stdout
    try:
        observer = subprocess.Popen(['python3', '-B', str(source / 'Scripts/dev/locker-compositor-observer.py'),
            '--work', str(work / 'observer')], stdin=subprocess.PIPE, env=environment,
            stdout=(work / 'observer-stdout.txt').open('x'), stderr=(work / 'observer-stderr.txt').open('x'))
        wait_for(lambda: (work / 'observer/ready.json').exists(), 10)
        assert not compositor_locked(work, sid), 'existing compositor lock'
        run(['sudo', '-n', 'chpasswd'], input='tester:' + password + '\n')
        keys = ('WAYLAND_DISPLAY', 'NIRI_SOCKET', 'XDG_CURRENT_DESKTOP', 'XDG_SESSION_TYPE',
            'XDG_RUNTIME_DIR', 'DBUS_SESSION_BUS_ADDRESS', 'TMPDIR', 'HOME', 'USER', 'PATH',
            'XDG_CONFIG_DIRS', 'ATMOSPHERA_CONFIG_DIR', 'ATMOSPHERA_CACHE_DIR', 'ATMOSPHERA_STATE_DIR', 'WAYLAND_DEBUG')
        run(['systemd-run', '--user', '--collect', '--unit=' + unit, '--property=KillMode=control-group',
            *['--setenv=' + key + '=' + environment[key] for key in keys if key in environment],
            '--', 'env', '-u', 'ATMOSPHERA_LOCK_SESSION', '-u', 'ATMOSPHERA_LOCK_GENERATION',
            '-u', 'ATMOSPHERA_LOCK_ROLE', '-u', 'ATMOSPHERA_LOCK_ADAPTER', 'qs', '-c', 'atmosphera-lockscreen'])
        saved = dict(line.split('=', 1) for line in run(['systemctl', '--user', 'show', unit,
            '-p', 'InvocationID', '-p', 'ControlGroup', '-p', 'MainPID']).stdout.splitlines())
        (work / 'identity.json').write_text(json.dumps(saved, indent=2))
        wait_for(lambda: re.search(r'ext_session_lock_v1#\d+\.locked\(\)', journal()), 20)
        assert compositor_locked(work, sid)
        run(['wtype', 'wrong-password'], env=environment)
        run(['wtype', '-k', 'Return'], env=environment)
        wait_for(lambda: 'LOCKER_PAM_REJECTED' in journal(), 20)
        assert compositor_locked(work, sid) and 'unlock_and_destroy' not in journal()
        run(['wtype', '-M', 'ctrl', '-k', 'a', '-m', 'ctrl', '-k', 'BackSpace'], env=environment)
        with (work / 'credential').open() as secret:
            run(['wtype', '-'], stdin=secret, env=environment)
        run(['wtype', '-k', 'Return'], env=environment)
        wait_for(lambda: not compositor_locked(work, sid), 20)
        group = Path('/sys/fs/cgroup' + saved['ControlGroup'])
        wait_for(lambda: not group.exists() or not cgroup_pids(group), 15)
        observer.stdin.close()
        assert observer.wait(timeout=15) == 0
        events = [json.loads(line) for line in (work / 'observer/events.jsonl').read_text().splitlines()]
        assert not any(e['kind'] == 'observer-error' for e in events)
        ordering = authenticated_unlocks(events, 1)
        assert ordering and journal().count('unlock_and_destroy') == 1
        assert [e['locked'] for e in compositor_transitions(events)] == [True, False]
        compositor_unlocks = [e for e in events if e['kind'] == 'compositor-log'
            and 'unlocking session' in e.get('message', '')]
        assert len(compositor_unlocks) == 1 and compositor_unlocks[0]['sourceMonotonic'] >= ordering[0]['pamSuccessAt']
        assert inputs() == before, 'standalone locker changed settings'
        assert (state.read_bytes() == state_before) if state.is_file() else not list(state.iterdir())
        authenticated = True
        (work / 'result.json').write_text(json.dumps({'passed': True, 'mode': args.mode,
            'standalone': True, 'wrongPasswordRetainedLock': True, 'pamOrdering': ordering,
            'settingsUnchanged': True, 'stateUnwritable': True, 'identity': saved}, indent=2))
        print('PASS standalone-state-storage', args.mode, work)
    finally:
        if observer is not None and observer.poll() is None:
            if not observer.stdin.closed:
                observer.stdin.close()
            observer.wait(timeout=15)
        if saved:
            (work / 'holder-protocol.txt').write_text('\n'.join(line for line in journal().splitlines() if 'wl_keyboard' not in line))
        if authenticated:
            run(['sudo', '-n', 'chpasswd', '-e'], input='tester:' + original_hash + '\n')
            (work / 'credential').unlink()
            (work / 'original-shadow-hash').unlink()
        else:
            print('Real-PAM recovery required; protected files in', work, file=__import__('sys').stderr)


if __name__ == '__main__':
    main()
