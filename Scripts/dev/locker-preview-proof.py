#!/usr/bin/env python3
"""Actual main/CLI preview renders and exits without a protocol lock."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time

from locker_framebuffer import Framebuffer
from locker_test_support import manage, require_guest, run, wait_for


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    source, work = require_guest(args.work, Path(__file__).resolve().parents[2])
    sid = manage(source, {'operation': 'discover'})['session']
    before = manage(source, {'operation': 'inspect', 'session': sid})
    assert run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'no'
    stage = work / 'stage'
    run(['bash', '-eu', '-c', 'source "$1/packaging/aur/package.sh"; package', 'stage', str(source)],
        env=dict(os.environ, srcdir=str(source.parent), _gitname=source.name, pkgdir=str(stage), pkgver='0.9.3'), timeout=60)
    root = stage / 'etc/xdg/quickshell/atmosphera'
    entry = root / 'shell.qml'
    config = work / 'config'
    config.mkdir()
    (config / 'settings.json').write_text(json.dumps({'settingsVersion': 62, 'general': {
        'lockScreenEnabled': True, 'lockScreenPlugin': 'default', 'showChangelogOnStartup': False,
        'lockOnSuspend': False}, 'idle': {'enabled': False}}))
    environment = dict(os.environ, XDG_CONFIG_DIRS=str(stage / 'etc/xdg') + ':/etc/xdg',
        ATMOSPHERA_CONFIG_DIR=str(config), ATMOSPHERA_CACHE_DIR=str(work / 'cache'),
        ATMOSPHERA_STATE_DIR=str(work / 'state'), WAYLAND_DEBUG='client')
    units = {}
    observer = None

    def launch(role, path):
        name = 'locker-orphan-proof-preview-' + role + '.service'
        keys = ('WAYLAND_DISPLAY', 'NIRI_SOCKET', 'HYPRLAND_INSTANCE_SIGNATURE', 'XDG_CURRENT_DESKTOP', 'XDG_SESSION_TYPE',
            'XDG_RUNTIME_DIR', 'DBUS_SESSION_BUS_ADDRESS', 'TMPDIR', 'HOME', 'USER', 'PATH', 'XDG_CONFIG_DIRS',
            'ATMOSPHERA_CONFIG_DIR', 'ATMOSPHERA_CACHE_DIR', 'ATMOSPHERA_STATE_DIR', 'WAYLAND_DEBUG')
        run(['systemd-run', '--user', '--collect', '--unit=' + name, '--property=KillMode=control-group',
            '--property=ExitType=cgroup', '--property=TimeoutStopSec=2s',
            *['--setenv=' + key + '=' + environment[key] for key in keys if key in environment],
            '--', 'qs', '-p', str(path), '--no-color'])
        values = dict(line.split('=', 1) for line in run(['systemctl', '--user', 'show', name,
            '-p', 'InvocationID', '-p', 'ControlGroup', '-p', 'MainPID']).stdout.splitlines())
        assert values['InvocationID'] and values['ControlGroup'] and int(values['MainPID']) > 0
        values.update(name=name, start=(Path('/proc') / values['MainPID'] / 'stat').read_text().split(') ', 1)[1].split()[19])
        units[role] = values
        (work / 'unit-identities.json').write_text(json.dumps(units, indent=2))

    def state():
        result = run(['qs', 'ipc', '-p', str(entry), 'call', 'state', 'all'], env=environment)
        return json.loads(result.stdout)

    try:
        observer = subprocess.Popen(['python3', '-B', str(source / 'Scripts/dev/locker-compositor-observer.py'),
            '--work', str(work / 'observer')], stdin=subprocess.PIPE, env=environment,
            stdout=(work / 'observer-stdout.txt').open('w'), stderr=(work / 'observer-stderr.txt').open('w'))
        wait_for(lambda: (work / 'observer/ready.json').exists())
        launch('main', entry)
        def ready():
            result = subprocess.run(['qs', 'ipc', '-p', str(entry), 'call', 'state', 'all'],
                env=environment, capture_output=True, text=True, timeout=5)
            return result.returncode == 0 and 'lockScreenActive' in result.stdout
        wait_for(ready, 20)
        assert state()['state']['lockScreenActive'] is False
        launch('sentinel', source / 'Scripts/dev/fixtures/locker-sentinel.qml')
        console = Framebuffer()
        try:
            def sentinel(name):
                console.capture(work / name)
                return all(console.sentinel_corners())
            wait_for(lambda: sentinel('before.ppm'))
            run([str(root / 'Scripts/bash/atmosphera'), 'lock', 'preview'], env=environment)
            wait_for(lambda: state()['state']['lockScreenActive'] is True)
            def rendered():
                console.capture(work / 'preview.ppm')
                # Preview is intentionally an inset presentation, not a secure
                # full-output surface. Its desktop margins may remain visible.
                center = b''.join(console.pixels[(y * console.width + console.width // 4) * 3:
                    (y * console.width + console.width * 3 // 4) * 3]
                    for y in range(console.height // 4, console.height * 3 // 4))
                return b'\xff\x00\xff' * 8 not in center and len(set(center[i:i+3]
                    for i in range(0, len(center), 3))) > 100
            wait_for(rendered)
            assert run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'no'
            during = manage(source, {'operation': 'inspect', 'session': sid})
            assert during['descriptor'] == before['descriptor'], 'preview created a lock generation'
            run(['wtype', '-k', 'Escape'], env=environment)
            wait_for(lambda: state()['state']['lockScreenActive'] is False)
            wait_for(lambda: sentinel('after.ppm'))
        finally:
            console.close()
        time.sleep(1)
        assert manage(source, {'operation': 'inspect', 'session': sid})['descriptor'] == before['descriptor']
        assert run(['loginctl', 'show-session', sid, '-p', 'LockedHint', '--value']).stdout.strip() == 'no'
        observer.stdin.close()
        assert observer.wait(timeout=10) == 0
        events = [json.loads(line) for line in (work / 'observer/events.jsonl').read_text().splitlines()]
        assert not any(event['kind'] in ('observer-error', 'locked-hint') for event in events)
        native = '\n'.join(event['message'] for event in events if event['kind'] == 'journal')
        assert not re.search(r'ext_session_lock_manager_v1#\d+\.lock\(', native), 'preview requested a real lock'
        assert 'unlock_and_destroy' not in native
        assert 'get_layer_surface' in native, 'preview did not render a real window'
        (work / 'preview-state.json').write_text(json.dumps({'before': before, 'during': during, 'state': state()}, indent=2))
    finally:
        if observer is not None and observer.poll() is None:
            if not observer.stdin.closed:
                observer.stdin.close()
            assert observer.wait(timeout=15) == 0
        for role, record in units.items():
            (work / (role + '-protocol.txt')).write_text('\n'.join(line for line in run(['journalctl', '--user', '-b',
                '--no-pager', '-o', 'cat', '_SYSTEMD_INVOCATION_ID=' + record['InvocationID']]).stdout.splitlines() if 'wl_keyboard' not in line))
            current = run(['systemctl', '--user', 'show', record['name'], '-p', 'InvocationID', '--value']).stdout.strip()
            assert current == record['InvocationID'], 'preview fixture unit replaced'
            run(['systemctl', '--user', 'stop', record['name']])
            group = Path('/sys/fs/cgroup' + record['ControlGroup'])
            assert not group.exists() or not any(path.read_text().split() for path in group.rglob('cgroup.procs'))
            process = Path('/proc') / record['MainPID'] / 'stat'
            assert not process.exists() or process.read_text().split(') ', 1)[1].split()[19] != record['start']
    (work / 'result.txt').write_text('PASS preview\n')
    print('PASS preview', work)


if __name__ == '__main__':
    main()
