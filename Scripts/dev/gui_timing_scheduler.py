"""Guest-only, owned tracefs capture and conservative poll sleep attribution.

The native wrapper admits one GUI TID before its first dispatcher entry. Only
scheduler-proven sleep inside a matching kernel poll syscall can split a batch.
Runnable preemption and wake-to-run latency are never idle credit.
"""
import argparse
from decimal import Decimal
import json
import os
from pathlib import Path
import re
import select
import signal
import socket
import struct
import subprocess
import sys
import time
import uuid

EVENTS = {
    'syscalls/sys_enter_poll': 'common_pid == {pid}',
    'syscalls/sys_exit_poll': 'common_pid == {pid}',
    'syscalls/sys_enter_ppoll': 'common_pid == {pid}',
    'syscalls/sys_exit_ppoll': 'common_pid == {pid}',
    'sched/sched_switch': 'prev_pid == {pid} || next_pid == {pid}',
    # A global set_event_pid would discard wakes issued by other threads.
    'sched/sched_waking': 'pid == {pid}',
    'sched/sched_wakeup': 'pid == {pid}',
}


class SchedulerCapture:
    def __init__(self, trace, runtime):
        self.output = Path(str(trace) + '.scheduler')
        self.output.mkdir(exist_ok=False)
        self.socket = Path(runtime) / ('sched-' + uuid.uuid4().hex[:8])
        self.log = (self.output / 'collector.log').open('xb')
        self.process = subprocess.Popen([
            'sudo', '-n', 'env', 'TMPDIR=' + os.environ['TMPDIR'],
            'python3', '-B', str(Path(__file__).resolve()), '--collect',
            '--output', str(self.output), '--socket', str(self.socket),
            '--uid', str(os.getuid())], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=self.log, text=True)
        try:
            assert select.select([self.process.stdout], [], [], 15)[0], 'scheduler collector readiness deadline'
            assert json.loads(self.process.stdout.readline()) == {'ready': True}, 'scheduler collector unavailable'
        except BaseException:
            self.finish()
            raise

    def environment(self):
        return {'ATMOSPHERA_GUI_SCHED_SOCKET': str(self.socket)}

    def finish(self):
        try:
            if self.process.poll() is None:
                self.process.communicate('stop\n', timeout=30)
            assert self.process.returncode == 0, 'scheduler capture failed: ' + str(self.output)
        finally:
            self.log.close()


