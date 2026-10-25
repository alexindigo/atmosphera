"""One deadline and private PID-tree lifetime for the presentation harnesses.

The unprivileged namespace's PID 1 owns all descendants, including processes
which detach into new sessions. Its exit reaps the namespace; no console PID,
name-based process discovery or desktop-shell restart is used for cleanup.
"""
import json
import math
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

DEFAULT_BUDGET = 375.0
TEARDOWN_GRACE = 3.0


def add_execution_arguments(parser):
    parser.add_argument('--budget', type=float, default=DEFAULT_BUDGET,
                        help='single execution budget in seconds, including fixtures and lint')


def remaining_budget():
    """Nested tooling uses its owner's deadline, never a new lifetime."""
    return max(0.01, float(os.environ['PRESENTATION_HARNESS_DEADLINE']) - time.monotonic())


def _live_namespace_tasks(namespace):
    result = []
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            if os.readlink(proc / 'ns/pid') == namespace:
                state = (proc / 'stat').read_text().rsplit(')', 1)[1].split()[0]
                if state not in ('Z', 'X', 'x'):
                    result.append(int(proc.name))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
    return result


def run_harness(argv, work, env, budget):
    """Stream logs and leave a failure receipt even if the child stalls."""
    if not math.isfinite(budget) or budget <= 0:
        raise ValueError('execution budget must be finite and positive')
    work = Path(work).resolve()
    temp = Path(env['TMPDIR']).resolve()
    if any(str(p).startswith(('/tmp/', '/dev/shm/')) for p in (work, temp)):
        raise ValueError('use disk-backed workspace and TMPDIR')
    started = time.monotonic()
    deadline = started + budget
    parent_namespace = os.readlink('/proc/self/ns/pid')
    child_env = dict(env, PRESENTATION_HARNESS_DEADLINE=str(deadline),
                     PRESENTATION_HARNESS_PARENT_NAMESPACE=parent_namespace)
    receipt = work / 'result.json'
    receipt.write_text(json.dumps(dict(passed=False, status='execution started')) + '\n')
    command = ['unshare', '--user', '--map-current-user', '--pid', '--fork',
               '--mount-proc', '--kill-child', '--forward-signals',
               sys.executable, '-B', str(Path(__file__).resolve()), '--supervise',
               str(work), str(deadline), json.dumps(list(map(str, argv))) ]
    process = None
    execution = dict(exit_code=None, timed_out=False, cleanup_complete=False,
                     budget_seconds=budget, teardown_grace_seconds=TEARDOWN_GRACE,
                     parent_namespace=parent_namespace)
    try:
        with (work / 'shell.log').open('xb') as log:
            process = subprocess.Popen(command, cwd=work, env=child_env,
                                       stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            execution['wrapper_pid'] = process.pid
            try:
                execution['exit_code'] = process.wait(timeout=max(0.01, deadline - time.monotonic()) + TEARDOWN_GRACE)
            except subprocess.TimeoutExpired:
                execution['timed_out'] = True
                execution['exit_code'] = 124
    finally:
        # Only the Popen-owned unshare controller is signaled. --kill-child and
        # PID-namespace teardown contain detached private descendants too.
        try:
            if process is not None and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=TEARDOWN_GRACE)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=TEARDOWN_GRACE)
            owned = work / 'namespace.json'
            if owned.exists():
                details = json.loads(owned.read_text())
                namespace = details['namespace']
                assert namespace != parent_namespace
                timed_out = execution['timed_out'] or details.get('timed_out', False)
                execution.update(details)
                execution['timed_out'] = timed_out
                execution['remaining_pids'] = _live_namespace_tasks(namespace)
                execution['cleanup_complete'] = not execution['remaining_pids']
        except Exception as error:
            execution['cleanup_error'] = repr(error)
            execution['cleanup_complete'] = False
        execution['elapsed_seconds'] = time.monotonic() - started
        (work / 'execution.json').write_text(json.dumps(execution, indent=2) + '\n')
        receipt.write_text(json.dumps(dict(passed=False, status='consumer assertions pending', execution=execution), indent=2) + '\n')
    return execution


def write_receipt(work, receipt, execution):
    receipt['execution'] = execution
    receipt['passed'] = bool(receipt['passed'] and execution['exit_code'] == 0 and
                            not execution['timed_out'] and execution['cleanup_complete'])
    (Path(work) / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')


def _supervise(work, deadline, argv):
    assert os.getpid() == 1
    namespace = os.readlink('/proc/self/ns/pid')
    assert namespace != os.environ['PRESENTATION_HARNESS_PARENT_NAMESPACE']
    details = dict(namespace=namespace, supervisor_pid=1, timed_out=False)
    marker = work / 'namespace.json'
    marker.write_text(json.dumps(details))
    stopping = []
    signal.signal(signal.SIGTERM, lambda *_: stopping.append(True))
    signal.signal(signal.SIGINT, lambda *_: stopping.append(True))
    process = subprocess.Popen(argv)
    while process.poll() is None and not stopping and time.monotonic() < deadline:
        try:
            process.wait(timeout=min(0.1, max(0.01, deadline - time.monotonic())))
        except subprocess.TimeoutExpired:
            pass
    if process.poll() is None:
        details['timed_out'] = not stopping
        print('HARNESS_TIMEOUT' if details['timed_out'] else 'HARNESS_INTERRUPTED', flush=True)
        process.terminate()
        try:
            process.wait(timeout=TEARDOWN_GRACE / 2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=TEARDOWN_GRACE / 2)
    details['child_exit_code'] = process.returncode
    marker.write_text(json.dumps(details))
    # Exiting PID 1 makes the kernel terminate/reap every remaining private
    # task, even a grandchild which called setsid().
    return 124 if details['timed_out'] else process.returncode


if __name__ == '__main__':
    assert len(sys.argv) == 5 and sys.argv[1] == '--supervise'
    raise SystemExit(_supervise(Path(sys.argv[2]), float(sys.argv[3]), json.loads(sys.argv[4])))
