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
    if operation != 'handover' or (work / 'ready-at-delay').exists():
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
        if reply['ok'] and reply['value']['committed']:
            (work / 'handover-at-barrier.json').write_text(json.dumps({'pid': os.getpid(), 'monotonic': time.monotonic()}))
            deadline = time.monotonic() + 30
            while not (work / 'release-handover').exists():
                if time.monotonic() >= deadline:
                    raise RuntimeError('test did not release the handover response barrier')
                time.sleep(.01)
    sys.stdout.write(output.getvalue())
    sys.exit(code)
os.execv('/usr/bin/python3', ['/usr/bin/python3', *sys.argv[1:]])
