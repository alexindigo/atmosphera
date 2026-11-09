#!/usr/bin/env python3
"""Prove timeout artifacts and detached-descendant cleanup in the assigned VM."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import time
from unittest.mock import patch
import workspace_guard
from presentation_harness import check_execution_paths, run_harness

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--workspace', type=Path, required=True)
args = parser.parse_args()
work = args.workspace.resolve()
check_execution_paths(parser, work)
work.mkdir()


def console_qs():
    # ps exits 1 when no qs runs; an empty listing is a valid observation.
    return subprocess.run(['ps', '-C', 'qs', '-o', 'pid=,args='], capture_output=True, text=True, timeout=10).stdout


console_before = console_qs()


def check_disk_guard():
    """Reject memory-backed roots and descendants before any write or spawn."""
    alias = work / 'memory-backed-link'
    alias.symlink_to('/tmp', target_is_directory=True)
    rejected = []
    invalid_paths = ['/tmp', '/tmp/child', '/dev/shm', '/dev/shm/child',
                     str(alias), str(alias / 'child')]
    for invalid in invalid_paths:
        for location in ('work', 'TMPDIR'):
            target = invalid if location == 'work' else work
            env = dict(os.environ, TMPDIR=invalid if location == 'TMPDIR' else os.environ['TMPDIR'])
            # On an unfixed harness the receipt write would be the first side
            # effect. Trap it so the regression itself never writes into tmpfs.
            with patch.object(Path, 'write_text', side_effect=AssertionError('write before validation')), \
                    patch('presentation_harness.subprocess.Popen', side_effect=AssertionError('spawn before validation')):
                try:
                    run_harness(['unused'], target, env, 1.0)
                except ValueError as error:
                    assert str(error) == 'use disk-backed workspace and TMPDIR'
                else:
                    raise AssertionError(f'accepted {location}={invalid}')
            rejected.append(dict(location=location, path=invalid))
    # A memory-backed root may itself be a symlink. Its real target and
    # descendants must stay rejected, so model one inside the workspace.
    real_root = work / 'memory-root-target'
    real_root.mkdir()
    linked_root = work / 'memory-root-link'
    linked_root.symlink_to(real_root, target_is_directory=True)
    with patch.object(workspace_guard, 'MEMORY_BACKED_ROOTS', (str(linked_root),)):
        for invalid in (real_root, real_root / 'child', linked_root / 'child'):
            with patch.object(Path, 'write_text', side_effect=AssertionError('write before validation')), \
                    patch('presentation_harness.subprocess.Popen', side_effect=AssertionError('spawn before validation')):
                try:
                    run_harness(['unused'], invalid, dict(os.environ), 1.0)
                except ValueError as error:
                    assert str(error) == 'use disk-backed workspace and TMPDIR'
                else:
                    raise AssertionError(f'accepted path under symlinked root: {invalid}')
            rejected.append(dict(location='symlinked-root', path=str(invalid)))
    # An empty TMPDIR is not "unset": Path('') is the current directory while
    # tempfile ignores it and may fall back to /tmp.
    with patch.object(Path, 'write_text', side_effect=AssertionError('write before validation')), \
            patch('presentation_harness.subprocess.Popen', side_effect=AssertionError('spawn before validation')):
        try:
            run_harness(['unused'], work, dict(os.environ, TMPDIR=''), 1.0)
        except ValueError as error:
            assert str(error) == 'use disk-backed workspace and TMPDIR'
        else:
            raise AssertionError('accepted an empty TMPDIR')
    rejected.append(dict(location='TMPDIR', path=''))
    rejected.extend(check_memory_filesystem())
    return rejected


def check_memory_filesystem():
    """Reject memory-backed storage by filesystem type, not by its path name."""
    # A private user+mount namespace mounts tmpfs at an ordinary disk-backed
    # path. Nothing is written into it; the mount ends with the namespace.
    mount = work / 'tmpfs-mount'
    mount.mkdir()
    probe = '\n'.join([
        'import sys',
        'sys.path.insert(0, sys.argv[1])',
        'import presentation_harness as h',
        'from pathlib import Path',
        'for p in (Path(sys.argv[2]), Path(sys.argv[2]) / "child" / "leaf"):',
        '    try:',
        '        h.require_disk_backed_paths(p)',
        '    except ValueError:',
        '        print("REJECTED", p)',
        '    else:',
        '        print("ACCEPTED", p)',
    ])
    result = subprocess.run(['unshare', '--user', '--map-root-user', '--mount', 'bash', '-c',
                             'mount -t tmpfs -o size=1m none "$2" && exec "$1" -B -c "$3" "$4" "$2"',
                             '_', sys.executable, str(mount), probe, str(Path(__file__).resolve().parent)],
                            capture_output=True, text=True, timeout=30)
    lines = result.stdout.splitlines()
    rejected = [line.split(' ', 1)[1] for line in lines if line.startswith('REJECTED ')]
    accepted = [line.split(' ', 1)[1] for line in lines if line.startswith('ACCEPTED ')]
    assert result.returncode == 0 and len(rejected) == 2 and not accepted, (result.returncode, result.stdout, result.stderr)
    assert not any(mount.iterdir())  # The probe never wrote through to the disk directory.
    return [dict(location='tmpfs-mount', path=path) for path in rejected]


disk_guard = check_disk_guard()
body = '''import os,signal,subprocess,sys,time
child = subprocess.Popen([sys.executable, '-u', '-c', 'import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); print("DETACHED_READY",flush=True); time.sleep(3600)'], start_new_session=True)
print('STALL_READY', child.pid, os.readlink('/proc/self/ns/pid'), flush=True)
time.sleep(3600)
'''
result = []
failures = []

def execute():
    try:
        result.append(run_harness([sys.executable, '-u', '-c', body], work, dict(os.environ), 2.0))
    except BaseException as error:
        failures.append(repr(error))

thread = threading.Thread(target=execute)
thread.start()
deadline = time.monotonic() + 2
incremental = False
while thread.is_alive() and time.monotonic() < deadline:
    path = work / 'shell.log'
    if path.exists() and 'DETACHED_READY' in path.read_text(errors='replace'):
        incremental = not (work / 'execution.json').exists()
        break
    time.sleep(0.02)
thread.join(timeout=12)
assert not thread.is_alive() and not failures, failures
execution = result[0]
receipt = json.loads((work / 'result.json').read_text())
log = (work / 'shell.log').read_text()
console_after = console_qs()
assert incremental and 'STALL_READY' in log and 'HARNESS_TIMEOUT' in log
assert receipt['passed'] is False and execution['timed_out'] and execution['exit_code'] != 0
assert execution['cleanup_complete'] and execution['remaining_pids'] == []
assert execution['elapsed_seconds'] < 10 and console_before == console_after
proof = dict(passed=True, disk_guard=disk_guard, incremental_log_observed=incremental, stalled_execution=execution,
             console_before=console_before, console_after=console_after)
(work / 'selftest.json').write_text(json.dumps(proof, indent=2) + '\n')
print(json.dumps(proof, indent=2))
