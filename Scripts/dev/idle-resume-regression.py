#!/usr/bin/env python3
"""Guest-only real idle protocol and DPMS proof; input is supplied by QMP outside.

Prints READY_RESET/READY_INPUT and waits for INJECTED on stdin. The controller
must inject a physical emulated keyboard event, not wtype/virtual-keyboard input.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from probe_files import ProbeFiles


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--guest-uuid', required=True)
    parser.add_argument('--cases', default='foreign-after,real-input,foreign-before,foreign-fade,own-after,own-before,stages-after,input-fade,queued-foreign,queued-own')
    args = parser.parse_args()
    def run(argv, **kwargs):
        return subprocess.run(argv, check=True, capture_output=True, text=True, timeout=40, **kwargs)
    assert run(['id', '-un']).stdout.strip() == 'tester'
    assert run(['sudo', '-n', 'cat', '/sys/class/dmi/id/product_uuid']).stdout.strip() == args.guest_uuid
    assert run(['systemd-detect-virt', '--vm']).stdout.strip() in ('qemu', 'kvm')
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=False)
    (work / 'tmp').mkdir()
    assert run(['findmnt', '-T', str(work), '-n', '-o', 'FSTYPE']).stdout.strip() not in ('tmpfs', 'ramfs')
    os.environ.update(TMPDIR=str(work / 'tmp'), WAYLAND_DISPLAY='wayland-1',
        NIRI_SOCKET=str(next(Path('/run/user/1000').glob('niri.*.sock'))),
        XDG_RUNTIME_DIR='/run/user/1000', DBUS_SESSION_BUS_ADDRESS='unix:path=/run/user/1000/bus',
        XDG_CURRENT_DESKTOP='niri', XDG_SESSION_TYPE='wayland',
        ATMOSPHERA_DEBUG='1', QML_DISABLE_DISK_CACHE='1', QT_LOGGING_RULES='quickshell.wayland.idle_notify.debug=true')
    env = {k: v for k, v in os.environ.items() if k in (
        'TMPDIR', 'WAYLAND_DISPLAY', 'NIRI_SOCKET', 'XDG_RUNTIME_DIR', 'DBUS_SESSION_BUS_ADDRESS',
        'XDG_CURRENT_DESKTOP', 'XDG_SESSION_TYPE', 'QML_IMPORT_PATH', 'XDG_CONFIG_DIRS',
        'ATMOSPHERA_DEBUG', 'QML_DISABLE_DISK_CACHE', 'QT_LOGGING_RULES', 'PATH')}
    def start(unit, path, extra=None):
        run(['systemd-run', '--user', '--unit=' + unit, '--collect'] +
            ['--setenv=' + k + '=' + v for k, v in (env | (extra or {})).items()] +
            ['--', 'qs', '-p', str(path), '--no-color'])
    def journal(unit):
        return run(['journalctl', '--user', '-u', unit, '--no-pager', '-o', 'short-precise']).stdout
    def wait_for(predicate, seconds=30):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            if predicate():
                return
            time.sleep(.05)
        raise AssertionError('condition deadline')
    def input_event(kind):
        print(kind, flush=True)
        assert sys.stdin.readline().strip() == 'INJECTED'
    def lines(path):
        try:
            return path.read_text().splitlines()
        except FileNotFoundError:
            return []
    dpms = next(Path('/sys/class/drm').glob('card*-Virtual-1/dpms'))
    probe = ProbeFiles(args.source, args.source / 'Scripts/dev/fixtures/idle-resume-probe.qml')
    try:
        for case in args.cases.split(','):
            root = work / case
            config = root / 'config'
            config.mkdir(parents=True)
            custom = [dict(timeout=2, command='echo idle >> ' + str(root / 'custom.txt'),
                resumeCommand='echo resume >> ' + str(root / 'custom.txt'))]
            idle = dict(enabled=False, screenOffTimeout=5, lockTimeout=0, suspendTimeout=0,
                        fadeDuration=2, customCommands=json.dumps(custom),
                        resumeScreenOffCommand='echo resume >> ' + str(root / 'screen-resume.txt'))
            if case == 'stages-after':
                idle.update(lockTimeout=3, suspendTimeout=4, fadeDuration=1,
                    resumeLockCommand='echo resume >> ' + str(root / 'lock-resume.txt'),
                    resumeSuspendCommand='echo resume >> ' + str(root / 'suspend-resume.txt'))
            if case.startswith('queued-'):
                idle.update(screenOffTimeout=2, lockTimeout=3, suspendTimeout=4, fadeDuration=4)
            (config / 'settings.json').write_text(json.dumps(dict(settingsVersion=62, idle=idle,
                general=dict(showChangelogOnStartup=False, lockScreenEnabled=False, lockOnSuspend=False),
                sessionMenu=dict(powerOptions=[dict(action='suspend', enabled=True, keybind='2', command='true')]))))
            unit = 'idle-resume-' + work.name + '-' + case
            foreign = unit + '-foreign'
            run(['niri', 'msg', 'action', 'power-on-monitors'])
            start(foreign, args.source / 'Scripts/dev/fixtures/idle-foreign-inhibitor.qml')
            start(unit, probe.probe, dict(ATMOSPHERA_CONFIG_DIR=str(config),
                ATMOSPHERA_STATE_DIR=str(root / 'state'), ATMOSPHERA_CACHE_DIR=str(root / 'cache')))
            try:
                wait_for(lambda: 'Heartbeat monitor created' in journal(unit))
                # Actions remain disabled until the reset event is observed,
                # even when the external controller responds slowly.
                wait_for(lambda: 'INPUT_ONLY_IDLE true' in journal(unit), 5)
                resets = journal(unit).count('INPUT_ONLY_IDLE false')
                idles = journal(unit).count('INPUT_ONLY_IDLE true')
                input_event('READY_RESET')
                wait_for(lambda: journal(unit).count('INPUT_ONLY_IDLE false') > resets, 5)
                log_baseline = journal(unit)
                run(['qs', 'ipc', '-p', str(probe.probe), 'call', 'idleRegression', 'arm'])
                wait_for(lambda: 'screenOff monitor created' in journal(unit))
                wait_for(lambda: journal(unit).count('INPUT_ONLY_IDLE true') > idles, 5)
                def epoch_log():
                    return journal(unit)[len(log_baseline):]
                def epoch_lines(name):
                    return lines(root / name)
                before = 'before' in case
                if not before:
                    if case.startswith('queued-'):
                        wait_for(lambda: 'Queued idle stage while fade is active: lock' in epoch_log(), 12)
                    elif case in ('foreign-fade', 'input-fade'):
                        wait_for(lambda: 'Idle fired: screenOff' in epoch_log(), 12)
                    else:
                        wait_for(lambda: dpms.read_text().strip() == 'Off', 12)
                raw_before = journal(unit).count('INPUT_ONLY_IDLE false')
                if case == 'input-fade':
                    input_event('READY_INPUT')
                    wait_for(lambda: journal(unit).count('INPUT_ONLY_IDLE false') > raw_before, 3)
                    wait_for(lambda: 'Fade cancelled for: screenOff' in epoch_log(), 3)
                    time.sleep(3)
                    assert dpms.read_text().strip() == 'On'
                    assert not epoch_lines('screen-resume.txt')
                    assert 'Executing action: screenOff' not in epoch_log()
                    print('IDLE_RESUME: PASS ' + case, flush=True)
                    (root / 'result.json').write_text(json.dumps(dict(case=case, passed=True)))
                    continue
                if case == 'real-input':
                    input_event('READY_INPUT')
                    wait_for(lambda: dpms.read_text().strip() == 'On', 3)
                    wait_for(lambda: epoch_lines('screen-resume.txt') == ['resume'], 3)
                else:
                    if case.startswith('own-') or case == 'queued-own':
                        run(['qs', 'ipc', '-p', str(probe.probe), 'call', 'idleRegression', 'inhibit'])
                        wait_for(lambda: 'Started inhibition:' in journal(unit))
                    else:
                        run(['qs', 'ipc', '-p', str(args.source / 'Scripts/dev/fixtures/idle-foreign-inhibitor.qml'),
                             'call', 'probe', 'inhibit'])
                        wait_for(lambda: 'INHIBITOR_REPLY false' in journal(foreign))
                    time.sleep(8 if before else 4)
                    assert dpms.read_text().strip() == ('On' if before else 'Off'), case
                    assert journal(unit).count('INPUT_ONLY_IDLE false') == raw_before, case
                    assert not epoch_lines('screen-resume.txt'), case
                    assert 'resume' not in epoch_lines('custom.txt')
                    if case.startswith('queued-'):
                        assert 'Executing action: lock' not in epoch_log()
                        assert 'Executing action: suspend' not in epoch_log()
                    if not before:
                        # Releasing policy without input must not replay completed actions.
                        if case.startswith('own-') or case == 'queued-own':
                            run(['qs', 'ipc', '-p', str(probe.probe), 'call', 'idleRegression', 'release'])
                        else:
                            run(['qs', 'ipc', '-p', str(args.source / 'Scripts/dev/fixtures/idle-foreign-inhibitor.qml'),
                                 'call', 'probe', 'release'])
                        if not case.startswith('queued-'):
                            time.sleep(8)
                        assert dpms.read_text().strip() == 'Off'
                        assert epoch_log().count('Executing action: screenOff') == 1
                        assert epoch_lines('custom.txt') == ['idle']
                    input_event('READY_INPUT')
                    wait_for(lambda: dpms.read_text().strip() == 'On', 3)
                if not before:
                    wait_for(lambda: epoch_lines('screen-resume.txt') == ['resume'], 3)
                    wait_for(lambda: epoch_lines('custom.txt') == ['idle', 'resume'], 3)
                    if case == 'stages-after':
                        for name in ('lock', 'suspend'):
                            wait_for(lambda: epoch_lines(name + '-resume.txt') == ['resume'], 3)
                    if case == 'real-input':
                        wait_for(lambda: dpms.read_text().strip() == 'Off', 12)
                        input_event('READY_INPUT')
                        wait_for(lambda: dpms.read_text().strip() == 'On', 3)
                        wait_for(lambda: epoch_lines('screen-resume.txt') == ['resume', 'resume'], 3)
                        wait_for(lambda: epoch_lines('custom.txt') == ['idle', 'resume', 'idle', 'resume'], 3)
                else:
                    assert not epoch_lines('custom.txt'), 'suppressed command must not resume'
                print('IDLE_RESUME: PASS ' + case, flush=True)
                (root / 'result.json').write_text(json.dumps(dict(case=case, passed=True)))
            finally:
                (root / 'shell.log').write_text(journal(unit))
                (root / 'foreign.log').write_text(journal(foreign))
                # A failed cold load can already have collected its transient unit.
                for child in (unit, foreign):
                    result = subprocess.run(['systemctl', '--user', 'stop', child], capture_output=True, text=True, timeout=40)
                    if result.returncode not in (0, 5):
                        raise RuntimeError(result.stderr)
    finally:
        probe.close()


if __name__ == '__main__':
    main()
