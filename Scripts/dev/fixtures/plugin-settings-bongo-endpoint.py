#!/usr/bin/env python3
"""Literal inert Bongo input/check endpoints. Never inspect an actual device."""
import json
import os
from pathlib import Path
import sys
import time

root = Path(os.environ['PHA_BONGO_CASE'])
command = Path(sys.argv[0]).name
argv = sys.argv[1:]
start = Path('/proc/self/stat').read_text().split(') ', 1)[1].split()[19]
with (root / 'requests.jsonl').open('a') as stream:
    stream.write(json.dumps(dict(command=command, argv=argv, pid=os.getpid(), start=start)) + '\n')
if command == 'which':
    print(str(root / 'bin/evtest'))
elif command == 'id':
    print('bongo-fixture' if argv == ['-un'] else 'input')
elif command == 'sh':
    if '/by-id' in argv[-1]: print('usb-fixture-event-kbd|/dev/input/event90')
    elif '/sys/class/input/' in argv[-1]: print('/dev/input/event90|Controlled keyboard')
    elif 'id -nG' not in argv[-1]: raise SystemExit('unreviewed Bongo shell endpoint')
elif command == 'test':
    if argv[0] != '-e': raise SystemExit('unreviewed Bongo test')
    device = argv[1]
    if 'held-check' in device:
        while not (root / 'check-release').exists(): time.sleep(0.02)
    raise SystemExit(1 if 'missing' in device else 0)
elif command == 'evtest':
    if len(argv) != 1: raise SystemExit('unreviewed Bongo reader')
    device = argv[0]
    if 'retry' in device: raise SystemExit(1)
    action = root / ('event-' + device.rsplit('/', 1)[-1])
    last = None
    while True:
        if action.exists():
            text = action.read_text()
            if text != last:
                print(text, flush=True); last = text
        time.sleep(0.02)
else: raise SystemExit('unknown Bongo endpoint: ' + command)
