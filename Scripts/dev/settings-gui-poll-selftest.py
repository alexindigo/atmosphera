#!/usr/bin/env python3
"""Actual Qt/poll scheduler consumers. Run only in the assigned project VM."""
import argparse
import array
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import struct
import subprocess
import sys
import time

from guest_profile import activate_profile, profile_argument
from workspace_guard import require_disk_backed_paths

HERE = Path(__file__).resolve().parent


def helper(address, cpu, output, mode, uid):
    assert os.geteuid() == 0
    signal.alarm(20)
    os.sched_setaffinity(0, {cpu})
    os.sched_setscheduler(0, os.SCHED_FIFO, os.sched_param(1))
    with socket.socket(socket.AF_UNIX) as server:
        server.bind(str(address))
        os.chown(address, uid, -1)
        os.chmod(address, 0o600)
        server.listen(1)
        with server.accept()[0] as peer:
            payload, ancillary, flags, _ = peer.recvmsg(48, socket.CMSG_SPACE(array.array('i').itemsize))
            pid, peer_uid, _ = struct.unpack('3i', peer.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
            assert peer_uid == uid and pid == int(payload.strip()) and not flags
            rights = array.array('i')
            assert len(ancillary) == 1 and ancillary[0][:2] == (socket.SOL_SOCKET, socket.SCM_RIGHTS)
            rights.frombytes(ancillary[0][2])
            assert len(rights) == 1
            fd = rights[0]
            try:
                if mode != 'ready':
                    time.sleep(.03)
                state = lambda: Path(f'/proc/{pid}/stat').read_text().split(') ', 1)[1].split()[0]
                before = state()
                wake = time.monotonic_ns()
                if mode != 'ready':
                    os.write(fd, struct.pack('Q', 1))
                begin = time.monotonic_ns()
                after = state()
                if mode != 'sleep':
                    while time.monotonic_ns() - begin < 80_000_000:
                        pass
                end = time.monotonic_ns()
                output.write_text(json.dumps(dict(pid=pid, beginNs=begin, endNs=end, wakeNs=wake,
                    beforeState=before, afterState=after, subjectPolicy=os.sched_getscheduler(pid),
                    subjectAffinity=sorted(os.sched_getaffinity(pid)), hogPolicy=os.sched_getscheduler(0),
                    hogAffinity=sorted(os.sched_getaffinity(0)))) + '\n')
                os.chown(output, uid, -1)
            finally:
                os.close(fd)
    address.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    profile_argument(parser)
    args = parser.parse_args()
    profile = activate_profile(args.guest_profile)
    assert not profile.console.records
    output = args.output.resolve()
    require_disk_backed_paths(output, os.environ['TMPDIR'])
    output.mkdir(parents=True, exist_ok=False)
    fixture = HERE/'fixtures/native-gui-timing'
    spec = importlib.util.spec_from_file_location('gui_timing', HERE/'settings-gui-timing.py')
    timing = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(timing)
    build = output/'build'
    with (output/'build.log').open('x') as log:
        for argv in (['cmake', '-S', fixture, '-B', build, '-G', 'Ninja'],
                     ['cmake', '--build', build, '--parallel', '4'],
                     ['g++', '-shared', '-fPIC', '-O2', '-pthread', '-o', output/'dispatch.so',
                      HERE/'fixtures/settings-gui-dispatch.cpp', HERE/'fixtures/settings-gui-log.cpp', '-ldl']):
            subprocess.run(list(map(str, argv)), check=True, stdout=log, stderr=subprocess.STDOUT, timeout=60)
    rows = []
    for dispatcher in ('glib', 'unix'):
        for kind in ('poll', 'ppoll'):
            for mode in ('ready', 'sleep', 'wake-preempt'):
                work = output/(dispatcher+'-'+kind+'-'+mode)
                work.mkdir()
                runtime = profile.child_environment('pc-')
                trace = work/'native.trace'
                cpu = min(os.sched_getaffinity(0))
                address = Path(runtime['XDG_RUNTIME_DIR'])/'h.sock'
                env = dict(os.environ, **runtime, QML_IMPORT_PATH=str(build),
                    LD_PRELOAD=str(output/'dispatch.so')+':'+str(build/'libready-delay.so'),
                    ATMOSPHERA_GUI_TRACE=str(trace), READY_POLL_SOCKET=str(address),
                    READY_POLL_KIND=kind, READY_POLL_MODE=mode, QML_DISABLE_DISK_CACHE='1')
                env.pop('QT_NO_GLIB', None)
                if dispatcher == 'unix':
                    env['QT_NO_GLIB'] = '1'
                hog = capture = None
                try:
                    hog = subprocess.Popen(['sudo', '-n', 'env', 'TMPDIR='+os.environ['TMPDIR'],
                        'python3', '-B', str(Path(__file__).resolve()), '--helper', str(address),
                        str(cpu), str(work/'scheduler.json'), mode, str(os.getuid())],
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    deadline = time.monotonic() + 10
                    while not address.exists():
                        assert hog.poll() is None and time.monotonic() < deadline, 'bounded RT control unavailable'
                        time.sleep(.01)
                    capture = timing.SchedulerCapture(trace, runtime['XDG_RUNTIME_DIR'])
                    env.update(capture.environment())
                    process = subprocess.run(['taskset', '-c', str(cpu), 'qs', '-p', str(fixture/'control.qml'), '--no-color'],
                        env=env, capture_output=True, text=True, timeout=20)
                    capture.finish()
                    capture = None
                    text = process.stdout + process.stderr
                    (work/'engine.log').write_text(text)
                    assert process.returncode == 0, text
                    stdout, stderr = hog.communicate(timeout=10)
                    assert hog.returncode == 0, (stdout, stderr)
                    observation = json.loads(re.search(r'READY_POLL_CONTROL (\{[^\n]+\})', text)[1])
                    scheduler = json.loads((work/'scheduler.json').read_text())
                    assert scheduler['beforeState'] == ('R' if mode == 'ready' else 'S'), scheduler
                    assert scheduler['afterState'] == 'R' and scheduler['subjectPolicy'] == os.SCHED_OTHER
                    assert scheduler['hogPolicy'] == os.SCHED_FIFO
                    assert scheduler['subjectAffinity'] == scheduler['hogAffinity'] == [cpu]
                    assert observation['result'] == 1 and observation['ready']
                    window = dict(id='native-'+mode, startNs=int(observation['beginNs']), endNs=int(observation['endNs']))
                    proof = timing.trace_report(trace, [window])
                    assert (1 if dispatcher == 'glib' else 2) in proof['dispatcherKinds']
                    timing.verify_drain(trace, proof['pid'])
                    credited = sum(max(0, min(w['endNs'], window['endNs']) - max(w['startNs'], window['startNs']))
                                   for w in proof['waits'])/1e6
                    if mode == 'ready':
                        assert proof['maximumBusyMs'] >= 75 and credited == 0
                    else:
                        assert credited >= 25, ('real sleeping ready-return poll was not credited', credited)
                        # The helper's wake is an upper bound on the start of
                        # wake-to-run delay. No part of that runnable interval
                        # may be erased, even though the poll really slept first.
                        assert all(w['endNs'] <= scheduler['beginNs'] for w in proof['waits']
                                   if window['startNs'] <= w['startNs'] <= window['endNs'])
                        if mode == 'wake-preempt':
                            assert proof['maximumBusyMs'] >= 75
                    (work/'report.json').write_text(json.dumps(proof, indent=2)+'\n')
                    rows.append(dict(dispatcher=dispatcher, syscall=kind, mode=mode, actual=observation,
                        scheduler=scheduler, creditedSleepMs=credited, maximumBusyMs=proof['maximumBusyMs'], status='PASS'))
                    print(json.dumps(rows[-1]), flush=True)
                finally:
                    try:
                        if capture:
                            capture.finish()
                    finally:
                        try:
                            if hog is not None and hog.poll() is None:
                                hog.communicate(timeout=22)
                        finally:
                            if (capture is None or capture.process.poll() is not None) and (hog is None or hog.poll() is not None):
                                shutil.rmtree(Path(runtime['XDG_RUNTIME_DIR']))
                (output/'result.json').write_text(json.dumps(rows, indent=2)+'\n')
    print('GUI_POLL_SELFTEST: PASS 12/12', flush=True)


if __name__ == '__main__':
    if len(sys.argv) == 7 and sys.argv[1] == '--helper':
        helper(Path(sys.argv[2]), int(sys.argv[3]), Path(sys.argv[4]), sys.argv[5], int(sys.argv[6]))
    else:
        main()
