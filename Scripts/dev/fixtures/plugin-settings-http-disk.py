#!/usr/bin/env python3
"""Complete independent documents; await the separately admitted runtime read save."""
import json
from pathlib import Path
import sys
import time

case, output, boundary = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
plugin = json.loads((case / 'input.json').read_text())['plugin']
expected = json.loads((case / 'expectations.json').read_text())[boundary]
deadline = time.monotonic() + (8 if boundary == 'actions' else 0)
while True:
    actual = dict(shared=json.loads((case / ('config/settings/plugins/' + plugin + '.json')).read_text()), bar=json.loads((case / 'config/settings/bar.json').read_text()))
    if actual == expected: break
    if time.monotonic() >= deadline: raise SystemExit('HTTP_DISK ' + boundary + ': ' + repr((actual, expected)))
    time.sleep(0.05)
(output / (boundary + '.json')).write_text(json.dumps(dict(status='PASS', values=actual), indent=2) + '\n')
print('HTTP_DISK ' + boundary + ': PASS', flush=True)
