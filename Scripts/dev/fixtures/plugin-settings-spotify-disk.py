#!/usr/bin/env python3
"""Independent complete native documents, including bounded generated expiry."""
from copy import deepcopy
import json
from pathlib import Path
import sys
import time

from json_evidence import json_matches

case, out, boundary = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
if boundary.startswith('marker:'):
    _, name, present = boundary.split(':')
    path = case / name
    if present == '1': path.touch()
    else: path.unlink(missing_ok=True)
    raise SystemExit(0)
if boundary.startswith('action-'):
    expected = json.loads(sys.argv[4])
else:
    expected = json.loads((case / 'expectations.json').read_text())[boundary]
deadline = time.monotonic() + (8 if boundary.startswith('action-') else 0)
while True:
    actual = dict(shared=json.loads((case / 'config/settings/plugins/spotify-player.json').read_text()), bar=json.loads((case / 'config/settings/bar.json').read_text()))
    compared = deepcopy(actual)
    for data in [compared['shared']] + [r.get('instanceSettings', {}) for r in compared['bar']['widgets']['left']]:
        if data.get('accessToken', '').startswith('access-'):
            expires = data.get('tokenExpiresAt')
            if not isinstance(expires, (int, float)) or not time.time() * 1000 + 3500000 < expires < time.time() * 1000 + 3610000:
                raise SystemExit('generated expiry outside independent time bounds')
            data['tokenExpiresAt'] = 'bounded-generated-expiry'
    if json_matches(compared, expected): break
    if time.monotonic() >= deadline: raise SystemExit('SPOTIFY_DISK ' + boundary + ': independent complete document mismatch: ' + repr((compared, expected)))
    time.sleep(.05)
(out / (boundary + '.json')).write_text(json.dumps(dict(status='PASS', values=actual), indent=2) + '\n')
print('SPOTIFY_DISK ' + boundary + ': PASS', flush=True)
