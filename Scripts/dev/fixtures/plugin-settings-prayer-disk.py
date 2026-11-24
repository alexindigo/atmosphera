#!/usr/bin/env python3
"""Independent complete prayer-cache/native documents, never a QML projection."""
from copy import deepcopy
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
import time

from json_evidence import json_matches

case, output, boundary = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
seed = json.loads((case / 'input.json').read_text())
expected = dict(shared=deepcopy(seed['shared']), bar=deepcopy(seed['bar']))
if boundary != 'initial':
    data = seed['week']
    source = json.dumps(['shared', 'UK', 3, 0, '0,0,0,0,0,0,0,0,0', None, None], separators=(',', ':'))
    expected['shared'].update(_cacheData=json.dumps(dict(schema=1, source=source, days=data), separators=(',', ':')), _cacheCity='shared', _cacheCountry='UK', _cacheMethod='3', _cacheSchool='0', _cacheSavedAt=datetime.now(timezone.utc).strftime('%Y-%m-%d'), _cacheFajrAngle='null', _cacheIshaAngle='null')
if boundary == 'selected':
    expected['bar']['widgets']['left'][0]['instanceSettings'].update(city='retry', tune=True, tuneFajr=9.9)
deadline = time.monotonic() + 7
while True:
    actual = dict(shared=json.loads((case / 'config/settings/plugins/mawaqit.json').read_text()), bar=json.loads((case / 'config/settings/bar.json').read_text()))
    if json_matches(actual, expected): break
    if time.monotonic() >= deadline: raise SystemExit('PRAYER_DISK ' + boundary + ': ' + repr((actual, expected)))
    time.sleep(0.05)
(output / (boundary + '.json')).write_text(json.dumps(dict(status='PASS', values=actual), indent=2) + '\n')
print('PRAYER_DISK ' + boundary + ': PASS', flush=True)
