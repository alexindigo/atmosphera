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


job = json.load(sys.stdin)
assert job['operation'] == 'client', 'rejected diagnostic must never authenticate'
root = Path(os.environ['LOCKER_TERMINAL_BARRIER'])
assert root.is_relative_to(Path('/home/tester/Projects/locker'))
status = job['status']
assert not status['secure'] and not status['authenticated'], 'diagnostic unexpectedly acquired a lock'
if status['terminal']:
    assert status['settlement'] == 'finished'
    (root / 'terminal.json').write_text(json.dumps(dict(status=status, at=time.monotonic())))
    deadline = time.monotonic() + 90
    while not (root / 'release').exists():
        assert time.monotonic() < deadline, 'terminal publication barrier timed out'
        time.sleep(.05)
print(json.dumps({'ok': True, 'value': {'generation': status['generation'], 'grant': True}}))
