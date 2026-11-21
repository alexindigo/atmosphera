#!/usr/bin/env python3
"""Independent real-helper files at every Music action boundary."""
import hashlib
import json
import os
from pathlib import Path
import sys

root = Path(os.environ['PHA_MUSIC_CASE'])
out = Path(os.environ['PHA_MUSIC_OUTPUT'])
phase = sys.argv[1]
limit = {'pending': 64, 'busy': 64, 'applied': 1, 'folder': 1, 'failed': 1, 'retried': 3}[phase]
folder = 'old music' if phase in ('pending', 'busy', 'applied') else 'new music'
expected = dict(activeProvider='youtube', sortBy='date', downloadDirectory=str(root / folder), downloadCacheMaxMb=limit)
path = root / 'helper/settings.json'
actual = json.loads(path.read_text())
if actual != expected:
    raise AssertionError('Music actual helper mismatch at ' + phase + ': ' + json.dumps(actual))
with (out / 'persisted' / (phase + '.json')).open('x') as stream:
    json.dump(dict(status='PASS', phase=phase, values=actual, sha256=hashlib.sha256(path.read_bytes()).hexdigest()), stream, indent=2)
print('MUSIC_ACTION_DISK: PASS ' + phase, flush=True)
