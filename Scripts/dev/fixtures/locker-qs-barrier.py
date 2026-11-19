#!/usr/bin/python3
"""Guest test-only launch barrier for an already-owned emergency acquisition.

Only the exact emergency config and role are held. The real compositor, locker,
protocol and PAM are unchanged. Release is a protected fixture file, not IPC.
"""
import json
import os
from pathlib import Path
import sys
import time

work = Path(__file__).resolve().parent.parent
if (os.environ.get('ATMOSPHERA_LOCK_ROLE') == 'real'
        and sys.argv[1:] == ['-c', 'atmosphera-lockscreen']
        and (work / 'delay-real').exists()):
    delay = float((work / 'delay-real').read_text())
    (work / 'real-delay-start.json').write_text(json.dumps({'pid': os.getpid(), 'monotonic': time.monotonic(), 'delay': delay}))
    time.sleep(delay)
    (work / 'real-delay-exec.json').write_text(json.dumps({'pid': os.getpid(), 'monotonic': time.monotonic()}))
if (os.environ.get('ATMOSPHERA_LOCK_ROLE') == 'emergency'
        and sys.argv[1:] == ['-c', 'atmosphera-emergency-lock']
        and (work / 'block-probe').exists()):
    (work / 'probe-at-barrier.json').write_text(json.dumps({'pid': os.getpid(), 'monotonic': time.monotonic()}))
    deadline = time.monotonic() + 60
    while not (work / 'release-probe').exists():
        if time.monotonic() >= deadline:
            raise RuntimeError('test did not release the emergency acquisition barrier')
        time.sleep(.01)
os.execv('/usr/bin/qs', ['/usr/bin/qs', *sys.argv[1:]])
