#!/usr/bin/env python3
"""Test-only publication barrier, never a protocol/authentication implementation.

The real LockClient acquires/refuses against the compositor and performs normal
terminal cleanup. Hold only its final management reply so the diagnostic root
can be sampled before its unchanged Qt.quit callback. EOF/release always exits.
"""
import json
import os
from pathlib import Path
import sys
import time
import runpy


job = json.load(sys.stdin)
assert job['operation'] == 'client', 'rejected diagnostic must never authenticate'
root = Path(os.environ['LOCKER_TERMINAL_BARRIER'])
assert root.is_relative_to(Path('/home/tester/Projects/locker'))
status = job['status']
info_path = root / 'report-info.json'
if info_path.exists():
    info = json.loads(info_path.read_text())
else:
    assert os.getppid() == int(job['pid'])
    helper = runpy.run_path(str(Path(__file__).resolve().parents[2] / 'python/locker-unit.py'))
    info = helper['prepare_report']('terminal-diagnostic')
    info.update(schema=1, identity=helper['proc_identity'](job['pid']), session=status['session'],
        generation=status['generation'], role=status['role'], invocation=os.environ.get('INVOCATION_ID', ''))
    info_path.write_text(json.dumps(info))
assert not status['secure'] and not status['authenticated'], 'diagnostic unexpectedly acquired a lock'
if status['terminal']:
    assert status['settlement'] == 'finished'
    (root / 'terminal.json').write_text(json.dumps(dict(status=status, at=time.monotonic())))
    deadline = time.monotonic() + 90
    while not (root / 'release').exists():
        assert time.monotonic() < deadline, 'terminal publication barrier timed out'
        time.sleep(.05)
print(json.dumps({'ok': True, 'value': {'generation': status['generation'], 'grant': True, 'report': info}}))
