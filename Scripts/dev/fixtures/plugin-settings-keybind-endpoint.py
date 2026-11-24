#!/usr/bin/env python3
"""Inert cat/glob/detection/hyprctl stages with exact held process identities."""
import glob
import json
import os
from pathlib import Path
import sys
import time

def identity(pid):
    try: return Path('/proc/'+str(pid)+'/stat').read_text().rsplit(')',1)[1].split()[19]
    except FileNotFoundError: return None

if len(sys.argv)>1 and sys.argv[1]=='inspect':
    rows=[json.loads(line) for line in Path(sys.argv[2]).read_text().splitlines()]
    for row in rows:
        if identity(row['pid'])==row['start']: raise SystemExit('still-running '+str(row))
    print('KEYBIND_ENDPOINTS_QUIESCENT '+str(len(rows)),flush=True)
    raise SystemExit(0)

name=Path(sys.argv[0]).name; args=sys.argv[1:]; case=Path(os.environ['KBD_ENDPOINT_CASE'])
stage='hyprctl' if name=='hyprctl' else 'hypr-detect' if name=='sh' and 'echo lua' in args[1] else ('mango-glob' if 'mango' in args[-1] else 'hypr-glob' if 'hypr' in args[-1] else 'niri-glob') if name=='sh' else 'hypr-lua' if args[-1].endswith('.lua') else 'mango-read' if 'mango' in args[-1] else 'hypr-read' if args[-1].endswith('.conf') else 'niri-read'
held=False
if stage==os.environ.get('KBD_HOLD_STAGE'):
    try: (case/'barrier-issued').mkdir(); held=True
    except FileExistsError: pass
row=dict(pid=os.getpid(),start=identity(os.getpid()),name=name,args=args,stage=stage,held=held)
with (case/'endpoints.jsonl').open('a') as log: log.write(json.dumps(row)+'\n'); log.flush(); os.fsync(log.fileno())
if held:
    # The owning QML generation must stop this exact process before engine exit.
    while True: time.sleep(0.05)
if os.environ.get('KBD_FAIL_STAGE')==stage: raise SystemExit(7)
if name=='cat':
    try: sys.stdout.write(Path(args[0]).read_text())
    except FileNotFoundError: raise SystemExit(1)
elif name=='sh':
    if stage=='hypr-detect': print('lua' if Path(args[-1]).is_file() else 'conf')
    else:
        for item in sorted(glob.glob(args[-1])):
            if Path(item).is_file(): print(item)
elif name=='hyprctl':
    assert args==['binds','-j'],args
    if os.environ.get('KBD_MODE')=='edges':
        print('{malformed JSON'); raise SystemExit(0)
    description='replacement lua bind' if os.environ.get('KBD_HOLD_STAGE')=='hyprctl' else 'lua bind'
    print(json.dumps([dict(key='a',modmask=64,dispatcher='__lua',arg='volatile',has_description=True,description=description),dict(key='b',modmask=32,dispatcher='exec',arg='fixture',has_description=False,description='')]))
else: raise SystemExit('unexpected endpoint '+name)
