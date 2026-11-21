#!/usr/bin/env python3
"""Independent complete shared document/cache readback, never a cache writer."""
import json
from pathlib import Path
import sys
import time

case, output = map(Path, sys.argv[1:])
expected = json.loads((case / 'input.json').read_text())['nativeShared']
actual = json.loads((case / 'config/settings/plugins/habitica.json').read_text())
stored = actual['_habiticaCache']
assert actual == dict(expected, _habiticaCache=stored), 'native cache write changed configuration or opaque data'
cache = json.loads(stored)
assert set(cache) == {'schema', 'sourceUserId', 'user', 'stats', 'dailies', 'todos', 'habits', 'tags', 'timestamp', 'avatarTimestamp'}
assert cache['schema'] == 1 and cache['sourceUserId'] == 'shared'
assert cache['user'] == dict(profile=dict(name='account-shared'), stats=dict(hp=44, lvl=8, gp=2))
assert cache['stats'] == dict(hp=44, lvl=8, gp=2)
for key, kind in [('dailies', 'daily'), ('todos', 'todo')]:
    assert cache[key] == [dict(id="shared/task '" + str(i), text='task-shared-' + str(i), type=kind, tags=['tag-a' if i == 0 else 'tag-b'], checklist=[dict(id="item/'", text='check-shared', completed=False)]) for i in range(2)]
assert cache['habits'] == [] and cache['tags'] == [] and cache['avatarTimestamp'] == 0
assert type(cache['timestamp']) is int and time.time() - 90 < cache['timestamp'] <= time.time() + 2
(output / 'native-cache.json').write_text(json.dumps(dict(status='PASS', completeSharedDocument=actual, decodedCache=cache), indent=2) + '\n')
print('HTTP_NATIVE_CACHE: PASS', flush=True)
