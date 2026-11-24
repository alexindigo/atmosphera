#!/usr/bin/env python3
"""Independent complete native documents, allowing only the owned color timestamp."""
from copy import deepcopy
import json
from pathlib import Path
import sys

from json_evidence import require_json_match

case,output,boundary=Path(sys.argv[1]),Path(sys.argv[2]),sys.argv[3]
info=json.loads((case/'input.json').read_text())
expected=json.loads((case/'expectations.json').read_text())[boundary]
actual=dict(shared=json.loads((case/('config/settings/plugins/'+info['plugin']+'.json')).read_text()),
            bar=json.loads((case/'config/settings/bar.json').read_text()))
normalized=deepcopy(actual)
for screen,row in expected['shared'].get('wallpaperColorScreenshots',{}).items():
    if row.get('path')!='@capture':continue
    requests=[json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()]
    captures=[request for request in requests if request['endpoint']=='capture-wallpaper-colors.sh']
    if len(captures) != 1:
        raise RuntimeError(f'{boundary}: expected one capture request, got {len(captures)}')
    observed=normalized['shared']['wallpaperColorScreenshots'][screen]
    path = observed['path']
    if type(path) is not str or path != captures[0]['argv'][0] or not Path(path).is_relative_to(case/'cache'):
        raise RuntimeError(f'{boundary}: unexpected capture path {path!r}')
    timestamp = observed['updatedAt']
    if type(timestamp) not in (int, float) or not timestamp >= info['startedAt']:
        raise RuntimeError(f'{boundary}: unexpected capture timestamp {timestamp!r}')
    observed['path']='@capture';observed['updatedAt']='@timestamp'
require_json_match(normalized, expected, f'{boundary}: native documents differ')
(output/(boundary+'.json')).write_text(json.dumps(dict(status='PASS',values=actual),indent=2)+'\n')
print('WALLPAPER_LIFETIME_DISK '+boundary+': PASS',flush=True)
