#!/usr/bin/env python3
"""Independent persisted endpoint, invoked between real Todo UI operations."""
import hashlib
import json
import os
from pathlib import Path
import sys

from json_evidence import require_json_match

phase, route, config = sys.argv[1], int(sys.argv[2]), Path(sys.argv[3])
shared = config / 'settings/plugins/todo.json'
if hashlib.sha256(shared.read_bytes()).hexdigest() != os.environ['PHA_TODO_SHARED_SHA256']:
    raise RuntimeError('shared bytes changed')
path = config / 'settings/desktopWidgets.json'
rows = json.loads(path.read_text())['monitorWidgets'][0]['widgets']
expected = dict(todos=[dict(id=91, text='legacy task', completed=False, pageId=0, priority='medium', details='')],
                pages=[dict(id=0, name='Legacy')], current_page_id=0, count=1, completedCount=0, opaque=dict(keep='legacy'))
if phase != 'reset' and route == 0:
    expected['showCompleted'] = False
if phase in ('untouched', 'discard') and route == 0:
    expected['isExpanded'] = True
if phase in ('apply', 'field-reset', 'failed', 'retry'):
    expected['exportEmptySections'] = True
if phase == 'apply':
    expected['exportPath'] = '/synthetic/export'
if phase == 'retry':
    expected['exportFormat'] = 'json'
require_json_match(rows, [dict(id='plugin:todo', tag='keep', instanceSettings=expected), dict(id='plugin:todo')],
                   f'{phase} route {route}: routed Todo rows differ')
record = dict(phase=phase, route=route, placementSha256=hashlib.sha256(path.read_bytes()).hexdigest(), sharedBytesPreserved=True,
              exactExpectedOverrides=True, protectedAndOpaquePreserved=True, siblingUnchanged=True)
out = Path(os.environ['PHA_TODO_OBSERVATIONS']) / (str(route) + '-' + phase + '.json')
with out.open('x') as stream:
    json.dump(record, stream, indent=2)
    stream.write('\n')
print('TODO_DISK: PASS ' + str(route) + ' ' + phase)
