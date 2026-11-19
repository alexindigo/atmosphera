#!/usr/bin/env python3
"""Exact guest proof barriers/tracing, never a protocol or auth substitute."""
import json
import os
from pathlib import Path
import sys
import time

root = Path(__file__).resolve().parents[1]
assert root.is_relative_to('/home/tester/Projects/locker')
if os.environ.get('ATMOSPHERA_LOCK_ROLE') == 'emergency' and sys.argv[1:3] == ['-c', 'atmosphera-emergency-lock']:
    hold = root / 'hold-first-report-probe'
    if hold.exists():
        hold.rename(root / 'first-report-probe-claimed')
        (root / 'probe-held.json').write_text(json.dumps({'pid': os.getpid(), 'at': time.monotonic()}))
        end = time.monotonic() + 120
        while time.monotonic() < end:
            time.sleep(.05)
        raise RuntimeError('unreported-probe proof did not retire its exact blocked unit')
    if (root / 'trace-report-probe').exists():
        command = ['strace', '-ff', '-ttt', '-s', '256', '-yy', '-e',
            'trace=openat,close,linkat,fsync,fdatasync,rename,renameat,renameat2,write,writev',
            '-o', str(root / 'probe-syscalls'), '/usr/bin/qs', *sys.argv[1:]]
        os.execvp(command[0], command)
os.execv('/usr/bin/qs', ['qs', *sys.argv[1:]])
