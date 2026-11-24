#!/usr/bin/env python3
"""Independent complete native documents and real permission barrier."""
import json
from pathlib import Path
import sys

from json_evidence import require_json_match

case, output, boundary = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
target = case / 'config/settings/plugins' if sys.argv[4] == 'shared' else case / 'config/settings'
if boundary in ('deny', 'allow'):
    target.chmod(0o500 if boundary == 'deny' else 0o700)
    print('CURRENCY_IO ' + boundary, flush=True)
    raise SystemExit(0)
if boundary in ('hold', 'release'):
    path = case / 'hold'
    if boundary == 'hold':
        path.touch(exist_ok=False)
    else:
        path.unlink()
    raise SystemExit(0)
expected = json.loads((case / 'expectations.json').read_text())[boundary]
actual = dict(shared=json.loads((case / 'config/settings/plugins/currency-exchange.json').read_text()),
              bar=json.loads((case / 'config/settings/bar.json').read_text()))
require_json_match(actual, expected, 'CURRENCY_DISK ' + boundary + ': complete document mismatch')
(output / (boundary + '.json')).write_text(json.dumps(dict(status='PASS', values=actual), indent=2) + '\n')
print('CURRENCY_DISK ' + boundary + ': PASS', flush=True)
