#!/usr/bin/python3
"""Guest test-only response barrier after the real handover transaction.

The owner remains busy awaiting its own adapter response. The authenticating
emergency exits fail-closed; no grant can run before the harness captures the
real dead-holder framebuffer and releases this response. No protocol is mocked.
"""
import json
import io
import os
from pathlib import Path
import runpy
import sys
import time
from contextlib import redirect_stdout

work = Path(__file__).resolve().parent.parent
arguments = sys.argv[1:]
if arguments[:1] == ['-B']:
    arguments = arguments[1:]
if len(arguments) == 1 and arguments[0].endswith('/Scripts/python/locker-sleep-inhibitor.py'):
    # Observe the real helper's stdout without changing its fd or signals.
    class Tap:
        def __init__(self):
            self.pending = ''
            self.output = (work / 'inhibitor-events.jsonl').open('a', buffering=1)

        def write(self, text):
            sys.__stdout__.write(text)
            self.pending += text
            while '\n' in self.pending:
                line, self.pending = self.pending.split('\n', 1)
                self.output.write(json.dumps({'pid': os.getpid(), 'value': json.loads(line)}) + '\n')
            return len(text)

        def flush(self):
            sys.__stdout__.flush()
            self.output.flush()

    sys.stdout = Tap()
    sys.argv = arguments
    runpy.run_path(arguments[0], run_name='__main__')
    sys.exit(0)
if len(sys.argv) == 3 and sys.argv[1].endswith('/Scripts/python/locker-unit.py') and sys.argv[2] == 'manage':
    payload = sys.stdin.read()
    job = json.loads(payload)
    operation = job['operation']
    if (operation == 'client' and job.get('role') == 'real' and job.get('status', {}).get('ready')
            and (work / 'ready-at-delay').exists() and not (work / 'ready-released.json').exists()):
        # Hold a real prepared client's publication before the actual fenced
        # transaction. Do not hold its descriptor lock or change any status.
        adapter = runpy.run_path(sys.argv[1], run_name='locker_boundary_adapter')
        with adapter['Session'](job['session']).locked(job['generation']) as descriptor:
            requested = descriptor['requestedAt']
        arrived = time.monotonic()
        target = requested + float((work / 'ready-at-delay').read_text())
        (work / 'ready-at-barrier.json').write_text(json.dumps({'pid': os.getpid(), 'arrived': arrived,
            'requestedAt': requested, 'target': target}))
        if arrived >= target:
            raise RuntimeError('natural preparation missed the controlled readiness barrier')
        while True:
            remaining = target - time.monotonic()
            if remaining <= 0:
                break
            time.sleep(min(.002, remaining))
        (work / 'ready-released.json').write_text(json.dumps({'released': time.monotonic(), 'target': target}))
    sys.stdin = io.StringIO(payload)
    sys.argv = sys.argv[1:]
    # Execute in this same process: client/authenticated publications deliberately
    # require the helper's PPid to be the exact GUI client. A proxy child would
    # (correctly) be rejected by that production identity fence.
    stale_suspend = (work / 'hold-after-consume-inspect').exists()
    if stale_suspend and operation == 'consume-suspend':
        (work / 'suspend-consume-seen').touch(mode=0o600)
    hold_inspect = (stale_suspend and operation == 'inspect'
        and (work / 'suspend-consume-seen').exists() and not (work / 'after-consume-inspect.json').exists())
    if not hold_inspect and (operation != 'handover' or (work / 'ready-at-delay').exists()):
        runpy.run_path(sys.argv[0], run_name='__main__')
        raise AssertionError('adapter unexpectedly returned without an exit code')
    output = io.StringIO()
    code = 0
    with redirect_stdout(output):
        try:
            runpy.run_path(sys.argv[0], run_name='__main__')
        except SystemExit as exit:
            code = exit.code
    if code == 0:
        reply = json.loads(output.getvalue())
        if hold_inspect and reply['ok']:
            # Capture the completed real inspect transaction, outside its flock.
            # Authentication remains free to commit before the old bytes arrive.
            (work / 'after-consume-inspect.json').write_text(output.getvalue())
            deadline = time.monotonic() + 45
            while not (work / 'release-after-consume-inspect').exists():
                if time.monotonic() >= deadline:
                    raise RuntimeError('test did not release the post-consume inspect reply')
                time.sleep(.01)
        elif operation == 'handover' and reply['ok'] and reply['value']['committed']:
            (work / 'handover-at-barrier.json').write_text(json.dumps({'pid': os.getpid(), 'monotonic': time.monotonic()}))
            deadline = time.monotonic() + 30
            while not (work / 'release-handover').exists():
                if time.monotonic() >= deadline:
                    raise RuntimeError('test did not release the handover response barrier')
                time.sleep(.01)
    sys.stdout.write(output.getvalue())
    sys.exit(code)
os.execv('/usr/bin/python3', ['/usr/bin/python3', *sys.argv[1:]])
