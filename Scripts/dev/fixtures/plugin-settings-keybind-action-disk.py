#!/usr/bin/env python3
"""Complete independent files and actual directory permission refusal."""
import json
from pathlib import Path
import sys
case,out,name=Path(sys.argv[1]),Path(sys.argv[2]),sys.argv[3]
data=json.loads((case/'input.json').read_text()); scope=data['scope']
directory=case/('config/settings/plugins' if scope=='shared' else 'config/settings')
if name in ('block','unblock'):
    directory.chmod(0o500 if name=='block' else 0o700)
else:
    expected=json.loads((case/'expectations.json').read_text())[name]
    actual=dict(shared=json.loads((case/'config/settings/plugins/keybind-cheatsheet.json').read_text()),bar=json.loads((case/'config/settings/bar.json').read_text()))
    if actual!=expected: raise SystemExit('KEYBIND_ACTION_DISK '+name+': '+repr((actual,expected)))
    (out/(name+'.json')).write_text(json.dumps(dict(status='PASS',values=actual),indent=2)+'\n')
print('KEYBIND_ACTION_DISK '+name+': PASS',flush=True)
