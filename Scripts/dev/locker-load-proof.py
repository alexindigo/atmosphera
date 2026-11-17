#!/usr/bin/env python3
"""Actual main, secure sleep ordering and emergency PAM under bounded guest load."""
import argparse
import json
import os
from pathlib import Path
import runpy
import subprocess
import time

from locker_test_support import require_guest, run, wait_for


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--delay', type=float, default=5)
    parser.add_argument('--recover-known-pam-hang', action='store_true')
    args = parser.parse_args()
    assert args.delay == 5, 'load acceptance uses the planned five-second candidate delay'
    source, work = require_guest(args.work, Path(__file__).resolve().parents[2])
    memory = work / 'memory'
    memory.mkdir()
    before = dict((line.split(':', 1)[0], int(line.split()[1])) for line in Path('/proc/meminfo').read_text().splitlines())
    # Half the guest's RAM, or 60% of currently available memory if another
    # guest workload already occupies it. The supervisor also bounds RSS/CPU.
    mib = min(before['MemTotal'] // 2048, before['MemAvailable'] * 3 // (5 * 1024))
    assert mib > 0
    unit = 'locker-memory-load.service'
    assert run(['systemctl', '--user', 'show', unit, '-p', 'MainPID', '--value']).stdout.strip() == '0'
    invocation = None
    pressure_before = Path('/proc/pressure/memory').read_text()
    retired = runpy.run_path(str(source / 'Scripts/dev/locker-lifecycle-regression.py'), run_name='locker_regression_tools')['retire_reconstructible']
    try:
        run(['systemd-run', '--user', '--collect', '--unit=' + unit, '--property=KillMode=control-group',
            '--property=TimeoutStopSec=2s', '--property=MemoryMax=' + str(mib + 64) + 'M',
            '--property=MemorySwapMax=0', '--property=CPUQuota=100%', '--property=TasksMax=16',
            '--setenv=TMPDIR=' + os.environ['TMPDIR'], '--setenv=LOCKER_TEST_VM_UUID=' + os.environ['LOCKER_TEST_VM_UUID'],
            '--', '/usr/bin/python3', '-B', str(source / 'Scripts/dev/fixtures/locker-memory-pressure.py'),
            '--work', str(memory), '--mib', str(mib)])
        invocation = run(['systemctl', '--user', 'show', unit, '-p', 'InvocationID', '--value']).stdout.strip()
        wait_for(lambda: (memory / 'resident.json').exists(), 30)
        resident = json.loads((memory / 'resident.json').read_text())
        identity = run(['systemctl', '--user', 'show', unit, '-p', 'InvocationID', '-p', 'ControlGroup', '-p', 'MainPID']).stdout
        assert 'InvocationID=' + invocation in identity
        assert int(resident['status'].split('VmRSS:', 1)[1].split()[0]) * 1024 >= mib * 1024 * 1024
        (work / 'pressure-start.json').write_text(json.dumps({'requestedMiB': mib, 'meminfoBeforeKiB': before,
            'resident': resident, 'identity': identity, 'pressureBefore': pressure_before,
            'meminfoUnderLoad': Path('/proc/meminfo').read_text()}, indent=2))
        for name, options in (('secure-sleep-handover', ['--sleep-signals']),
                ('responsive-emergency-pam', ['--emergency-auth-before-ready'])):
            command = ['python3', '-B', str(source / 'Scripts/dev/locker-owner-proof.py'), '--main-shell',
                '--case', 'slow', '--delay', '5', '--work', str(work / name), *options]
            if args.recover_known_pam_hang:
                command.append('--recover-known-pam-hang')
            with (work / (name + '-output.txt')).open('x') as log:
                result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=240)
            print((work / (name + '-output.txt')).read_text(), end='', flush=True)
            assert result.returncode == 0, command
            assert run(['systemctl', '--user', 'show', unit, '-p', 'InvocationID', '--value']).stdout.strip() == invocation
            retired(source, work / name)
        (work / 'pressure-end.json').write_text(json.dumps({'memoryPressure': Path('/proc/pressure/memory').read_text(),
            'meminfo': Path('/proc/meminfo').read_text(), 'monotonic': time.monotonic()}, indent=2))
    finally:
        if invocation:
            actual = run(['systemctl', '--user', 'show', unit, '-p', 'InvocationID', '--value']).stdout.strip()
            assert actual in ('', invocation), 'pressure unit changed ownership'
            (memory / 'release').touch(mode=0o600)
            if actual:
                run(['systemctl', '--user', 'stop', unit])
            assert run(['systemctl', '--user', 'show', unit, '-p', 'MainPID', '--value']).stdout.strip() == '0'
            if (memory / 'resident.json').exists():
                resident = json.loads((memory / 'resident.json').read_text())
                process = Path('/proc') / str(resident['pid'])
                assert not process.exists() or process.joinpath('stat').read_text().split(') ', 1)[1].split()[19] != resident['stat'].split(') ', 1)[1].split()[19]
    (work / 'result.txt').write_text('PASS bounded-load; signal/inhibitor proof, not hardware sleep\n')
    print('PASS bounded-load', work)


if __name__ == '__main__':
    main()
