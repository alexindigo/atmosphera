#!/usr/bin/env python3
"""Independent complete native documents and controlled observation handoff."""
import json
from pathlib import Path
import sys

case, output, boundary = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
plugin = json.loads((case / 'input.json').read_text())['plugin']
expected = json.loads((case / 'expectations.json').read_text())[boundary]
actual = dict(shared=json.loads((case / ('config/settings/plugins/' + plugin + '.json')).read_text()),
              bar=json.loads((case / 'config/settings/bar.json').read_text()))
if actual != expected:
    raise SystemExit('POLL_DISK ' + boundary + ': ' + repr((actual, expected)))
(output / (boundary + '.json')).write_text(json.dumps(dict(status='PASS', values=actual), indent=2) + '\n')
if boundary == 'edited':
    # No explicit refresh: only the actual selected Timer may fetch this new data.
    (case / 'observation.json').write_text(json.dumps(dict(connected=True, battery=73)))
print('POLL_DISK ' + boundary + ': PASS', flush=True)
