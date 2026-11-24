#!/usr/bin/env python3
"""Finite inert fortune endpoint; no external process or user files."""
import json
import os
from pathlib import Path
import signal
import sys
import time

args = sys.argv[1:]
allowed = [['-s', *flags, category] for flags in ([], ['-o'], ['-e'], ['-o', '-e']) for category in ('sibling', 'following', 'replacement', 'oversized')]
if args not in allowed:
    raise SystemExit('unreviewed fortune argv: ' + repr(args))
case = Path(os.environ['PHA_TEXT_CASE'])
def record(event):
    with (case / 'fortune.jsonl').open('a') as output:
        output.write(json.dumps(dict(event=event, argv=args)) + '\n')


record('requested')
try:
    (case / 'hold-next').unlink()
except FileNotFoundError:
    pass
else:
    def cancel(signum, frame):
        record('cancelled')
        (case / 'cancelled').touch()
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, cancel)
    record('held')
    (case / 'held').write_text(json.dumps(dict(pid=os.getpid(), start=Path('/proc/self/stat').read_text().rsplit(')', 1)[1].split()[19])))
    while True:
        time.sleep(0.02)
print('fortune-' + args[-1], flush=True)
