#!/usr/bin/env python3
"""Finite local provider commands over a synthetic HOME, with exact process IDs."""
import json
import os
from pathlib import Path
import sys
import time

stat = Path('/proc/self/stat').read_text().split(') ', 1)[1].split()
name = Path(sys.argv[0]).name
args = sys.argv[1:]
home = Path(os.environ['HOME'])
with Path(os.environ['PHA_PROVIDER_REQUESTS']).open('a') as stream:
    stream.write(json.dumps(dict(pid=os.getpid(), start=stat[19], command=name, argv=args)) + '\n')
if name == 'find' and args and not Path(args[0]).is_relative_to(home):
    # The runtime collaborator must not intercept the real lint file discovery.
    # Its exact source/fixture paths remain inside this isolated case workspace.
    inputs = args[:next((i for i, arg in enumerate(args) if arg.startswith('-')), len(args))]
    case = Path(os.environ['PHA_PROVIDER_CASE']).resolve()
    assert inputs and all(Path(path).resolve().is_relative_to(case) for path in inputs)
    os.execv('/usr/bin/find', ['find', *args])
if (home / 'hold').exists(): time.sleep(2)
if name == 'gh':
    assert args == ['auth', 'token']; print('controlled-copilot')
elif name == 'find':
    root = Path(args[0]); assert root.is_relative_to(home)
    files = sorted(root.rglob('*.jsonl'))
    if '-exec' in args:
        for path in files: print(path.read_text(), end='')
    else:
        for path in files: print(path)
else:
    raise SystemExit('unreviewed provider local executable')
