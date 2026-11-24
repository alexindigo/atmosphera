#!/usr/bin/env python3
"""Independent complete shared document/cache readback, never a cache writer."""
import json
from pathlib import Path
import sys
import time

from json_evidence import require_json_match

case, output = map(Path, sys.argv[1:])
expected = json.loads((case / 'input.json').read_text())['nativeShared']
actual = json.loads((case / 'config/settings/plugins/habitica.json').read_text())
stored = actual['_habiticaCache']
require_json_match(actual, dict(expected, _habiticaCache=stored),
                   'native cache write changed configuration or opaque data')
cache = json.loads(stored)
timestamp = cache['timestamp']
if type(timestamp) is not int or not time.time() - 90 < timestamp <= time.time() + 2:
    raise RuntimeError(f'native cache timestamp outside the observation window: {timestamp!r}')
stats = dict(hp=44, lvl=8, gp=2)
expected_cache = dict(schema=1, sourceUserId='shared', user=dict(profile=dict(name='account-shared'), stats=stats),
                      stats=stats, habits=[], tags=[], timestamp=timestamp, avatarTimestamp=0)
for key, kind in [('dailies', 'daily'), ('todos', 'todo')]:
    expected_cache[key] = [dict(id="shared/task '" + str(i), text='task-shared-' + str(i), type=kind,
                                tags=['tag-a' if i == 0 else 'tag-b'],
                                checklist=[dict(id="item/'", text='check-shared', completed=False)]) for i in range(2)]
require_json_match(cache, expected_cache, 'decoded native cache differs')
(output / 'native-cache.json').write_text(json.dumps(dict(status='PASS', completeSharedDocument=actual, decodedCache=cache), indent=2) + '\n')
print('HTTP_NATIVE_CACHE: PASS', flush=True)
