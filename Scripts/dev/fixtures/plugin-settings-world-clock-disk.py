#!/usr/bin/env python3
"""Independent complete native-document oracle for selected clocks."""
import json
from pathlib import Path
import sys

case, output, boundary = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
expected = json.loads((case / 'expectations.json').read_text())[boundary]
actual = dict(shared=json.loads((case / 'config/settings/plugins/world-clock.json').read_text()),
              bar=json.loads((case / 'config/settings/bar.json').read_text()))
if actual != expected:
    raise SystemExit('WORLD_DISK ' + boundary + ': ' + repr((actual, expected)))
(output / (boundary + '.json')).write_text(json.dumps(dict(status='PASS', values=actual), indent=2) + '\n')
print('WORLD_DISK ' + boundary + ': PASS', flush=True)