def collect(args):
    assert os.geteuid() == 0
    def interrupted(signum, frame):
        raise RuntimeError('scheduler collector interrupted: ' + str(signum))
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    output = args.output.resolve(strict=True)
    instance = Path('/sys/kernel/tracing/instances') / ('atcq-' + uuid.uuid4().hex)
    receipt = dict(status='FAIL', clock='mono', timestampResolutionNs=1000,
                   instance=str(instance), filters={}, cpuStats={})
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    created = False
    try:
        listener.bind(str(args.socket))
        os.chown(args.socket, args.uid, -1)
        os.chmod(args.socket, 0o600)
        listener.listen(1)
        instance.mkdir()
        created = True
        (instance / 'tracing_on').write_text('0')
        (instance / 'current_tracer').write_text('nop')
        (instance / 'trace_clock').write_text('mono')
        assert '[mono]' in (instance / 'trace_clock').read_text()
        # The 100-round shell produces about 300k records on its busiest CPU.
        # Retain the complete bounded run, not just its first 8 MiB.
        (instance / 'buffer_size_kb').write_text('65536')
        receipt['bufferSizeKbPerCpu'] = int((instance / 'buffer_size_kb').read_text())
        # Never overwrite old records. Full buffers invalidate the receipt.
        (instance / 'options/overwrite').write_text('0')
        print(json.dumps({'ready': True}), flush=True)
        ready, _, _ = select.select([listener, sys.stdin], [], [], 60)
        if listener not in ready:
            raise RuntimeError('no GUI scheduler admission')
        with listener.accept()[0] as peer:
            peer.settimeout(10)
            pid, uid, _ = struct.unpack('3i', peer.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
            assert uid == args.uid and pid > 1
            receipt['pid'] = pid
            for name, expression in EVENTS.items():
                event = instance / 'events' / name
                rule = expression.format(pid=pid)
                (event / 'filter').write_text(rule)
                receipt['filters'][name] = (event / 'filter').read_text().strip()
                (event / 'enable').write_text('1')
            (instance / 'tracing_on').write_text('1')
            receipt['startNs'] = time.monotonic_ns()
            peer.sendall(b'1')
        listener.close()
        # Owned by the Python runner; EOF also retires the instance on failure.
        assert sys.stdin.readline() == 'stop\n', 'scheduler owner disconnected'
        receipt['endNs'] = time.monotonic_ns()
        assert (instance / 'tracing_on').read_text().strip() == '1'
        assert '[mono]' in (instance / 'trace_clock').read_text()
        for name in EVENTS:
            event = instance / 'events' / name
            assert (event / 'enable').read_text().strip() == '1'
            assert (event / 'filter').read_text().strip() == receipt['filters'][name]
        (instance / 'tracing_on').write_text('0')
        (output / 'trace').write_text((instance / 'trace').read_text())
        for cpu in sorted((instance / 'per_cpu').glob('cpu*')):
            stats = (cpu / 'stats').read_text()
            receipt['cpuStats'][cpu.name] = stats
        for stats in receipt['cpuStats'].values():
            values = dict(line.split(':', 1) for line in stats.splitlines())
            assert all(int(values[key]) == 0 for key in ('overrun', 'commit overrun', 'dropped events')), stats
        assert receipt['cpuStats'], 'no scheduler loss counters'
        receipt['status'] = 'PASS'
    finally:
        listener.close()
        if args.socket.exists():
            args.socket.unlink()
        if created:
            (instance / 'tracing_on').write_text('0')
            (instance / 'events/enable').write_text('0')
            instance.rmdir()
        receipt['removed'] = not instance.exists()
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        for path in output.iterdir():
            os.chown(path, args.uid, -1)


def proven_sleeps(trace, pid, first, last):
    root = Path(str(trace) + '.scheduler')
    receipt = json.loads((root / 'receipt.json').read_text())
    assert receipt['status'] == 'PASS' and receipt['removed'] and receipt['pid'] == pid
    assert receipt['clock'] == 'mono' and receipt['timestampResolutionNs'] == 1000
    assert receipt['startNs'] <= first <= last <= receipt['endNs'], 'native trace outside scheduler coverage'
    assert receipt['cpuStats'] and receipt['filters'] == {name: rule.format(pid=pid) for name, rule in EVENTS.items()}
    for stats in receipt['cpuStats'].values():
        values = dict(line.split(':', 1) for line in stats.splitlines())
        assert all(int(values[key]) == 0 for key in ('overrun', 'commit overrun', 'dropped events'))
    # ftrace's text clock truncates to microseconds. Move every credited start
    # inward by one full tick; credited ends use the earlier printed boundary.
    tick = receipt['timestampResolutionNs']
    row = re.compile(r'\s+([0-9]+\.[0-9]+): (.*)$')
    calls, sleeps = [], []
    entered = sleeping = None
    wake_since_run = False
    seen = set()
    previous = count = 0
    for line in (root / 'trace').read_text().splitlines():
        if line.startswith('#') or not line.strip():
            continue
        match = row.search(line)
        assert match, ('unknown scheduler trace row', line)
        stamp, data = match.groups()
        assert len(stamp.split('.')[1]) >= 6, 'insufficient scheduler timestamp resolution'
        syscall = re.match(r'sys_(poll|ppoll)(\(| -> )', data)
        if syscall:
            name = ('sys_enter_' if syscall[2] == '(' else 'sys_exit_') + syscall[1]
        else:
            name, data = data.split(': ', 1)
            assert name in ('sched_switch', 'sched_waking', 'sched_wakeup'), ('unknown scheduler event', name)
        count += 1
        at = int(Decimal(stamp) * 1_000_000_000)
        assert at >= previous, 'nonmonotonic scheduler clock'
        previous = at
        seen.add(name)
        if name.startswith('sys_enter_'):
            assert entered is None, 'overlapping kernel polls'
            entered = name.removeprefix('sys_enter_'), at
            wake_since_run = False
        elif name.startswith('sys_exit_'):
            assert entered and entered[0] == name.removeprefix('sys_exit_'), 'unmatched kernel poll'
            calls.append(dict(kind=entered[0], startNs=entered[1] + tick, endNs=at))
            entered = None
        elif name == 'sched_switch':
            fields = dict(re.findall(r'(prev_pid|next_pid|prev_state)=([^ ]+)', data))
            if int(fields['next_pid']) == pid:
                assert sleeping is None, 'sleep resumed without a captured wake'
                wake_since_run = False
            if int(fields['prev_pid']) == pid and fields['prev_state'] in ('S', 'D'):
                assert sleeping is None, 'overlapping scheduler sleeps'
                # A remote wake can race the switch tracepoint. If waking
                # already began while the target was running, the later
                # wakeup/switch-in is not a safe idle endpoint.
                if not wake_since_run:
                    sleeping = at + tick
        elif int(re.search(r'\bpid=(\d+)', data)[1]) == pid:
            if sleeping is not None:
                if at > sleeping:
                    sleeps.append((sleeping, at))
                sleeping = None
            wake_since_run = True
    assert any(name.startswith('sys_enter_') for name in seen) and 'sched_switch' in seen, 'missing kernel poll/scheduler evidence'
    assert count == sum(int(dict(line.split(':', 1) for line in stats.splitlines())['entries'])
                        for stats in receipt['cpuStats'].values()), 'truncated scheduler trace'
    assert entered is None or entered[1] + tick >= last, 'unmatched kernel poll before final native event'
    assert sleeping is None or sleeping + tick >= last, 'unmatched sleep before final native event'
    # A terminal process can exit inside a wait; that unmatched interval earns
    # no credit. All completed credit is an intersection, never a W/R estimate.
    return calls, sleeps, receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--collect', action='store_true', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--socket', type=Path, required=True)
    parser.add_argument('--uid', type=int, required=True)
    collect(parser.parse_args())
