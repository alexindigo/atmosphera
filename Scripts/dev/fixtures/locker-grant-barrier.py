#!/usr/bin/python3
"""Hold a real grant response past the deadline, without changing authority.

Run the real adapter in this process so its client PPid fence remains intact.
The companion exec barrier holds emergency until the real client secures. No
protocol or authentication events are synthesized and no secure client is killed.
"""
import io
import json
from pathlib import Path
import runpy
import sys
import time
from contextlib import redirect_stdout
import os

work = Path(__file__).resolve().parent.parent
if len(sys.argv) == 3 and sys.argv[1].endswith('/Scripts/python/locker-unit.py') and sys.argv[2] == 'manage':
    payload = sys.stdin.read()
    job = json.loads(payload)
    sys.stdin = io.StringIO(payload)
    sys.argv = sys.argv[1:]
    output = io.StringIO()
    code = 0
    with redirect_stdout(output):
        try:
            runpy.run_path(sys.argv[0], run_name='__main__')
        except SystemExit as error:
            code = error.code
    reply = json.loads(output.getvalue())
    if (code == 0 and job['operation'] == 'client' and job.get('role') == 'real'
            and reply['ok'] and reply['value'].get('grant') and not job['status']['requested']):
        adapter = runpy.run_path(sys.argv[0], run_name='locker_grant_adapter')
        with adapter['Session'](job['session']).locked(job['generation']) as descriptor:
            target = descriptor['requestedAt'] + 5
        (work / 'grant-held.json').write_text(json.dumps({'arrived': time.monotonic(), 'target': target}))
        while time.monotonic() < target:
            time.sleep(.01)
    sys.stdout.write(output.getvalue())
    sys.exit(code)
os.execv('/usr/bin/python3', ['/usr/bin/python3', *sys.argv[1:]])
