#!/usr/bin/env python3
"""Non-locking process-tree fixture. It never creates/unlocks a session lock."""
import argparse
import json
import os
from pathlib import Path
import signal
import time


parser = argparse.ArgumentParser()
parser.add_argument('--work', type=Path, required=True)
parser.add_argument('--daemonize', action='store_true')
parser.add_argument('--resist-term', action='store_true')
args = parser.parse_args()
assert Path(os.environ['TMPDIR']).is_relative_to('/home/tester/Projects/locker')
if args.daemonize:
    if os.fork():
        raise SystemExit(0)
    os.setsid()
if args.resist_term:
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
child = os.fork()
kind = 'child' if child == 0 else 'parent'
body = Path('/proc/self/stat').read_text().rsplit(')', 1)[1].split()
(args.work / (kind + '.json')).write_text(json.dumps({'pid': os.getpid(), 'start': body[19]}))
while True:
    time.sleep(1)
